Code.require_file("support/fonts.exs", __DIR__)
Code.require_file("support/checks.exs", __DIR__)

# A form XObject: drawn once, placed four times, on two pages.
#
# The approval stamp below is defined with form_xobject/5 and written into the
# file as one object. Every place_form_xobject/5 after that is a reference to
# it - a few bytes of positioning - however much the stamp itself draws.
#
#   form_xobject/5        draws the content once, in its own coordinate space
#   place_form_xobject/5  puts it on the current page, at a scale or a size
#
# Inside the callback only drawing is allowed: shapes, colour and other
# graphics state, text, images and fonts. And drawing there starts afresh - the
# stamp does not pick up the font or anything else set on the page before it.
#
# This example makes no conformance claim. It is untagged, and placing one
# XObject inside several structure elements is deliberately outside the
# validated corpus.

page_w = 595
page_h = 842
margin = 72

ink = {0.13, 0.14, 0.16}
stamp_red = {0.72, 0.11, 0.11}

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Purchase order 2026-0418",
    author: "Northgate Instruments Ltd",
    subject: "A form XObject defined once and placed four times"
  )
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

# A rounded rectangle as a path: four lines and four quarter-circle curves.
rounded_rect = fn pdf, x, y, w, h, r ->
  k = r * 0.552_284_749_831

  pdf
  |> Tincture.move_to(x + r, y)
  |> Tincture.line_to(x + w - r, y)
  |> Tincture.bezier(x + w - r + k, y, x + w, y + r - k, x + w, y + r)
  |> Tincture.line_to(x + w, y + h - r)
  |> Tincture.bezier(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h)
  |> Tincture.line_to(x + r, y + h)
  |> Tincture.bezier(x + r - k, y + h, x, y + h - r + k, x, y + h - r)
  |> Tincture.line_to(x, y + r)
  |> Tincture.bezier(x, y + r - k, x + r - k, y, x + r, y)
end

# --- the stamp, defined once ---------------------------------------------
# 200 x 60, origin at the bottom left. A little transparency so it reads as
# ink over the page rather than a box pasted on it. Its colour is set inside
# it: anything it did not set would come from wherever it is placed.
pdf =
  Tincture.form_xobject(pdf, :approved, 200, 60, fn pdf ->
    pdf
    |> Tincture.save_state()
    |> Tincture.set_alpha(0.85)
    |> Tincture.set_stroke_color(stamp_red)
    |> Tincture.set_fill_color(stamp_red)
    |> Tincture.set_line_width(2.5)
    |> rounded_rect.(2, 2, 196, 56, 8)
    |> Tincture.stroke()
    |> Tincture.set_line_width(0.75)
    |> rounded_rect.(7, 7, 186, 46, 5)
    |> Tincture.stroke()
    |> Tincture.set_font(sans, 22)
    |> Tincture.text_at(37, 28, "APPROVED")
    |> Tincture.set_font(sans, 8)
    |> Tincture.text_at(52, 15, "Northgate quality review")
    |> Tincture.restore_state()
  end)

# --- page 1: the order, approved three times ------------------------------
# set_font here does not reach the stamp, and the stamp's fonts do not reach
# the page: after the definition the page is still drawing in its own font.
pdf =
  pdf
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(sans, 20)
  |> Tincture.text_at(margin, page_h - 100, "Purchase order 2026-0418")
  |> Tincture.set_font(body, 11)
  |> Tincture.text_at(margin, page_h - 130, "Supplier: Calder Precision Components")
  |> Tincture.text_at(margin, page_h - 146, "Delivery: Northgate Instruments, Unit 4, Leeds")
  |> Tincture.text_at(margin, page_h - 178, "120 x  M4 stainless standoff, 12 mm")
  |> Tincture.text_at(margin, page_h - 194, "40 x  enclosure gasket, silicone, 2 mm")
  |> Tincture.text_at(margin, page_h - 210, "6 x  calibration jig, revision C")
  |> Tincture.text_at(margin, page_h - 260, "Approvals")
  |> Tincture.set_font(body, 9)
  |> Tincture.text_at(margin, page_h - 280, "Engineering, at full size:")
  |> Tincture.place_form_xobject(:approved, margin, page_h - 350)
  |> Tincture.text_at(margin, page_h - 380, "Finance, at half scale:")
  |> Tincture.place_form_xobject(:approved, margin, page_h - 420, scale: 0.5)
  |> Tincture.text_at(margin + 220, page_h - 380, "Purchasing, fitted to 150 points wide:")
  |> Tincture.place_form_xobject(:approved, margin + 220, page_h - 430, width: 150)

# --- page 2: the same object again ----------------------------------------
pdf =
  pdf
  |> Tincture.add_page()
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(sans, 16)
  |> Tincture.text_at(margin, page_h - 100, "Delivery note")
  |> Tincture.set_font(body, 11)
  |> Tincture.text_at(margin, page_h - 130, "Received complete and undamaged.")
  |> Tincture.place_form_xobject(:approved, page_w - margin - 200, page_h - 220)

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("stamp.pdf")
File.write!(path, binary)

IO.puts("\nwrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")

count = fn pattern -> binary |> String.split(pattern) |> length() |> Kernel.-(1) end

checks = [
  {"one form XObject", "/Subtype /Form", count.("/Subtype /Form") == 1},
  {"placed four times", "/Fm1 Do", count.("/Fm1 Do") == 4},
  {"named on both pages", "/XObject << /Fm1", count.("/XObject << /Fm1") == 2},
  {"alpha inside the stamp", "/ExtGState", binary =~ ~r|/Subtype /Form [^\n]*/ExtGState|},
  if embedded? do
    {"each font embedded once", "/FontFile2", {count.("/FontFile2") == 2, "ok — two fonts"}}
  else
    {"each font embedded once", "/FontFile2", {:note, "no TrueType font found; standard 14"}}
  end
]

IO.puts("""

#{Examples.Checks.table(checks)}

The stamp is one object however many times it is placed. Each placement is
`q sx 0 0 sy x y cm /Fm1 Do Q` in the page's content stream: a transformation,
and a reference.
""")

Examples.Checks.halt_if_missing(checks)
