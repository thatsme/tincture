Code.require_file("support/fonts.exs", __DIR__)

# A realistic interactive form: supplier account application.
#
# Exercises every field type the library can produce — text (single and
# multiline), choice, checkbox, radio group, signature and push buttons — laid
# out as an actual document rather than a grid of test widgets.
#
# Static text is set in embedded fonts, field values in Helvetica. Each text and
# choice field carries an appearance stream Tincture lays out, so the
# dropdowns' values show in any render; the text fields are empty. A field may
# also use an embedded font, which this example does not.

page_w = 595
page_h = 842
margin = 50
content_w = page_w - margin * 2

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule = {0.85, 0.86, 0.88}

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Supplier account application",
    author: "Northgate Instruments Ltd",
    subject: "Interactive application form"
  )
  |> Examples.Fonts.register("Body", "Sans")

# Resolve through the helper rather than naming "Body" directly: on a machine
# with none of the candidate fonts installed nothing was registered, and the
# document does not know that name.
body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

# --- header ---------------------------------------------------------------
pdf =
  pdf
  |> Tincture.set_fill_color(accent)
  |> Tincture.rectangle(0, page_h - 96, page_w, 96, :fill)
  |> Tincture.set_fill_color({1.0, 1.0, 1.0})
  |> Tincture.set_font(body, 22)
  |> Tincture.text_at(margin, page_h - 52, "Supplier account application")
  |> Tincture.set_font(sans, 8.5)
  |> Tincture.text_at(
    margin,
    page_h - 70,
    "Complete every field marked required, then sign and submit."
  )

# Section heading, and a small-caps-ish label above a field.
section = fn pdf, y, title ->
  pdf
  |> Tincture.set_fill_color(accent)
  |> Tincture.set_font(sans, 8)
  |> Tincture.text_at(margin, y, String.upcase(title))
  |> Tincture.set_stroke_color(rule)
  |> Tincture.set_line_width(0.75)
  |> Tincture.line(margin, y - 6, page_w - margin, y - 6)
end

# Every label's baseline sits label_gap above the top of its field, so the
# label clears the field's area rather than resting on its edge.
label_gap = 4

label = fn pdf, x, y, text ->
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 7.5)
  |> Tincture.text_at(x, y, String.upcase(text))
end

# A field's box is drawn as a rule under it rather than a full border, which is
# why every field is created with border: :none.
underline = fn pdf, x, y, width ->
  pdf
  |> Tincture.set_stroke_color(rule)
  |> Tincture.set_line_width(0.75)
  |> Tincture.line(x, y - 3, x + width, y - 3)
end

# --- your details ---------------------------------------------------------
col_w = (content_w - 20) / 2
right_x = margin + col_w + 20

pdf = section.(pdf, page_h - 136, "Your details")

pdf =
  pdf
  |> label.(margin, page_h - 160 + label_gap, "Registered company name")
  |> underline.(margin, page_h - 178, content_w)
  |> Tincture.text_field(margin, page_h - 178, content_w, 18, "company_name",
    required: true,
    border: :none,
    tooltip: "As it appears on your certificate of incorporation"
  )
  |> label.(margin, page_h - 200 + label_gap, "Contact name")
  |> underline.(margin, page_h - 218, col_w)
  |> Tincture.text_field(margin, page_h - 218, col_w, 18, "contact_name",
    required: true,
    border: :none
  )
  |> label.(right_x, page_h - 200 + label_gap, "Position")
  |> underline.(right_x, page_h - 218, col_w)
  |> Tincture.text_field(right_x, page_h - 218, col_w, 18, "position", border: :none)
  |> label.(margin, page_h - 240 + label_gap, "Email")
  |> underline.(margin, page_h - 258, col_w)
  |> Tincture.text_field(margin, page_h - 258, col_w, 18, "email",
    required: true,
    border: :none
  )
  |> label.(right_x, page_h - 240 + label_gap, "Telephone")
  |> underline.(right_x, page_h - 258, col_w)
  |> Tincture.text_field(right_x, page_h - 258, col_w, 18, "telephone", border: :none)
  |> label.(margin, page_h - 280 + label_gap, "Registered address")
  |> underline.(margin, page_h - 330, content_w)
  |> Tincture.text_field(margin, page_h - 330, content_w, 50, "address",
    multiline: true,
    border: :none
  )

# --- account ---------------------------------------------------------------
pdf = section.(pdf, page_h - 366, "Account")

radio_y = page_h - 402

