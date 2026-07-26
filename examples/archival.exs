Code.require_file("support/fonts.exs", __DIR__)

# A document that has to outlive the software that made it.
#
# PDF/A (ISO 19005) is what records-retention policies specify. It is mostly a
# set of constraints rather than new capability: everything needed to render
# the file in fifty years has to be inside the file.
#
# This claims PDF/A-2a, the accessible archival level, which subsumes PDF/A-2u
# (text is extractable) and PDF/A-2b (visual reproduction is preserved) and
# additionally requires the tagging that PDF/UA needs. So the same document
# conforms to both standards at once — verify either:
#
#     verapdf --flavour 2a  examples/output/archival.pdf
#     verapdf --flavour ua1 examples/output/archival.pdf

alias Tincture.Typography.RichText

page_w = 595
page_h = 842
margin = 56
content_w = page_w - margin * 2

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule_grey = {0.85, 0.86, 0.88}

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Calibration certificate NGI-C-4471",
    author: "Northgate Instruments Ltd",
    subject: "Calibration certificate retained under ISO 17025",
    keywords: "calibration, certificate, ISO 17025, archival"
  )
  |> Examples.Fonts.register("Body", "Sans")

# PDF/A requires every font to be embedded in the file, so the standard 14 are
# not usable: they are referenced by name and resolved by the reader, which is
# precisely the outside dependency archival formats exist to remove.
unless embedded? do
  IO.puts("""
  No embeddable TrueType font was found on this machine, so this document would
  fall back to the standard 14 fonts — which PDF/A forbids, because they are
  referenced by name rather than carried in the file. The document below is
  still produced, but will not validate.
  """)
end

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

pdf =
  pdf
  |> Tincture.set_language("en-GB")
  # Everything PDF/A needs beyond ordinary output: an sRGB output intent so
  # device colour has a defined meaning, XMP carrying the conformance claim,
  # and a file identifier.
  |> Tincture.set_pdf_a(:a2a)

heading = fn pdf, level, y, text, size, colour, font ->
  Tincture.tag(pdf, level, fn pdf ->
    pdf
    |> Tincture.set_fill_color(colour)
    |> Tincture.set_font(font, size)
    |> Tincture.text_at(margin, y, text)
  end)
end

rule_at = fn pdf, y ->
  Tincture.artifact(pdf, fn pdf ->
    pdf
    |> Tincture.set_stroke_color(rule_grey)
    |> Tincture.set_line_width(0.75)
    |> Tincture.line(margin, y, page_w - margin, y)
    |> Tincture.stroke()
  end)
end

statement =
  "The instrument identified below was calibrated against standards traceable " <>
    "to national measurement standards. This certificate records the results as " <>
    "found and as left, and is retained for the period required by the quality " <>
    "management system. It may not be reproduced except in full."

details = [
  ["Field", "Value"],
  ["Certificate number", "NGI-C-4471"],
  ["Instrument", "Flow meter FM-220, serial 88-41207"],
  ["Calibrated on", "18 July 2026"],
  ["Next due", "18 July 2027"],
  ["Procedure", "NGI-WI-08 rev 4"],
  ["Ambient", "20.4 °C, 44% RH"]
]

table_top = page_h - 330
table_row_height = 25
table_bottom = table_top - table_row_height * length(details)

pdf =
  Tincture.tag(pdf, :document, fn pdf ->
    pdf =
      pdf
      |> heading.(:h1, page_h - 92, "Calibration certificate", 21, ink, body)
      |> Tincture.tag(:p, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(sans, 9)
        |> Tincture.text_at(margin, page_h - 110, "Northgate Instruments Ltd · NGI-C-4471")
      end)
      |> rule_at.(page_h - 126)

    pdf =
      Tincture.tag(pdf, :section, [title: "Statement"], fn pdf ->
        pdf
        |> heading.(:h2, page_h - 156, "STATEMENT OF TRACEABILITY", 8, accent, sans)
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> Tincture.set_fill_color(ink)
          |> Tincture.set_font(body, 10.5)
          |> Tincture.text_paragraph(
            margin,
            page_h - 180,
            RichText.from_plain(statement, font: body, size: 10.5),
            content_w,
            align: :justified,
            line_break: :optimal,
            line_height: 15
          )
        end)
      end)

    pdf =
      Tincture.tag(pdf, :section, [title: "Details"], fn pdf ->
        pdf =
          heading.(pdf, :h2, table_top + 26, "INSTRUMENT AND CONDITIONS", 8, accent, sans)

        pdf = Tincture.set_fill_color(pdf, ink)

        {pdf, _table} =
          Tincture.Layout.Table.render(pdf, margin, table_top, :auto, details,
            header_rows: 1,
            font: body,
            header_font: sans,
            font_size: 10,
            padding: 7,
            row_height: table_row_height,
            table_width: content_w
          )

        pdf
      end)

    Tincture.tag(pdf, :section, [title: "Authorisation"], fn pdf ->
      pdf =
        pdf
        |> heading.(:h2, table_bottom - 40, "AUTHORISED BY", 8, accent, sans)
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> Tincture.set_fill_color(ink)
          |> Tincture.set_font(body, 10.5)
          |> Tincture.text_at(margin, table_bottom - 66, "R. Aldiss, Calibration Engineer")
        end)
        |> rule_at.(table_bottom - 96)

      Tincture.tag(pdf, :p, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(sans, 7.5)
        |> Tincture.text_at(
          margin,
          table_bottom - 112,
          "Retained under ISO/IEC 17025. Archived as PDF/A-2a."
        )
      end)
    end)
  end)

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("archival.pdf")
File.write!(path, binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")

IO.puts("""

What PDF/A needed, and where it came from:

  sRGB output intent      set_pdf_a/2   #{if binary =~ "/GTS_PDFA1", do: "ok", else: "MISSING"}
  ICC profile embedded    built in      #{if binary =~ "/DestOutputProfile", do: "ok", else: "MISSING"}
  conformance in XMP      set_pdf_a/2   #{if binary =~ "pdfaid:conformance", do: "ok", else: "MISSING"}
  file identifier         always        #{if binary =~ "/ID [<", do: "ok", else: "MISSING"}
  fonts embedded          register_ttf  #{if embedded?, do: "ok", else: "NO - standard 14 in use"}
  tagged (needed for 2a)  tag/4         #{if binary =~ "/StructTreeRoot", do: "ok", else: "MISSING"}

Building the same document twice produces identical bytes: the file identifier
is derived from the content and the ICC profile carries no creation date, so an
archived file can be checked against a rebuild.

Verify both standards independently:

    verapdf --flavour 2a  #{Path.relative_to_cwd(path)}
    verapdf --flavour ua1 #{Path.relative_to_cwd(path)}
""")
