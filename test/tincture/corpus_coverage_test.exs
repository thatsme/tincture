defmodule Tincture.CorpusCoverageTest do
  @moduledoc """
  What the validated documents actually exercise.

  veraPDF scores rules, not features, and a rule with nothing to match counts
  as passed. So a clean run says only as much as the documents handed to it:
  tagged links scored 106 of 106 for two releases while being unreachable from
  the structure tree, because `compliant.pdf` contained no link annotations.

  This pins the difference between what the API can emit and what the validated
  corpus does emit, so the gap is a number that changes visibly rather than
  something nobody thought to look at.
  """

  use ExUnit.Case, async: true

  alias Tincture.PDF.Structure

  # The documents the release checklist runs veraPDF against. `archival.pdf` is
  # validated at 2a, which carries the same tagging rules as PDF/UA.
  @validated ~w(compliant accessible archival)

  # Structure types the corpus does not emit. Every one is a set of rules that
  # has never run against Tincture's output.
  #
  # This list is meant to shrink. A failure here means either a type became
  # covered — delete it — or a new type arrived uncovered, in which case adding
  # it is the cheap part and knowing what it owes is the point.
  #
  # Two are known defects rather than merely unexercised:
  #
  #   * `Note` fails ISO 14289-1 clause 7.9 outright. A Note element requires
  #     an /ID entry and Tincture writes none. Fixed in 0.3.1.
  #   * `Form` does not exist in the vocabulary at all, so a widget annotation
  #     cannot be nested in one as clause 7.18.4 requires. Form fields are
  #     therefore not usable in a PDF/UA document.
  #
  # `H3` through `H6` are the quiet ones: heading levels the corpus stops short
  # of, so clause 7.4's nesting rules have only ever seen two levels deep.
  @never_validated ~w(Art BlockQuote Code Div Formula H H3 H4 H5 H6 Index Note
                      Part Quote Reference Span TFoot TOC TOCI)

  defp emitted_structure_types do
    known = Structure.tags() |> Map.values() |> MapSet.new()

    @validated
    |> Enum.flat_map(fn name ->
      path = Path.join(["examples", "output", "#{name}.pdf"])

      case File.read(path) do
        {:ok, binary} ->
          ~r|/S /([A-Za-z0-9]+)|
          |> Regex.scan(binary)
          |> Enum.map(fn [_, type] -> type end)

        {:error, _reason} ->
          flunk("#{path} is missing. Run `mix examples` before this suite.")
      end
    end)
    # /S also introduces an action subtype (/S /URI) and an output intent
    # (/S /GTS_PDFA1). Only structure types are of interest here.
    |> Enum.filter(&MapSet.member?(known, &1))
    |> MapSet.new()
  end

  test "the corpus exercises the structure types it is believed to" do
    emitted = emitted_structure_types()
    all = Structure.tags() |> Map.values() |> MapSet.new()
    missing = all |> MapSet.difference(emitted) |> Enum.sort()

    assert missing == Enum.sort(@never_validated), """
    The set of structure types the validated corpus never emits has changed.

    Never emitted now: #{inspect(missing)}
    Recorded as such:  #{inspect(Enum.sort(@never_validated))}

    If a type is newly covered, remove it from @never_validated. If a type is
    newly uncovered, add it — and note that its PDF/UA rules have never run
    against Tincture's output, so "the corpus passes" says nothing about it.
    """
  end

  test "a link is exercised, since that is the gap this list was written for" do
    emitted = emitted_structure_types()

    assert MapSet.member?(emitted, "Link"),
           "compliant.pdf must carry a tagged link. Without one, ISO 14289-1 " <>
             "clause 7.18.5 has nothing to match and passes by default."
  end

  test "every recorded gap is a real structure type, not a stale name" do
    known = Structure.tags() |> Map.values() |> MapSet.new()

    for type <- @never_validated do
      assert MapSet.member?(known, type),
             "#{type} is recorded as unvalidated but is not a structure type Tincture emits"
    end
  end
end
