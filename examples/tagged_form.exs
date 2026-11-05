Code.require_file("support/fonts.exs", __DIR__)
Code.require_file("support/checks.exs", __DIR__)

# An accessible form: a tagged document with interactive fields, claiming
# PDF/UA-1 (ISO 14289-1).
#
# It carries one of each field type: single-line and multiline text, a combo
# box, a list box, a checkbox, a three-button radio group, a push button that
# opens a URL, and an unsigned signature field. In a tagged document every
# widget is owned by a Form structure element of its own, which Tincture
# appends to the element open when the field is created; the field's
# :tooltip, written as /TU, is the name a screen reader announces.
#
# Each field is created inside the :p that draws its visible label, so its
# Form element sits under the element that describes it, and no paragraph
# holds a widget alone. Headings are drawn well above the body size, and each
# has a bookmark.
#
#     verapdf --flavour ua1 examples/output/tagged_form.pdf

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
    title: "Workshop registration",
    author: "Northgate Instruments Ltd",
    subject: "Registration for a calibration workshop"
  )
  |> Tincture.set_language("en-GB")
  |> Examples.Fonts.register("Body", "Sans")

unless embedded? do
  IO.puts("""
  No embeddable TrueType font was found on this machine, so the text falls
  back to the standard 14 fonts, which PDF/UA forbids (clause 7.21.4). The
  document below is still produced, and it will not validate.
  """)
end

sans = Examples.Fonts.resolve("Sans", embedded?)

# A field someone types into needs its font whole, so that a viewer can draw
# any character; the page text is subset from the same file, under another
# name.
pdf =
  if embedded?,
    do: Tincture.register_ttf_font(pdf, "Field", Examples.Fonts.sans(), subset: :none),
    else: pdf

field_font = if embedded?, do: "Field", else: "Helvetica"

heading = fn pdf, level, y, text ->
  {size, colour} = if level == :h1, do: {20, accent}, else: {13, ink}

  pdf
  |> Tincture.tag(level, fn pdf ->
    pdf
    |> Tincture.set_fill_color(colour)
    |> Tincture.set_font(sans, size)
    |> Tincture.text_at(margin, y, text)
  end)
  |> Tincture.add_bookmark(text, pdf.current_page)
end

label = fn pdf, x, y, text ->
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 9)
  |> Tincture.text_at(x, y, text)
end

option = fn pdf, x, y, text ->
  pdf
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(sans, 9)
  |> Tincture.text_at(x, y, text)
end

# Rules under the single-line fields are decoration, not content.
rule = fn pdf, x, y, width ->
  Tincture.artifact(pdf, fn pdf ->
    pdf
    |> Tincture.set_stroke_color(rule_grey)
    |> Tincture.set_line_width(0.75)
    |> Tincture.line(x, y, x + width, y)
  end)
end

# The letterhead is a form XObject, drawn once and placed once, inside a
# content element: its text is the paragraph's content.
pdf =
  Tincture.form_xobject(pdf, "letterhead", page_w - margin * 2, 40, fn xobject ->
    xobject
    |> Tincture.set_fill_color(accent)
    |> Tincture.set_font(sans, 12)
    |> Tincture.text_at(0, 22, "Northgate Instruments Ltd")
    |> Tincture.set_fill_color(muted)
    |> Tincture.set_font(sans, 8)
    |> Tincture.text_at(0, 8, "Calibration and loan of measuring instruments")
  end)

top = page_h - margin

