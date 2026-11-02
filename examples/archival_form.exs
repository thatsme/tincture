Code.require_file("support/fonts.exs", __DIR__)
Code.require_file("support/checks.exs", __DIR__)

# A form that has to outlive the software that made it.
#
# An archival document (PDF/A, ISO 19005) can carry an interactive form, as
# long as every field draws itself and every font it draws with is in the
# file. This claims PDF/A-2u, which subsumes PDF/A-2b, and carries one of
# each field PDF/A allows: single-line and multiline text, a read-only text
# field, a combo box, a list box, a checkbox, a radio group, and an unsigned
# signature field. A push button cannot be part of a PDF/A document, so there
# is none.
#
# Every field's text is in an embedded font. The editable fields use one font
# embedded whole, so a viewer can draw whatever someone types; the read-only
# field uses a second font, subset to what it draws, including a character
# that appears nowhere else on the page.
#
#     verapdf --flavour 2b examples/output/archival_form.pdf
#     verapdf --flavour 2u examples/output/archival_form.pdf

page_w = 595
page_h = 842
margin = 56
field_w = 260

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule_grey = {0.85, 0.86, 0.88}

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Instrument loan record NGI-L-0219",
    author: "Northgate Instruments Ltd",
    subject: "Loan of a calibrated instrument, retained with its certificate",
    keywords: "loan, instrument, archival, form"
  )
  |> Tincture.set_language("en-GB")
  |> Tincture.set_pdf_a(:a2u)
  |> Examples.Fonts.register("Body", "Sans")

# PDF/A requires every font a field draws with to be embedded, so without a
# TrueType font the claim cannot be met: the document is still produced, with
# `enforce: false`, and will not validate.
unless embedded? do
  IO.puts("""
  No embeddable TrueType font was found on this machine, so the fields would
  fall back to the standard 14 fonts, which PDF/A forbids. The document below is
  exported with `enforce: false`: it is still produced, and it will not validate.
  """)
end

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

# "№" appears nowhere else on the page, so it reaches the read-only field's
# font only through that field. WinAnsi has no "№", so the standard-14
# fallback writes "No".
reference = if embedded?, do: "Ref. № NGI-C-4471", else: "Ref. No NGI-C-4471"

label = fn pdf, x, y, text ->
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 8)
  |> Tincture.text_at(x, y, text)
end

underline = fn pdf, x, y, width ->
  pdf
  |> Tincture.set_stroke_color(rule_grey)
  |> Tincture.set_line_width(0.75)
  |> Tincture.line(x, y, x + width, y)
end

# The letterhead is a form XObject, drawn once and placed once: its font is
# checked and embedded like the page's.
pdf =
  Tincture.form_xobject(pdf, "letterhead", page_w - margin * 2, 40, fn xobject ->
    xobject
    |> Tincture.set_fill_color(accent)
    |> Tincture.set_font(sans, 16)
    |> Tincture.text_at(0, 22, "Northgate Instruments Ltd")
    |> Tincture.set_fill_color(muted)
    |> Tincture.set_font(sans, 8)
    |> Tincture.text_at(0, 8, "Calibration and loan of measuring instruments")
  end)

top = page_h - margin

pdf =
  pdf
  |> Tincture.place_form_xobject("letterhead", margin, top - 40)
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(sans, 13)
  |> Tincture.text_at(margin, top - 80, "Instrument loan record")
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 8.5)
  |> Tincture.text_at(
    margin,
    top - 96,
    "Complete and keep with the instrument's calibration certificate."
  )

# --- the borrower ---------------------------------------------------------
y = top - 140

pdf =
  pdf
  |> label.(margin, y + 24, "Borrower")
  |> underline.(margin, y - 2, field_w)
  |> Tincture.text_field(margin, y - 2, field_w, 20, "borrower",
    value: "Ada Lovelace",
    font: sans,
    full_font: true,
    tooltip: "Name of the person borrowing the instrument"
  )
  |> label.(margin + field_w + 24, y + 24, "Certificate (read-only)")
  |> underline.(margin + field_w + 24, y - 2, 175)
  |> Tincture.text_field(margin + field_w + 24, y - 2, 175, 20, "certificate",
    value: reference,
    font: body,
    read_only: true,
    tooltip: "Reference of the instrument's calibration certificate"
  )

# --- the instrument --------------------------------------------------------
y = y - 56

pdf =
  pdf
  |> label.(margin, y + 24, "Instrument")
  |> Tincture.choice_field(margin, y - 2, field_w, 20, "instrument",
    options: ["Digital multimeter", "Oscilloscope", "Pressure gauge", "Torque wrench"],
    value: "Pressure gauge",
    font: sans,
    full_font: true,
    border: {0, 0, 0.75},
    tooltip: "The instrument on loan"
  )
  |> label.(margin + field_w + 24, y + 24, "Purpose")
  |> Tincture.choice_field(margin + field_w + 24, y - 44, 175, 62, "purpose",
    options: ["Field service", "Laboratory work", "Training", "Validation"],
    value: "Laboratory work",
    dropdown: false,
    font: sans,
    full_font: true,
    border: {0, 0, 0.75},
    tooltip: "What the instrument will be used for"
  )

