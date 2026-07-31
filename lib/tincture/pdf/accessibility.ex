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
      Enum.flat_map([&figures_without_alt/1], fn check -> check.(pdf) end)
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

  defp blank?(nil), do: true
  defp blank?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank?(_other), do: false
end
