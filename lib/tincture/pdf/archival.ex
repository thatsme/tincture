defmodule Tincture.PDF.Archival do
  @moduledoc """
  Checks a document against the PDF/A rules Tincture can see.

  `Tincture.set_pdf_a/2` writes a conformance claim into the file's metadata.
  That is an assertion, not a request: a document saying `pdfaid:conformance`
  while using a font it does not embed is *lying* about itself, and nobody finds
  out until a retention audit years later. A false claim is worse than no claim,
  so `Tincture.export/2` refuses to produce one.

  ## What this can and cannot tell you

  Everything checked here was confirmed against veraPDF rather than read off a
  specification, and each violation names the clause it breaks.

  It is still **not a conformance check**. Tincture sees the document it built,
  not the file a validator sees, and PDF/A has requirements no library can
  settle on your behalf. Passing these checks means "nothing Tincture knows of
  is wrong", which is a much smaller claim than "this is PDF/A". Validate the
  output:

      verapdf --flavour 2b out.pdf

  ## What is allowed that you might expect not to be

  Checkboxes, radio buttons and links are fine. They were not always: links
  lacked the `/F` key every annotation needs, and `/NeedAppearances` was set
  whenever a document had any form field at all. Both were fixed rather than
  forbidden, because a rule that bans working features is a bug in the rule.
  """

  alias Tincture.PDF
  alias Tincture.PDF.FontEmbed

  @type violation :: %{
          required(:rule) => atom(),
          required(:clause) => String.t(),
          required(:message) => String.t()
        }

  @doc """
  Every PDF/A violation Tincture can detect in this document.

  Returns `[]` for a document that declares no level, since there is then
  nothing being claimed.
  """
  @spec violations(PDF.t()) :: [violation()]
  def violations(%PDF{pdf_a: nil}), do: []

  def violations(%PDF{} = pdf) do
    Enum.flat_map(
      [
        &unembedded_fonts/1,
        &encryption/1,
        &value_rendered_fields/1,
        &signature_fields/1,
        &push_buttons/1,
        &untagged_for_level/1
      ],
      fn check -> check.(pdf) end
    )
  end

  @doc """
  A human-readable summary of the violations, for an error message.
  """
  @spec describe([violation()]) :: String.t()
  def describe(violations) do
    Enum.map_join(violations, "\n", fn violation ->
      "  * #{violation.message} (ISO 19005-2 clause #{violation.clause})"
    end)
  end

  # ISO 19005-2 clause 6.2.11.4.1. The standard 14 fonts are referenced by name
  # for the reader to resolve, which is exactly the outside dependency an
  # archival format exists to remove.
  defp unembedded_fonts(%PDF{} = pdf) do
    used =
      pdf
      |> PDF.page_numbers()
      |> Enum.flat_map(fn page_number ->
        pdf |> PDF.page_operations(page_number) |> FontEmbed.font_names_from_operations()
      end)
      |> Enum.uniq()

    # Only fonts that actually draw something count. A form field's /DA font
    # renders its value, so it matters for text and choice fields - but those
    # are rejected outright below, and a checkbox or radio button draws from
    # its appearance streams and never uses the font at all. Flagging those
    # would reject documents veraPDF accepts.
    unembedded = Enum.reject(used, &Map.has_key?(pdf.embedded_fonts, &1))

    case Enum.uniq(unembedded) do
      [] ->
        []

      fonts ->
        [
          %{
            rule: :unembedded_font,
            clause: "6.2.11.4.1",
            message:
              "these fonts are not embedded: #{Enum.map_join(Enum.sort(fonts), ", ", &inspect/1)}. " <>
                "PDF/A requires every font to be carried in the file, so the standard 14 " <>
                "cannot be used. Register them with register_ttf_font/4 or register_otf_font/4."
          }
        ]
    end
  end

  # ISO 19005-2 clause 6.1.3. An encrypted file cannot be read without a
  # secret, which defeats the point of archiving it.
  defp encryption(%PDF{encryption: nil}), do: []

  defp encryption(%PDF{}) do
    [
      %{
        rule: :encrypted,
        clause: "6.1.3",
        message:
          "the document is encrypted. PDF/A forbids encryption, because a file that needs " <>
            "a password to open is not readable in the long term."
      }
    ]
  end

  # ISO 19005-2 clause 6.4.1. Text and choice fields have their value drawn by
  # the viewer from /NeedAppearances, which PDF/A forbids. They need generated
  # appearance streams, which Tincture does not yet produce for them.
  defp value_rendered_fields(%PDF{} = pdf) do
    case Enum.filter(pdf.form_fields, &(&1.type in [:text, :choice])) do
      [] ->
        []

      fields ->
        [
          %{
            rule: :value_rendered_field,
            clause: "6.4.1",
            message:
              "#{length(fields)} text or choice field(s) present " <>
                "(#{fields |> Enum.map(& &1.name) |> Enum.take(3) |> Enum.map_join(", ", &inspect/1)}). " <>
                "Their value is rendered by the viewer via /NeedAppearances, which PDF/A " <>
                "forbids. Checkboxes and radio buttons carry their own appearances and are fine."
          }
        ]
    end
  end

  # ISO 19005-2 clause 6.3.3. Every annotation needs an appearance stream, and
  # an unsigned signature field has nothing to draw.
  defp signature_fields(%PDF{} = pdf) do
    case Enum.filter(pdf.form_fields, &(&1.type == :signature)) do
      [] ->
        []

      fields ->
        [
          %{
            rule: :signature_field,
            clause: "6.3.3",
            message:
              "#{length(fields)} signature field(s) present. Every annotation needs an " <>
                "appearance stream, and an unsigned signature field has none."
          }
        ]
    end
  end

  # ISO 19005-2 clauses 6.4.1 and 6.5.1. A push button is nothing but an
  # action, and a widget carrying /A is forbidden outright - ResetForm doubly
  # so.
  defp push_buttons(%PDF{} = pdf) do
    case Enum.filter(pdf.form_fields, &(&1.type == :push_button)) do
      [] ->
        []

      fields ->
        [
          %{
            rule: :push_button,
            clause: "6.4.1",
            message:
              "#{length(fields)} push button(s) present. A widget annotation may not carry " <>
                "an /A action, and a push button is nothing but an action."
          }
        ]
    end
  end

  # The accessible conformance levels require the tagging PDF/UA needs.
  defp untagged_for_level(%PDF{pdf_a: {part, :a}} = pdf) do
    if PDF.tagged?(pdf) do
      []
    else
      [
        %{
          rule: :untagged,
          clause: "6.8",
          message:
            "conformance level #{part}A requires a tagged document, and this one carries no " <>
              "logical structure. Use tag/4 and set_language/2, or claim level #{part}B."
        }
      ]
    end
  end

  defp untagged_for_level(%PDF{}), do: []
end
