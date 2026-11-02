defmodule Tincture.PDF.Archival do
  @moduledoc """
  Checks a document against the PDF/A rules Tincture can see.

  `Tincture.set_pdf_a/2` writes a conformance claim into the file's metadata.
  That is an assertion, not a request: a document saying `pdfaid:conformance`
  while using a font it does not embed is *lying* about itself, and nobody finds
  out until a retention audit years later. A false claim is worse than no claim,
  so `Tincture.export/2` refuses to produce one.

  ## What this can and cannot tell you

  Each violation names the ISO 19005-2 clause it breaks.

  It is still **not a conformance check**. Tincture sees the document it built,
  not the file a validator sees, and PDF/A has requirements no library can
  settle on your behalf. Passing these checks means "nothing Tincture knows of
  is wrong", which is a much smaller claim than "this is PDF/A". Validate the
  output:

      verapdf --flavour 2b out.pdf

  ## What is allowed that you might expect not to be

  Form fields are not refused, except push buttons. Text and choice fields,
  checkboxes, radio groups and signature fields each carry their own
  appearance, and a field that draws text must use an embedded font. CI runs
  veraPDF on an archival form that carries one of each (`archival_form.pdf`),
  and on an archival example that carries a link. Neither was always
  allowed: links lacked the `/F` key every annotation needs, and
  `/NeedAppearances` was set whenever a document had any form field at all.
  Both were fixed rather than forbidden, because a rule that bans working
  features is a bug in the rule.
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
        &unembedded_field_fonts/1,
        &encryption/1,
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
      |> PDF.stream_keys()
      |> Enum.flat_map(fn key ->
        pdf |> PDF.stream_operations(key) |> FontEmbed.font_names_from_operations()
      end)
      |> Enum.uniq()

    # The pages and the form XObjects. A field's font is checked per field,
    # below: its appearance is built only when the document is written.
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

  # ISO 19005-2 clause 6.2.11.4.1, for form fields. A field whose appearance
  # draws text - a text or choice field, or a push button or signature with a
  # :label - draws it with the field's one font, and names that font in /DA,
  # which a viewer that redraws the field draws with too. So the font must be
  # embedded. A checkbox, a radio group and an unlabelled signature draw no
  # text and, in a document that declares PDF/A, name no font.
  defp unembedded_field_fonts(%PDF{} = pdf) do
    for field <- pdf.form_fields,
        draws_text?(field),
        not Map.has_key?(pdf.embedded_fonts, field.font) do
      %{
        rule: :unembedded_font,
        clause: "6.2.11.4.1",
        message:
          "field #{inspect(field.name)} draws with #{inspect(field.font)}, which is not " <>
            "embedded. PDF/A requires every font a field draws with to be carried in the " <>
            "file, so a text, choice or labelled signature field cannot use the standard 14. " <>
            "Register a TrueType or OpenType font with register_ttf_font/4 or " <>
            "register_otf_font/4 and pass it as the field's :font."
      }
    end
  end

  defp draws_text?(%{type: type}) when type in [:text, :choice], do: true
  defp draws_text?(field), do: Map.has_key?(field, :label)

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

  # ISO 19005-2 clauses 6.4.1 and 6.3.3. A push button is nothing but an
  # action, and a widget carrying /A is forbidden outright (6.4.1), ResetForm
  # doubly so (6.5.1). Its appearance is a single stream, and a button
  # widget's must be a dictionary of states (6.3.3): veraPDF fails both, even
  # for a URL action, which 6.5.1 permits.
  defp push_buttons(%PDF{} = pdf) do
    case Enum.filter(pdf.form_fields, &(&1.type == :push_button)) do
      [] ->
        []

      fields ->
        names = fields |> Enum.map(& &1.name) |> Enum.take(3) |> Enum.map_join(", ", &inspect/1)

        [
          %{
            rule: :push_button,
            clause: "6.4.1",
            message:
              "#{length(fields)} push button(s) present (#{names}). A push button cannot be " <>
                "part of a PDF/A document: its widget carries an /A action, which PDF/A " <>
                "forbids on a widget, and its appearance is a single stream, where PDF/A " <>
                "requires a button's to be a dictionary of states (ISO 19005-2 clause 6.3.3)."
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
