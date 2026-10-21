defmodule Tincture.DocVersionLabelsTest do
  @moduledoc """
  The README, ROADMAP and examples/README quote figures "at" a version: the
  test count, the coverage, the veraPDF counts. Each such label is marked
  `<!-- version -->` before its version number, which a renderer drops, and
  must name the version being built. History - "at 0.3.2, SumatraPDF followed
  them" - is a different kind of sentence with the same shape, so it is listed
  here and left alone.

  A new "at X.Y.Z" that is neither marked nor listed fails, so a figure cannot
  be added without deciding which kind it is.
  """
  use ExUnit.Case, async: true

  @docs ["README.md", "ROADMAP.md", "examples/README.md"]

  # History: what happened at a release, not a figure measured now. Matched
  # against the text with whitespace collapsed.
  @history [
    {"ROADMAP.md", "at 0.3.2, browser-embedded viewers did not follow these links"},
    {"ROADMAP.md", "at 0.3.3 neither did macOS Preview"},
    {"examples/README.md", "at 0.3.2, SumatraPDF followed them"},
    {"examples/README.md", "at 0.3.3, macOS Preview"}
  ]

  @version Mix.Project.config()[:version]

  defp text(file), do: file |> File.read!() |> String.replace(~r/\s+/, " ")

  test "every marked label names the version being built" do
    labels =
      for file <- @docs,
          [_, version] <- Regex.scan(~r/<!-- version -->(\d+\.\d+\.\d+)/, text(file)),
          do: {file, version}

    assert labels != []
    assert Enum.reject(labels, fn {_file, version} -> version == @version end) == []
  end

  test "every unmarked \"at X.Y.Z\" is listed history" do
    unlisted =
      for file <- @docs,
          text = text(file),
          {start, _length} <-
            Regex.scan(~r/\b[Aa]t \d+\.\d+\.\d+/, text, return: :index) |> Enum.map(&hd/1),
          rest = binary_part(text, start, byte_size(text) - start),
          not Enum.any?(@history, fn {history_file, phrase} ->
            history_file == file and String.starts_with?(rest, phrase)
          end),
          do: {file, String.slice(rest, 0, 60)}

    assert unlisted == [],
           "unmarked version labels; mark a current figure with <!-- version --> " <>
             "or list history in this test: #{inspect(unlisted)}"
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
