Code.require_file("support/fonts.exs", __DIR__)

# A realistic invoice — run with: mix run examples/invoice.exs
#
# Writes output/invoice.pdf.
#
# This example exists because building it found two real bugs that 1,000 tests
# had not: rectangle/6 could not fill (it auto-stroked, which ended the path so
# a following fill/1 silently did nothing), and the typography engine cannot
# measure an embedded font. Both are noted inline below.
#
alias Tincture.Layout.Table
alias Tincture.Typography.RichText


# A4 in points.
page_w = 595
page_h = 842
margin = 50
content_w = page_w - margin * 2

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule = {0.85, 0.86, 0.88}

items = [
  ["Description", "Qty", "Unit", "Amount"],
  ["Calibration service — flow meter FM-220", "2", "340.00", "680.00"],
  ["Replacement sensor housing, stainless", "4", "112.50", "450.00"],
  ["On-site engineer, standard rate (hours)", "6", "95.00", "570.00"],
  ["On-site engineer, out-of-hours (hours)", "2", "142.50", "285.00"],
  ["Certification and documentation pack", "1", "180.00", "180.00"],
  ["Carriage, next-day insured", "1", "38.40", "38.40"]
]

subtotal = 2203.40
vat = Float.round(subtotal * 0.20, 2)
total = Float.round(subtotal + vat, 2)

money = fn amount ->
  amount
  |> :erlang.float_to_binary([{:decimals, 2}])
  |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
end

terms =
  "Payment is due within 30 days of the invoice date. Amounts outstanding beyond " <>
    "that period may be subject to interest at 8% above the Bank of England base rate, " <>
    "calculated daily, under the Late Payment of Commercial Debts (Interest) Act 1998. " <>
    "Please quote the invoice number with any remittance so that payment can be " <>
    "reconciled without correspondence."

pdf =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Invoice INV-2026-0418",
    author: "Northgate Instruments Ltd",
    subject: "Invoice for calibration and service work",
    keywords: "invoice, calibration, service"
  )
  |> then(&elem(Examples.Fonts.register(&1, "Body", "Sans"), 0))

# --- header band ----------------------------------------------------------
# rectangle/6 takes a paint mode. Before that existed the band silently did
# not render: the shape auto-stroked, which ended the path, and the following
# fill/1 had nothing left to fill.
logo_cx = margin + 17
logo_cy = page_h - 48

pdf =
  pdf
  |> Tincture.set_fill_color(accent)
  |> Tincture.rectangle(0, page_h - 96, page_w, 96, :fill)
  # A simple mark: an open ring with a gauge needle, drawn as vectors.
  |> Tincture.set_stroke_color({1.0, 1.0, 1.0})
  |> Tincture.set_line_width(2.2)
  |> Tincture.circle(logo_cx, logo_cy, 15, :stroke)
  |> Tincture.set_line_width(1.6)
  |> Tincture.line(logo_cx, logo_cy, logo_cx + 9, logo_cy + 8)
  |> Tincture.set_fill_color({1.0, 1.0, 1.0})
  |> Tincture.circle(logo_cx, logo_cy, 2.6, :fill)
  |> Tincture.set_font("Body", 22)
  |> Tincture.text_at(margin + 42, page_h - 52, "Northgate Instruments")
  |> Tincture.set_font("Sans", 8.5)
  |> Tincture.text_at(margin + 42, page_h - 70, "Unit 7, Brasshouse Works · Sheffield S3 8QP · United Kingdom")
  |> Tincture.set_font("Body", 26)
  |> Tincture.text_at(page_w - margin - 92, page_h - 52, "INVOICE")

# --- invoice meta, right column -------------------------------------------
meta_x = page_w - margin - 190
meta_y = page_h - 132

pdf =
  [
    {"Invoice number", "INV-2026-0418"},
    {"Invoice date", "26 July 2026"},
    {"Payment due", "25 August 2026"},
    {"Account", "NGI-4471"}
  ]
  |> Enum.with_index()
  |> Enum.reduce(pdf, fn {{label, value}, i}, acc ->
    y = meta_y - i * 15

    acc
    |> Tincture.set_fill_color(muted)
    |> Tincture.set_font("Sans", 8)
    |> Tincture.text_at(meta_x, y, String.upcase(label))
    |> Tincture.set_fill_color(ink)
    |> Tincture.set_font("Body", 10)
    |> Tincture.text_at(meta_x + 96, y, value)
  end)

