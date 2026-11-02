# Fails when a tracked text file in the working tree has a carriage return.
#
#     elixir scripts/check_line_endings.exs              # scan the working tree
#     elixir scripts/check_line_endings.exs --self-test  # check the checker
#
# .gitattributes stores every text file with LF, but it normalises on commit,
# not in the working tree: a tool that writes CRLF on Windows leaves the file
# CRLF, or mixed, until it is committed, and everything that reads the file in
# between reads the CR. That is not cosmetic here: Tincture.Font.Standard
# parses the base-14 metric tables with regexes anchored at `;$`, which a CR
# defeats, and a CR inside an @doc heredoc is part of the string the docs
# render. So the working tree is checked, not the index.
#
# Scanned: the tracked files under lib/, test/, priv/, scripts/ and examples/
# that git treats as text, by .gitattributes and by its own detection
# (`git ls-files --eol`). Each line holding a CR is reported as file:line.
#
# Plain Elixir with no dependencies, so it runs the same everywhere `elixir`
# does, and it is not a Mix task: those live in lib/ and would ship.

defmodule Tincture.LineEndingCheck do
  @directories ["lib", "test", "priv", "scripts", "examples"]

  def main(["--self-test"]), do: self_test()
  def main([]), do: scan()

  def main(other) do
    IO.puts(:stderr, "unknown arguments: #{inspect(other)}")
    IO.puts(:stderr, "usage: elixir scripts/check_line_endings.exs [--self-test]")
    System.halt(2)
  end

  @doc """
  The 1-based numbers of the lines in `content` that hold a carriage return,
  whether as part of CRLF or alone.
  """
  def cr_lines(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _number} -> String.contains?(line, "\r") end)
    |> Enum.map(fn {_line, number} -> number end)
  end

  @doc """
  The tracked text files under the scanned directories, by `git ls-files
  --eol`: a file is text unless git's index or its attributes say otherwise.
  """
  def text_files do
    {listing, 0} = System.cmd("git", ["ls-files", "--eol", "-z", "--" | @directories])

    listing
    |> String.split(<<0>>, trim: true)
    |> Enum.map(&parse_eol_entry/1)
    |> Enum.split_with(fn {_file, text?} -> text? end)
    |> then(fn {text, binary} -> {Enum.map(text, &elem(&1, 0)), length(binary)} end)
  end

  # "i/lf    w/crlf  attr/text=auto eol=lf \tpath": the path follows the tab.
  # A file is binary when git stored it as -text, or its attributes unset text
  # (`binary` in .gitattributes is -text -diff).
  defp parse_eol_entry(entry) do
    [info, file] = String.split(entry, "\t", parts: 2)
    [index, _worktree | attributes] = String.split(info)
    attributes = Enum.join(attributes, " ")
    binary? = index == "i/-text" or String.contains?(attributes, "-text")
    {file, not binary?}
  end

  @doc """
  The problems in one file, as `{file, line_number}`.
  """
  def check_file(file) do
    case File.read(file) do
      {:ok, content} -> for number <- cr_lines(content), do: {file, number}
      {:error, :enoent} -> []
    end
  end

  ## Scan

  defp scan do
    # The one absolute path this needs is derived at run time, never written in.
    {root, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"])
    File.cd!(String.trim(root))

    {files, binary_count} = text_files()
    problems = Enum.flat_map(files, &check_file/1)

    Enum.each(problems, fn {file, number} ->
      IO.puts("#{file}:#{number}: carriage return")
    end)

    IO.puts(
      "scanned #{length(files)} text files under #{Enum.join(@directories, "/, ")}/ " <>
        "(#{binary_count} binary skipped); #{length(problems)} line(s) with a carriage return"
    )

    cond do
      files == [] ->
        IO.puts(:stderr, "no text files were scanned - refusing to pass on an empty scan")
        System.halt(1)

      problems != [] ->
        IO.puts(
          :stderr,
          "A tool wrote CRLF into the working tree. Rewrite each file with LF line endings. " <>
            "`mix format` does not: it keeps a CR inside a string, an @doc heredoc included. " <>
            "A script that writes text on Windows must write bytes, or its newlines become CRLF."
        )

        System.halt(1)

      true ->
        :ok
    end
  end

  ## Self-test

  @flagged [
    {"a CRLF file", "one\r\ntwo\r\n", [1, 2]},
    {"a mixed file", "one\ntwo\r\nthree\n", [2]},
    {"a lone CR", "one\rtwo\n", [1]},
    {"a CR on the last line, with no newline", "one\ntwo\r", [2]}
  ]

  @not_flagged [
    {"an LF file", "one\ntwo\n"},
    {"an LF file with no final newline", "one\ntwo"},
    {"an empty file", ""},
    {"a backslash-r written as text", "one \\r two\n"}
  ]

  # `git ls-files --eol` entries, and whether each is scanned as text.
  @classification [
    {"i/lf    w/lf    attr/text=auto eol=lf \tlib/tincture.ex", true},
    {"i/lf    w/crlf  attr/text=auto eol=lf \tlib/tincture.ex", true},
    {"i/-text w/-text attr/-text            \texamples/output/form.pdf", false},
    {"i/-text w/-text attr/text=auto eol=lf \texamples/fonts/LiberationSans-Regular.ttf", false}
  ]

  # Each case runs on a scratch file in tmp/, which is gitignored, so the
  # check reads a real file the way the scan does.
  defp self_test do
    {root, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"])
    File.cd!(String.trim(root))
    dir = Path.join("tmp", "line-endings-self-test")
    File.mkdir_p!(dir)

    try do
      failures =
        Enum.flat_map(@flagged, fn {name, content, expected} ->
          case run_case(dir, content) do
            ^expected -> []
            got -> ["FAIL (expected lines #{inspect(expected)}): #{name} -> #{inspect(got)}"]
          end
        end) ++
          Enum.flat_map(@not_flagged, fn {name, content} ->
            case run_case(dir, content) do
              [] -> []
              got -> ["FAIL (expected clean): #{name} -> lines #{inspect(got)}"]
            end
          end) ++ classification_failures()

      Enum.each(failures, &IO.puts/1)
      total = length(@flagged) + length(@not_flagged) + length(@classification)
      IO.puts("self-test: #{total - length(failures)} of #{total} cases correct")
      if failures != [], do: System.halt(1)
    after
      File.rm_rf!(dir)
    end
  end

  defp run_case(dir, content) do
    file = Path.join(dir, "case.txt")
    File.write!(file, content)
    file |> check_file() |> Enum.map(fn {_file, number} -> number end)
  end

  defp classification_failures do
    for {entry, text?} <- @classification,
        parse_eol_entry(entry) != {entry |> String.split("\t") |> List.last(), text?},
        do: "FAIL (expected text? #{text?}): #{inspect(entry)}"
  end
end

Tincture.LineEndingCheck.main(System.argv())
