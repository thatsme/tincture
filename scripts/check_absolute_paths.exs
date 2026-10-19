# Fails when a tracked text file contains an absolute, machine-specific path.
#
#     elixir scripts/check_absolute_paths.exs              # scan the repository
#     elixir scripts/check_absolute_paths.exs --self-test  # check the checker
#
# Tincture is worked on from Windows machines with different drive layouts and
# from macOS, and checked on Linux, so a path that exists on one of them is a
# bug on the others. See "Paths and machines" in CLAUDE.md.
#
# A line that has to carry such a path - a fixture proving that one is
# rejected, say - is exempt only with a marker: the keyword `abs-path-ok`, a
# colon, and a reason of at least three words, in a comment either on the same
# line or on a comment-only line directly above it. The second form exists
# because `mix format` moves an end-of-line comment above the expression it
# follows. A marker on a code line covers only that line, and one separated by
# a blank line covers nothing. A marker without a reason is an error in its own
# right. Nothing is exempted by narrowing a pattern: a pattern that hits a
# legitimate line is answered with a marker someone can review, not with a
# regex that stops seeing it.
#
# Plain Elixir with no dependencies, so it runs the same everywhere `elixir`
# does, and it is not a Mix task: those live in lib/ and would ship.

defmodule Tincture.AbsolutePathCheck do
  # A drive letter starts a token: the start of the line, whitespace, a quote,
  # or one of ( = [ {. That is what keeps URL schemes - https:// - out.
  @patterns [
    {"drive-letter path", ~r/(?:^|[\s"'`(=\[{])([A-Za-z]:[\/\\][^\s"'`)\]},;]*)/},
    {"macOS home directory", ~r/(\/Users\/[A-Za-z0-9._-]+[^\s"'`)\]},;]*)/},
    {"Linux home directory", ~r/(\/home\/[A-Za-z0-9._-]+[^\s"'`)\]},;]*)/},
    # abs-path-ok: the pattern that detects this directory name
    {"Windows profile directory", ~r/([^\s"'`(]*AppData[^\s"'`)\]},;]*)/}
  ]

  # Assembled from two parts so that this file's own source does not carry the
  # marker keyword without a reason - which the check would rightly flag.
  @marker "abs-path" <> "-ok:"
  @comment_openers ["#", "//", "<!--", "%", "--"]
  @min_reason_words 3
  @binary_probe_bytes 8192

  def main(["--self-test"]), do: self_test()
  def main([]), do: scan()

  def main(other) do
    IO.puts(:stderr, "unknown arguments: #{inspect(other)}")
    IO.puts(:stderr, "usage: elixir scripts/check_absolute_paths.exs [--self-test]")
    System.halt(2)
  end

  @doc """
  The problems on one line, as `{label, matched_text}`, given the line before
  it. Empty when the line is clean or carries a valid exemption.
  """
  def check_line(line, previous \\ "") do
    hits =
      for {label, regex} <- @patterns, [_, text] <- Regex.scan(regex, line), do: {label, text}

    case {marker_status(line), hits} do
      {:invalid, _hits} -> [{"marker without a reason", marker_text(line)}]
      {:valid, _hits} -> []
      {:none, []} -> []
      {:none, hits} -> if exempted_from_above?(previous), do: [], else: hits
    end
  end

  # A valid marker on a line holding nothing but a comment exempts the next
  # line, which is where `mix format` leaves an end-of-line comment.
  defp exempted_from_above?(previous) do
    trimmed = String.trim_leading(previous)

    Enum.any?(@comment_openers, &String.starts_with?(trimmed, &1)) and
      marker_status(previous) == :valid
  end

  # :none when the line has no marker, :valid when it has one in a comment with
  # a reason of at least @min_reason_words words, :invalid otherwise.
  defp marker_status(line) do
    case :binary.match(line, @marker) do
      :nomatch ->
        :none

      {at, length} ->
        before = binary_part(line, 0, at)

        reason =
          line
          |> binary_part(at + length, byte_size(line) - at - length)
          |> String.replace("-->", "")

        words = Regex.scan(~r/[A-Za-z]{2,}/, reason)

        if in_comment?(before) and length(words) >= @min_reason_words, do: :valid, else: :invalid
    end
  end

  defp in_comment?(before) do
    trimmed = String.trim_trailing(before)
    Enum.any?(@comment_openers, &String.ends_with?(trimmed, &1))
  end

  defp marker_text(line) do
    {at, _length} = :binary.match(line, @marker)
    line |> binary_part(at, byte_size(line) - at) |> String.trim()
  end

  ## Scan

  defp scan do
    # The one absolute path this needs is derived at run time, never written in.
    {root, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"])
    File.cd!(String.trim(root))

    {listing, 0} = System.cmd("git", ["ls-files", "-z"])
    files = listing |> String.split(<<0>>, trim: true) |> Enum.sort()

    {text_files, binary_count} =
      Enum.reduce(files, {[], 0}, fn file, {text, binaries} ->
        if binary?(file), do: {text, binaries + 1}, else: {[file | text], binaries}
      end)

    problems = text_files |> Enum.reverse() |> Enum.flat_map(&check_file/1)

    Enum.each(problems, fn {file, number, label, text} ->
      IO.puts("#{file}:#{number}: #{text}  (#{label})")
    end)

    IO.puts(
      "scanned #{length(text_files)} text files (#{binary_count} binary skipped, " <>
        "#{length(files)} tracked); #{length(problems)} problem(s)"
    )

    cond do
      text_files == [] ->
        IO.puts(:stderr, "no text files were scanned - refusing to pass on an empty scan")
        System.halt(1)

      problems != [] ->
        System.halt(1)

      true ->
        :ok
    end
  end

  # A file with a NUL byte in its first 8 KB is treated as binary.
  defp binary?(file) do
    case File.open(file, [:read, :binary], &IO.binread(&1, @binary_probe_bytes)) do
      {:ok, data} when is_binary(data) -> String.contains?(data, <<0>>)
      {:ok, :eof} -> false
      {:error, _reason} -> false
    end
  end

  defp check_file(file) do
    lines =
      file |> File.read!() |> String.split("\n") |> Enum.map(&String.trim_trailing(&1, "\r"))

    [""]
    |> Enum.concat(lines)
    |> Enum.zip(lines)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{previous, line}, number} ->
      for {label, text} <- check_line(line, previous), do: {file, number, label, text}
    end)
  end

  ## Self-test

  @flagged [
    # abs-path-ok: self-test case that must be flagged
    ~S|linked({:file, "C:/tmp/a.pdf"})|,
    # abs-path-ok: self-test case that must be flagged
    ~S|D:\dev\x|,
    # abs-path-ok: self-test case that must be flagged
    "see /Users/alex/x",
    # abs-path-ok: self-test case that must be flagged
    "see /home/alex/x",
    # abs-path-ok: self-test case that must be flagged
    ~S|path = C:\Users\x\AppData\Local|,
    "x = 1 # " <> @marker,
    "x = 1 # " <> @marker <> " too short",
    # abs-path-ok: self-test case that must be flagged
    ~S|linked({:file, "C:/tmp/a.pdf"}) # see above|,
    # A marker on a code line covers only that line, not the one below it.
    # abs-path-ok: self-test case that must be flagged
    {"x = 1 # " <> @marker <> " documented reason with several words", ~S|"C:/tmp/a.pdf"|},
    # A marker above a blank line covers nothing.
    # abs-path-ok: self-test case that must be flagged
    {"", ~S|"C:/tmp/a.pdf"|},
    # A comment above with no marker exempts nothing.
    # abs-path-ok: self-test case that must be flagged
    {"# an ordinary comment", ~S|"C:/tmp/a.pdf"|}
  ]

  @not_flagged [
    "https://hex.pm/x",
    "file:///x",
    "mailto:a@b",
    ~S|{:file, "a/b.pdf"}|,
    "../x",
    # abs-path-ok: self-test case for a valid exemption
    ~S|linked({:file, "C:/tmp/a.pdf"}) # | <>
      @marker <> " rejection fixture for drive-letter paths",
    "x = 1 # " <> @marker <> " documented reason with several words",
    # The marker on the comment-only line directly above, where `mix format`
    # puts it.
    {
      "        # " <> @marker <> " rejection fixture for drive-letter paths",
      # abs-path-ok: self-test case for a valid exemption
      ~S|        linked({:file, "C:/tmp/a.pdf"})|
    }
  ]

  defp self_test do
    failures =
      Enum.filter(@flagged, &(run_case(&1) == [])) ++
        Enum.reject(@not_flagged, &(run_case(&1) == []))

    total = length(@flagged) + length(@not_flagged)

    Enum.each(failures, fn test_case ->
      expected = if test_case in @flagged, do: "flagged", else: "clean"

      IO.puts(
        "FAIL (expected #{expected}): #{inspect(test_case)} -> #{inspect(run_case(test_case))}"
      )
    end)

    IO.puts("self-test: #{total - length(failures)} of #{total} cases correct")
    if failures != [], do: System.halt(1)
  end

  # A case is a line, or `{line_above, line}`.
  defp run_case({previous, line}), do: check_line(line, previous)
  defp run_case(line), do: check_line(line)
end

Tincture.AbsolutePathCheck.main(System.argv())