# --- bill to --------------------------------------------------------------
pdf =
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font("Sans", 8)
  |> Tincture.text_at(margin, meta_y, "BILL TO")
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font("Body", 11)
  |> Tincture.text_at(margin, meta_y - 18, "Harlow Process Systems Ltd")
  |> Tincture.set_font("Body", 10)
  |> Tincture.text_at(margin, meta_y - 33, "Attn: Accounts Payable")
  |> Tincture.text_at(margin, meta_y - 47, "14 Pinnacle Way")
  |> Tincture.text_at(margin, meta_y - 61, "Harlow CM19 5QT")

# --- line items -----------------------------------------------------------
table_y = meta_y - 96

# Graphics state persists across operations, and the logo above left the
# stroke colour white — which would draw the table's borders invisibly.
pdf = Tincture.set_stroke_color(pdf, rule)

{pdf, table} =
  Table.render(pdf, margin, table_y, [252, 46, 78, 90], items,
    header_rows: 1,
    font: "Body",
    header_font: "Sans",
    font_size: 9.5,
    padding: 7,
    table_width: content_w
  )

totals_y = table_y - table.height - 18

# --- totals ---------------------------------------------------------------
pdf =
  [
    {"Subtotal", money.(subtotal), false},
    {"VAT at 20%", money.(vat), false},
    {"Total due (GBP)", money.(total), true}
  ]
  |> Enum.with_index()
  |> Enum.reduce(pdf, fn {{label, value, emphasis}, i}, acc ->
    y = totals_y - i * 19
    size = if emphasis, do: 12, else: 10

    acc =
      if emphasis do
        acc
        |> Tincture.set_stroke_color(rule)
        |> Tincture.set_line_width(0.75)
        |> Tincture.line(page_w - margin - 214, y + 13, page_w - margin, y + 13)
        |> Tincture.stroke()
      else
        acc
      end

    acc
    |> Tincture.set_fill_color(if(emphasis, do: ink, else: muted))
    |> Tincture.set_font(if(emphasis, do: "Sans", else: "Body"), size)
    |> Tincture.text_at(page_w - margin - 214, y, label)
    |> Tincture.set_fill_color(ink)
    |> Tincture.set_font("Body", size)
    |> Tincture.text_at(page_w - margin - 72, y, "£" <> value)
  end)

# --- payment terms, through the typography engine -------------------------
terms_y = totals_y - 92

pdf =
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font("Sans", 8)
  |> Tincture.text_at(margin, terms_y + 22, "PAYMENT TERMS")
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font("Body", 9.5)

# The typography engine measures against the document, so this paragraph is
# justified and hyphenated using Georgia's real metrics. Rich text built this
# way carries provisional widths until text_paragraph/6 re-measures it, which
# is why no font context has to be passed here.
{pdf, _lines} =
  {Tincture.text_paragraph(
     pdf,
     margin,
     terms_y,
     RichText.from_plain(terms, font: "Body", size: 9.5),
     content_w - 150,
     align: :justified,
     line_break: :optimal,
     line_height: 13,
     hyphen_penalty: 60,
     widow_penalty: 200,
     orphan_penalty: 200
   ), nil}

# --- pay online link ------------------------------------------------------
pay_y = terms_y - 92

pdf =
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font("Sans", 8)
  |> Tincture.text_at(margin, pay_y + 20, "PAY ONLINE")
  # The clickable rectangle is measured from the drawn string, in whatever font
  # is current - embedded or not.
  |> Tincture.set_font("Body", 10)
  |> Tincture.text_link(
    margin,
    pay_y,
    "northgate-instruments.example/pay/INV-2026-0418",
    "https://northgate-instruments.example/pay/INV-2026-0418",
    color: accent
  )

# --- footer ---------------------------------------------------------------
pdf =
  pdf
  |> Tincture.set_stroke_color(rule)
  |> Tincture.set_line_width(0.75)
  |> Tincture.line(margin, 74, page_w - margin, 74)
  |> Tincture.stroke()
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font("Sans", 7.5)
  |> Tincture.text_at(margin, 60, "Northgate Instruments Ltd · Registered in England 04471902 · VAT GB 812 4471 02")
  |> Tincture.text_at(margin, 48, "Bank: Lloyds · Sort 30-96-14 · Account 41780255 · IBAN GB29 LOYD 3096 1441 7802 55")

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("invoice.pdf")
File.write!(path, binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")
IO.puts("table height: #{Float.round(table.height, 1)}pt over #{table.rows} rows")
IO.puts("embedded fonts subsetted: #{Regex.scan(~r|/BaseFont /([A-Z]{6})\+(\w+)|, binary) |> Enum.map(&Enum.at(&1, 2)) |> inspect()}")
IO.puts("link present: #{binary =~ "/Subtype /Link"}")
