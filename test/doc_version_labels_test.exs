defmodule Tincture.DocVersionLabelsTest do
  @moduledoc """
  The README, ROADMAP and examples/README quote figures "at" a version: the
  test count, the coverage, the veraPDF counts. Those current labels must name
  the version being built. History - "at 0.3.2, SumatraPDF followed them" - is
  a different kind of sentence with the same shape, and keeps its version.

  Both kinds are listed here, exhaustively, so the documents carry no markup.
  A current label is identified by the text just before its "at": a changed
  version in one fails. An "at X.Y.Z" on neither list fails too, so a figure
  cannot be added without deciding which kind it is.
  """
  use ExUnit.Case, async: true

  @docs ["README.md", "ROADMAP.md", "examples/README.md"]

  # Current labels: the text immediately before "at <version>", and how many
  # times it occurs in the file. Matched against the text with whitespace
  # collapsed.
  @current [
    {"README.md", "the counts are as measured", 1},
    {"README.md", "Passes veraPDF 1.30.2 in CI on every commit;", 1},
    {"README.md", "may still move before 1.0.", 1},
    {"README.md", "% in CI", 1},
    {"ROADMAP.md", "(PDF/UA-1 profile) in CI on every commit;", 2},
    {"ROADMAP.md", "2u, 2a | passes veraPDF 1.30.2 in CI on every commit;", 1},
    {"ROADMAP.md", "No required runtime dependencies.", 1},
    {"ROADMAP.md", "% in CI", 1},
    {"ROADMAP.md", "`examples/output/archival.pdf` passes veraPDF 1.30.2 in CI on every commit;",
     1},
    {"examples/README.md",
     "**Validated.** Passes veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit;", 2},
    {"examples/README.md", "at four flavours;", 1},
    {"examples/README.md", "both pass veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit;",
     1}
  ]

  # History: what happened at a release, not a figure measured now. The text
  # from its "at" onwards.
  @history [
    {"ROADMAP.md", "at 0.3.2, browser-embedded viewers did not follow these links"},
    {"ROADMAP.md", "at 0.3.3 neither did macOS Preview"},
    {"examples/README.md", "at 0.3.2, SumatraPDF followed them"},
    {"examples/README.md", "at 0.3.3, macOS Preview"}
  ]

  @version Mix.Project.config()[:version]

  defp text(file), do: file |> File.read!() |> String.replace(~r/\s+/, " ")

  # Every "at X.Y.Z" in a file: the text before it, the text from it on, and
  # its version.
  defp labels(file) do
    text = text(file)

    for [{start, _length}, {v_start, v_length}] <-
          Regex.scan(~r/\b[Aa]t (\d+\.\d+\.\d+)/, text, return: :index) do
      {binary_part(text, 0, start), binary_part(text, start, byte_size(text) - start),
       binary_part(text, v_start, v_length)}
    end
  end

  defp current_prefix(file, before) do
    Enum.find_value(@current, fn {current_file, prefix, _count} ->
      if current_file == file and String.ends_with?(before, prefix <> " "), do: prefix
    end)
  end

  defp history?(file, rest) do
    Enum.any?(@history, fn {history_file, phrase} ->
      history_file == file and String.starts_with?(rest, phrase)
    end)
  end

  test "every \"at X.Y.Z\" is a listed current label or listed history" do
    unclassified =
      for file <- @docs,
          {before, rest, _version} <- labels(file),
          current_prefix(file, before) == nil and not history?(file, rest),
          do: {file, String.slice(rest, 0, 60)}

    assert unclassified == [],
           "version labels on neither list; add each to @current or @history: " <>
             inspect(unclassified)
  end

  test "every current label names the version being built" do
    stale =
      for file <- @docs,
          {before, _rest, version} <- labels(file),
          prefix = current_prefix(file, before),
          prefix != nil and version != @version,
          do: {file, prefix, version}

    assert stale == []
  end

  test "every listed current label occurs as often as listed" do
    for {file, prefix, count} <- @current do
      found =
        Enum.count(labels(file), fn {before, _rest, _version} ->
          String.ends_with?(before, prefix <> " ")
        end)

      assert found == count, "#{file}: #{inspect(prefix)} labels #{found} times, listed #{count}"
    end
  end

  test "every listed history sentence is still there" do
    for {file, phrase} <- @history do
      assert text(file) =~ phrase, "#{file} no longer says #{inspect(phrase)}"
    end
  end

  test "the install snippet names the version being built" do
    assert File.read!("README.md") =~ ~s({:tincture, "~> #{@version}"})
  end
end