# --- conditions ------------------------------------------------------------
y = y - 64

pdf =
  pdf
  |> label.(margin, y + 24, "Loan period")
  |> Tincture.radio_group(
    "period",
    [
      [value: "week", x: margin, y: y, size: 12],
      [value: "month", x: margin + 70, y: y, size: 12],
      [value: "quarter", x: margin + 150, y: y, size: 12]
    ],
    selected: "month",
    tooltip: "How long the instrument is lent for"
  )
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(sans, 9)
  |> Tincture.text_at(margin + 16, y + 2, "One week")
  |> Tincture.text_at(margin + 86, y + 2, "One month")
  |> Tincture.text_at(margin + 166, y + 2, "One quarter")

y = y - 40

pdf =
  pdf
  |> Tincture.checkbox(margin, y, 12, "returned_calibrated",
    value: true,
    tooltip: "Return the instrument within its calibration interval"
  )
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(sans, 9)
  |> Tincture.text_at(
    margin + 18,
    y + 2,
    "The instrument is returned before its calibration falls due."
  )

y = y - 44

pdf =
  pdf
  |> label.(margin, y + 70, "Notes")
  |> Tincture.text_field(margin, y - 2, page_w - margin * 2, 64, "notes",
    value: "Collected with its case and the two probes.\nReturn to the calibration desk.",
    font: sans,
    full_font: true,
    multiline: true,
    border: {0, 0, 0.75},
    tooltip: "Anything the calibration desk should know"
  )

# --- signature -------------------------------------------------------------
y = y - 110

pdf =
  pdf
  |> label.(margin, y + 58, "Borrower's signature")
  |> Tincture.signature_field(margin, y, field_w, 50, "signature",
    label: "Signature",
    size: 11,
    font: sans,
    border: {0, 0, 0.75},
    tooltip: "Signature of the borrower"
  )

binary = if embedded?, do: Tincture.export(pdf), else: Tincture.export(pdf, enforce: false)
path = Examples.Fonts.output_path("archival_form.pdf")
File.write!(path, binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")

# The font programs, by name: the whole-font embed carries no subset tag.
sans_size = if embedded?, do: File.stat!(Examples.Fonts.sans()).size, else: 0
whole_sans? = binary =~ "/FontName /Sans " or binary =~ "/FontName /Sans>"
subset_body? = binary =~ ~r|/FontName /[A-Z]{6}\+Body|

widget = fn name ->
  case Regex.run(~r|<< [^\n]*/T \(#{name}\)[^\n]*|, binary) do
    [dictionary] -> dictionary
    nil -> ""
  end
end

stream_ap? = fn name -> widget.(name) =~ ~r|/AP << /N \d+ 0 R >>| end
dictionary_ap? = fn name -> widget.(name) =~ ~r|/AP << /N << | end

checks = [
  {"conformance in XMP, level U", "set_pdf_a/2", binary =~ ~s(pdfaid:conformance>U<)},
  {"no /NeedAppearances", "6.4.1-3", not (binary =~ "/NeedAppearances")},
  {"Sans embedded whole", "full_font: true",
   if(embedded?,
     do: {whole_sans? and binary =~ "/Length1 #{sans_size}", "ok, #{sans_size} bytes"},
     else: {:note, "NO - standard 14 in use"}
   )},
  {"Body subset, for the read-only field", "subset",
   if(embedded?, do: subset_body?, else: {:note, "NO - standard 14 in use"})},
  {"text and choice: /AP /N a stream", "6.3.3-4",
   Enum.all?(~w(borrower certificate instrument purpose notes), stream_ap?)},
  {"signature: /AP /N a stream", "6.3.3-4", stream_ap?.("signature")},
  {"checkbox: /AP /N a dictionary", "6.3.3-3", dictionary_ap?.("returned_calibrated")},
  {"radio: /AP /N a dictionary", "6.3.3-3",
   Regex.scan(~r|/Parent \d+ 0 R [^\n]*/AP << /N << |, binary) |> length() == 3},
  {"no document-level /DA", "PDF/A rule", not (binary =~ ~r|/AcroForm << [^\n]*/DA \(|)},
  {"checkbox and radio name no font", "PDF/A rule",
   not (widget.("returned_calibrated") =~ "/DA") and not (widget.("period") =~ "/DA")},
  {"signature names its font", "/DA", widget.("signature") =~ "/DA ("},
  {"no push button", "refused", not (binary =~ "/Ff 65536")},
  {"letterhead placed once", "form_xobject/5", length(Regex.scan(~r|/Fm\d+ Do|, binary)) == 1}
]

IO.puts("""

What the archival form needed, and where it came from:

#{Examples.Checks.table(checks)}

Validate it:

    verapdf --flavour 2b #{Path.relative_to_cwd(path)}
    verapdf --flavour 2u #{Path.relative_to_cwd(path)}
""")

Examples.Checks.halt_if_missing(checks)
