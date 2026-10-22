# Fails when a veraPDF count quoted in the docs differs from the reports of
# the same CI run.
#
#     elixir scripts/check_doc_claims.exs verapdf-reports
#
# The claims are listed in scripts/doc_claims.tsv, one per line: the document,
# how many times the claim appears in it, the reports it describes, and the
# quoted text with {rules} and {checks} where the counts go. Each template is
# rendered from each of its reports - "106 of 106", passed of passed plus
# failed - and the rendered text must appear in the document exactly that many
# times, with runs of whitespace collapsed so a claim may wrap across lines.
#
# So a count that changes without the docs fails here, and so does a doc that
# quotes a count no report gives. The docs are never "current as of" anything
# but the commit they sit at.
#
# Plain Elixir with no dependencies, like scripts/check_absolute_paths.exs.

defmodule Tincture.DocClaimsCheck do
  @claims "scripts/doc_claims.tsv"

  def main([reports_dir]) do
    problems =
      @claims
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, _number} -> line == "" or String.starts_with?(line, "#") end)
      |> Enum.flat_map(fn {line, number} -> check(line, number, reports_dir) end)

    case problems do
      [] ->
        IO.puts("doc claims: every quoted veraPDF count matches this run's reports")

      _ ->
        Enum.each(problems, &IO.puts(:stderr, &1))
        System.halt(1)
    end
  end

  def main(_args) do
    IO.puts(:stderr, "usage: elixir scripts/check_doc_claims.exs <reports directory>")
    System.halt(2)
  end

  defp check(line, number, reports_dir) do
    [file, occurrences, reports, template] = String.split(line, "\t", parts: 4)
    expected = String.to_integer(occurrences)
    where = "#{@claims}:#{number}"

    rendered =
      reports
      |> String.split(",")
      |> Enum.map(&render(template, Path.join(reports_dir, &1 <> ".xml")))
      |> Enum.uniq()

    case rendered do
      [text] ->
        found = count(normalise(File.read!(file)), text)

        if found == expected,
          do: [],
          else: [
            "#{where}: #{file} should quote #{inspect(text)} #{expected} time(s), " <>
              "and quotes it #{found} time(s)"
          ]

      several ->
        ["#{where}: its reports disagree, giving #{Enum.map_join(several, " and ", &inspect/1)}"]
    end
  end

  defp render(template, report) do
    details = report |> File.read!() |> details!(report)

    template
    |> String.replace("{rules}", of(details["passedRules"], details["failedRules"]))
    |> String.replace("{checks}", of(details["passedChecks"], details["failedChecks"]))
  end

  # The mrr report's <details passedRules=".." failedRules=".." passedChecks=".."
  # failedChecks=".."> element.
  defp details!(xml, report) do
    case Regex.run(~r/<details ([^>]*)>/, xml) do
      [_, attributes] ->
        ~r/(\w+)="(\d+)"/
        |> Regex.scan(attributes)
        |> Map.new(fn [_, key, value] -> {key, String.to_integer(value)} end)

      nil ->
        raise "#{report}: no <details> element"
    end
  end

  defp of(passed, failed), do: "#{passed} of #{passed + failed}"

  defp normalise(text), do: String.replace(text, ~r/\s+/, " ")

  defp count(haystack, needle), do: length(:binary.matches(haystack, needle))
end

Tincture.DocClaimsCheck.main(System.argv())