pdf =
  Tincture.tag(pdf, :document, fn pdf ->
    pdf =
      pdf
      |> Tincture.tag(:p, &Tincture.place_form_xobject(&1, "letterhead", margin, top - 40))
      |> heading.(:h1, top - 84, "Workshop registration")

    # --- about you ----------------------------------------------------------
    y = top - 132

    pdf =
      Tincture.tag(pdf, :section, fn pdf ->
        pdf
        |> heading.(:h2, y + 28, "About you")
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> label.(margin, y + 8, "Full name")
          |> Tincture.text_field(margin, y - 14, field_w, 20, "full_name",
            font: field_font,
            tooltip: "Your full name"
          )
        end)
        |> rule.(margin, y - 14, field_w)
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> label.(margin + field_w + 24, y + 8, "Role")
          |> Tincture.choice_field(margin + field_w + 24, y - 14, 175, 20, "role",
            options: ["Engineer", "Technician", "Student", "Other"],
            value: "Engineer",
            font: field_font,
            border: {0, 0, 0.75},
            tooltip: "Your role"
          )
        end)
      end)

    # --- the workshop ---------------------------------------------------------
    y = y - 86

    pdf =
      Tincture.tag(pdf, :section, fn pdf ->
        pdf
        |> heading.(:h2, y + 28, "The workshop")
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> label.(margin, y + 8, "Session")
          |> Tincture.choice_field(margin, y - 56, field_w, 62, "session",
            options: [
              "Pressure, morning",
              "Pressure, afternoon",
              "Torque, morning",
              "Torque, afternoon"
            ],
            value: "Torque, morning",
            dropdown: false,
            font: field_font,
            border: {0, 0, 0.75},
            tooltip: "The session you will attend"
          )
        end)
        |> Tincture.tag(:p, fn pdf ->
          x = margin + field_w + 24

          pdf
          |> label.(x, y + 8, "Lunch")
          |> Tincture.radio_group(
            "lunch",
            [
              [value: "standard", x: x, y: y - 12, size: 12],
              [value: "vegetarian", x: x, y: y - 30, size: 12],
              [value: "none", x: x, y: y - 48, size: 12]
            ],
            selected: "standard",
            tooltip: "Your lunch choice"
          )
          |> option.(x + 18, y - 10, "Standard")
          |> option.(x + 18, y - 28, "Vegetarian")
          |> option.(x + 18, y - 46, "No lunch")
        end)
      end)

    # --- notes ------------------------------------------------------------------
    y = y - 112

    pdf =
      Tincture.tag(pdf, :section, fn pdf ->
        pdf
        |> heading.(:h2, y + 28, "Notes")
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> label.(margin, y + 8, "Anything the organisers should know")
          |> Tincture.text_field(margin, y - 62, page_w - margin * 2, 64, "notes",
            multiline: true,
            font: field_font,
            border: {0, 0, 0.75},
            tooltip: "Access needs or other notes for the organisers"
          )
        end)
        |> Tincture.tag(:p, fn pdf ->
          pdf
          |> Tincture.checkbox(margin, y - 90, 12, "newsletter",
            tooltip: "Receive the workshop newsletter"
          )
          |> option.(margin + 18, y - 88, "Send me the workshop newsletter.")
        end)
      end)

    # --- signature ----------------------------------------------------------------
    y = y - 146

    Tincture.tag(pdf, :section, fn pdf ->
      pdf
      |> heading.(:h2, y + 28, "Signature")
      |> Tincture.tag(:p, fn pdf ->
        pdf
        |> label.(margin, y + 8, "Your signature")
        |> Tincture.signature_field(margin, y - 52, field_w, 50, "signature",
          label: "Sign here",
          size: 11,
          font: field_font,
          border: {0, 0, 0.75},
          tooltip: "Your signature"
        )
      end)
      |> Tincture.tag(:p, fn pdf ->
        x = margin + field_w + 24

        pdf
        |> label.(x, y + 8, "Workshop terms")
        |> Tincture.push_button(x, y - 30, 140, 24, "terms",
          action: {:url, "https://example.org/workshop-terms"},
          label: "Read the terms",
          font: field_font,
          tooltip: "Open the workshop terms in a browser"
        )
      end)
    end)
  end)

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("tagged_form.pdf")
File.write!(path, binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")

checks =
  Examples.Checks.form_rows(binary, widgets: 10, fields: 8, headings: 5) ++
    [
      {"letterhead placed once", "7.20-2", length(Regex.scan(~r|/Fm\d+ Do|, binary)) == 1},
      {"fields in an embedded font", "7.21.4",
       if(embedded?, do: true, else: {:note, "NO - standard 14 in use"})}
    ]

IO.puts("""

What the tagged form needed, and where it came from:

#{Examples.Checks.table(checks)}

Validate it:

    verapdf --flavour ua1 #{Path.relative_to_cwd(path)}
""")

Examples.Checks.halt_if_missing(checks)