pdf =
  pdf
  |> label.(margin, radio_y + 12 + label_gap, "Account type")
  |> Tincture.radio_group(
    "account_type",
    [
      [value: "standard", x: margin, y: radio_y, size: 12],
      [value: "priority", x: margin, y: radio_y - 20, size: 12],
      [value: "trial", x: margin, y: radio_y - 40, size: 12]
    ],
    selected: "standard",
    border: :none,
    tooltip: "Priority accounts are invoiced monthly in arrears"
  )
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(body, 10)
  |> Tincture.text_at(margin + 20, radio_y + 3, "Standard — invoiced per order")
  |> Tincture.text_at(margin + 20, radio_y - 17, "Priority — invoiced monthly in arrears")
  |> Tincture.text_at(margin + 20, radio_y - 37, "Trial — three months, then review")

pdf =
  pdf
  |> label.(right_x, radio_y + 12 + label_gap, "Payment terms")
  |> underline.(right_x, radio_y - 6, col_w)
  |> Tincture.choice_field(right_x, radio_y - 6, col_w, 18, "payment_terms",
    options: ["14 days", "30 days", "60 days"],
    value: "30 days",
    dropdown: true,
    border: :none
  )
  |> label.(right_x, radio_y - 34 + label_gap, "Currency")
  |> underline.(right_x, radio_y - 52, col_w)
  |> Tincture.choice_field(right_x, radio_y - 52, col_w, 18, "currency",
    options: ["GBP", "EUR", "USD"],
    value: "GBP",
    dropdown: true,
    border: :none
  )

# --- declarations ----------------------------------------------------------
pdf = section.(pdf, page_h - 500, "Declarations")

check_y = page_h - 528

pdf =
  pdf
  |> Tincture.checkbox(margin, check_y, 12, "accept_terms",
    required: true,
    border: :none
  )
  |> Tincture.checkbox(margin, check_y - 22, 12, "newsletter", border: :none)
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(body, 10)
  |> Tincture.text_at(margin + 20, check_y + 3, "I accept the standard terms of supply (required)")
  |> Tincture.text_at(margin + 20, check_y - 19, "Send me occasional product updates")

pdf =
  pdf
  |> label.(margin, check_y - 52 + label_gap, "Anything we should know")
  |> underline.(margin, check_y - 100, content_w)
  |> Tincture.text_field(margin, check_y - 100, content_w, 48, "notes",
    multiline: true,
    border: :none,
    tooltip: "Optional"
  )

# --- signature -------------------------------------------------------------
sign_y = page_h - 690

pdf =
  pdf
  |> section.(sign_y + 44, "Signature")
  |> label.(margin, sign_y + 20 + label_gap, "Signed")
  |> underline.(margin, sign_y - 20, col_w)
  |> Tincture.signature_field(margin, sign_y - 20, col_w, 40, "signature",
    required: true,
    border: :none,
    tooltip: "Sign here"
  )
  |> label.(right_x, sign_y + 16 + label_gap, "Date")
  |> underline.(right_x, sign_y - 2, col_w)
  |> Tincture.text_field(right_x, sign_y - 2, col_w, 18, "signed_on", border: :none)

# --- actions ---------------------------------------------------------------
button_y = 96

pdf =
  pdf
  |> Tincture.push_button(margin, button_y, 96, 26, "submit",
    label: "Submit",
    action: {:submit, "https://northgate-instruments.example/apply"},
    tooltip: "Send this application"
  )
  |> Tincture.push_button(margin + 106, button_y, 96, 26, "clear",
    label: "Clear",
    action: :reset,
    tooltip: "Reset every field"
  )
  |> Tincture.push_button(margin + 212, button_y, 96, 26, "help",
    label: "Help",
    action: {:url, "https://northgate-instruments.example/help"}
  )

# --- footer ----------------------------------------------------------------
pdf =
  pdf
  |> Tincture.set_stroke_color(rule)
  |> Tincture.set_line_width(0.75)
  |> Tincture.line(margin, 66, page_w - margin, 66)
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 7.5)
  |> Tincture.text_at(
    margin,
    52,
    "Northgate Instruments Ltd · Registered in England 04471902 · VAT GB 812 4471 02"
  )

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("form.pdf")
File.write!(path, binary)

field_count = length(pdf.form_fields)
radio_buttons = pdf.form_fields |> Enum.flat_map(&Map.get(&1, :widgets, [])) |> length()

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")
IO.puts("fields: #{field_count} (#{radio_buttons} radio buttons across groups)")

IO.puts(
  "types: " <>
    (pdf.form_fields |> Enum.map(& &1.type) |> Enum.frequencies() |> inspect())
)
