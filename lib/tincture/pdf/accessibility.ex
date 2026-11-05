defmodule Tincture.PDF.Accessibility do
  @moduledoc """
  Checks a tagged document against the PDF/UA rules Tincture can see.

  Tagging a document is a claim: the catalog carries `/MarkInfo`, and the XMP
  metadata carries `pdfuaid:part`. A reader that finds structure trusts it, and
  a figure with no alternative text is then worse than an untagged one — the
  reader announces an element it cannot describe, and the person using it knows
  only that something is there.

  So the same rule applies as for PDF/A: `Tincture.export/2` refuses to write a
  claim the document does not meet. See `Tincture.PDF.Archival` for the archival
  half.

  ## What is checked

    * a `:figure` with no `:alt` (clause 7.3);
    * a link annotation outside the structure tree, or nested in an element
      other than `:link` (clause 7.18.5);
    * a link annotation with no `:contents` (clause 7.18.5);
    * a form field with no `:tooltip`, which is written as `/TU` (clause
      7.18.1);
    * a form field created outside every `Tincture.tag/4` scope, which leaves
      its widget with no Form element (clause 7.18.4);
    * a document with no language, set with `Tincture.set_language/2`
      (clause 7.2);
    * a document with no title, set with `Tincture.set_metadata/2` (clause
      7.1).

  Clause numbers are those of the matching rules in veraPDF 1.30.2's PDF/UA-1
  profile (7.3-1, 7.18.5-1, 7.18.5-2, 7.18.1-3, 7.18.4-1, 7.2-34, 7.2-25 and
  7.2-33, and 7.1-9).

  ## What this can and cannot tell you

  This is **not a conformance check**. PDF/UA has requirements no library can
  settle for you — whether a heading level is the right one, whether reading
  order matches intent, whether an alternative text is *accurate* rather than
  merely present. Tincture checks the ones that are structural and therefore
  visible to it. Validate the output:

      verapdf --flavour ua1 out.pdf

  and, because it applies checks veraPDF does not, PAC.
  """

  alias Tincture.PDF
  alias Tincture.PDF.Structure

  @type violation :: %{
          required(:rule) => atom(),
          required(:clause) => String.t(),
          required(:message) => String.t()
        }

  @doc """
  Every PDF/UA violation Tincture can detect in this document.

  Returns `[]` for an untagged document, since nothing is being claimed.
  """
  @spec violations(PDF.t()) :: [violation()]
  def violations(%PDF{} = pdf) do
    if PDF.tagged?(pdf) do
      Enum.flat_map(
        [
          &figures_without_alt/1,
          &links_outside_structure/1,
          &links_without_description/1,
          &fields_without_description/1,
          &fields_outside_structure/1,
          &language_missing/1,
          &title_missing/1
        ],
        fn check -> check.(pdf) end
      )
    else
      []
    end
  end

  @doc """
  A human-readable summary of the violations, for an error message.
  """
  @spec describe([violation()]) :: String.t()
  def describe(violations) do
    Enum.map_join(violations, "\n", fn violation ->
      "  * #{violation.message} (ISO 14289-1 clause #{violation.clause})"
    end)
  end

  # A figure is the one element whose meaning is entirely outside the text
  # layer. Without :alt there is nothing for a reader to say about it, and the
  # structure tree has promised there is something there.
  defp figures_without_alt(%PDF{} = pdf) do
    pdf.structure_tree
    |> Structure.flatten()
    |> Enum.filter(fn element ->
      element.tag == :figure and blank?(Map.get(element, :alt))
    end)
    |> Enum.map(fn element ->
      %{
        rule: :figure_without_alt,
        clause: "7.3",
        message:
          "a :figure on page #{element.page_number} has no alternative text. " <>
            "Pass alt: \"...\" to tag/4"
      }
    end)
  end

  # A link annotation is not content, so marked content cannot carry it: the
  # structure tree has to own it outright, through a /Link element holding an
  # /OBJR reference. A tagged document whose links sit outside the tree has
  # promised a structure that does not describe everything on the page, and the
  # link is unreachable to anyone navigating by structure rather than by sight.
  defp links_outside_structure(%PDF{} = pdf) do
    owners =
      pdf.structure_tree
      |> Structure.flatten()
      |> Enum.flat_map(fn element ->
        Enum.map(Map.get(element, :annotation_ids, []), &{&1, element})
      end)
      |> Map.new()

    for page_number <- PDF.page_numbers(pdf),
        annotation <- PDF.page_annotations(pdf, page_number),
        violation = link_structure_violation(annotation, page_number, owners) do
      violation
    end
  end

  # A link's rectangle is not self-describing: without /Contents a reader
  # reaches the annotation and has nothing to announce but that a link is
  # there. Required rather than advisory - veraPDF checks it twice, under
  # clause 7.18.1 and again under 7.18.5.
  defp links_without_description(%PDF{} = pdf) do
    for page_number <- PDF.page_numbers(pdf),
        annotation <- PDF.page_annotations(pdf, page_number),
        blank?(Map.get(annotation, :contents)) do
      %{
        rule: :link_without_description,
        clause: "7.18.5",
        message:
          "a link annotation on page #{page_number} has no alternate description. " <>
            "Pass contents: \"...\" saying where the link goes"
      }
    end
  end

  defp link_structure_violation(annotation, page_number, owners) do
    case Map.fetch(owners, Map.get(annotation, :id)) do
      {:ok, %{tag: :link}} ->
        nil

      {:ok, element} ->
        %{
          rule: :link_in_wrong_element,
          clause: "7.18.5",
          message:
            "a link annotation on page #{page_number} is inside a :#{element.tag} element " <>
              "rather than a :link one. A reader announces a link by its /Link tag"
        }

      :error ->
        %{
          rule: :link_outside_structure,
          clause: "7.18.5",
          message:
            "a link annotation on page #{page_number} is not in the structure tree. " <>
              "Create it inside tag(:link, fn ...) so a reader can reach it"
        }
    end
  end

  # A tagged document claims PDF/UA-1 in its XMP, and PDF/UA requires the
  # natural language of everything a reader announces to be determined: the
  # page text (veraPDF rule 7.2-34), a field's /TU (7.2-25), the metadata
  # title (7.2-33). The catalog /Lang that set_language/2 writes determines
  # all three; without it a screen reader guesses which language to pronounce
  # the text in. One violation for the document, whatever it holds.
  defp language_missing(%PDF{language: nil}) do
    [
      %{
        rule: :language_missing,
        clause: "7.2",
        message:
          "the document has no language. A tagged document claims PDF/UA, which needs " <>
            "the natural language of its text, its form fields' tooltips and its " <>
            "metadata title to be known (veraPDF rules 7.2-34, 7.2-25 and 7.2-33), so a " <>
            "screen reader does not have to guess how to pronounce them. Call " <>
            "set_language/2, for example set_language(pdf, \"en-GB\")"
      }
    ]
  end

  defp language_missing(%PDF{}), do: []

  # PDF/UA also requires the metadata to carry a title that identifies the
  # document (veraPDF rule 7.1-9, dc:title in the XMP), which a reader
  # announces in place of a file name: a tagged document asks the viewer to
  # show it (/DisplayDocTitle). set_metadata/2's :title writes it. A blank
  # title counts as none. One violation for the document.
  defp title_missing(%PDF{metadata: metadata}) do
    if blank?(Map.get(metadata, :title)) do
      [
        %{
          rule: :title_missing,
          clause: "7.1",
          message:
            "the document has no title. A tagged document claims PDF/UA, which needs " <>
              "its metadata to carry a title that identifies the document (veraPDF rule " <>
              "7.1-9, dc:title), so a reader can announce what it is. Call " <>
              "set_metadata/2 with title:, for example " <>
              "set_metadata(pdf, title: \"Annual report\")"
        }
      ]
    else
      []
    end
  end

  # A field's tooltip is written as /TU, the name a screen reader announces for
  # it; without one, a reader reaches the field and can say only that a field
  # is there. Checked once per field, so a radio group, one field with one
  # :tooltip, is checked once whatever its number of buttons.
  defp fields_without_description(%PDF{} = pdf) do
    for field <- pdf.form_fields, blank?(Map.get(field, :tooltip)) do
      %{
        rule: :field_without_description,
        clause: "7.18.1",
        message:
          "a #{field_kind(field.type)} #{inspect(field.name)} on page #{field.page_number} " <>
            "has no tooltip. In a tagged document every form field needs one: it is " <>
            "written as /TU, the name a screen reader announces for the field. Pass " <>
            "tooltip: \"...\""
      }
    end
  end

  # A widget, like a link, is not content: the structure tree has to own it,
  # through a Form element, which a field call creates only inside a tag/4
  # scope. One created outside every scope has none, and is unreachable to
  # anyone navigating by structure. Once per field: a radio group's buttons
  # all come from one call.
  defp fields_outside_structure(%PDF{} = pdf) do
    for field <- pdf.form_fields, Map.get(field, :created_outside_structure, false) do
      %{
        rule: :field_outside_structure,
        clause: "7.18.4",
        message:
          "a #{field_kind(field.type)} #{inspect(field.name)} on page #{field.page_number} " <>
            "is not in the structure tree. In a tagged document a form field must be " <>
            "created inside a tag(...) scope so a reader can reach it"
      }
    end
  end

  @doc false
  @spec field_kind(atom()) :: String.t()
  def field_kind(:text), do: "text field"
  def field_kind(:choice), do: "choice field"
  def field_kind(:checkbox), do: "checkbox"
  def field_kind(:radio), do: "radio group"
  def field_kind(:push_button), do: "push button"
  def field_kind(:signature), do: "signature field"

  defp blank?(nil), do: true
  defp blank?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank?(_other), do: false
end
