Code.require_file("support/fonts.exs", __DIR__)

# Transparency and shading: a report cover.
#
# Everything else in examples/ is a document you read. This is the one you look
# at first, and it is the case the drawing API could not serve until now — there
# was no way to vary a colour across a region, or to draw anything at less than
# full opacity.
#
# Three things are new here:
#
#   set_alpha/2       constant alpha for fill and stroke, as graphics state
#   linear_gradient/7 an axial gradient, two stops or many
#   radial_gradient/7 the same, radiating from a centre
#
# A gradient is paint, not a shape: it fills the rectangle you give it and
# ignores the current fill colour. Alpha is state and applies to everything
# after it, which is why each use below is fenced in save_state/restore_state.

alias Tincture.Typography.RichText

page_w = 595
page_h = 842
margin = 50

paper = {0.99, 0.99, 0.98}
ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Regional performance, Q2 2026",
    author: "Northgate Instruments Ltd",
    subject: "Cover page demonstrating transparency and shading"
  )
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

# --- the cover band -------------------------------------------------------
# A single vertical gradient, deep blue at the top falling to near-black. Two
# stops is the common case and interpolates directly; the extra stop here bends
# the falloff so the middle stays saturated instead of going muddy.
band_h = 360

pdf =
  Tincture.linear_gradient(pdf, 0, page_h - band_h, page_w, band_h, [
    {0.0, {0.04, 0.28, 0.50}},
    {0.55, {0.05, 0.16, 0.32}},
    {1.0, {0.02, 0.04, 0.09}}
  ])

# --- a glow behind the mark -----------------------------------------------
# Radial, and deliberately larger than it looks: with `extend` on, the outer
# colour continues past the last stop, so the rectangle fills to its corners
# rather than leaving a visible disc edge. Drawn at low alpha so it reads as
# light rather than as a shape.
glow_cx = margin + 26
glow_cy = page_h - 96

pdf =
  pdf
  |> Tincture.save_state()
  |> Tincture.set_alpha(0.55)
  |> Tincture.radial_gradient(
    glow_cx - 90,
    glow_cy - 90,
    180,
    180,
    [
      {0.0, {0.35, 0.72, 0.95}},
      {1.0, {0.04, 0.20, 0.38}}
    ],
    center: {glow_cx, glow_cy},
    radius: 78
  )
  |> Tincture.restore_state()

# The mark itself: an open ring with a gauge needle, as in invoice.exs.
pdf =
  pdf
  |> Tincture.set_stroke_color({1.0, 1.0, 1.0})
  |> Tincture.set_line_width(2.2)
  |> Tincture.circle(glow_cx, glow_cy, 15, :stroke)
  |> Tincture.set_line_width(1.6)
  |> Tincture.line(glow_cx, glow_cy, glow_cx + 9, glow_cy + 8)
  |> Tincture.set_fill_color({1.0, 1.0, 1.0})
  |> Tincture.circle(glow_cx, glow_cy, 2.6, :fill)

# --- title ----------------------------------------------------------------
pdf =
  pdf
  |> Tincture.set_fill_color({1.0, 1.0, 1.0})
  |> Tincture.set_font(body, 34)
  |> Tincture.text_at(margin, page_h - 190, "Regional performance")
  |> Tincture.set_font(sans, 13)
  |> Tincture.text_at(margin, page_h - 214, "Second quarter, 2026")

# A three-stop rule under the title, left to right. The same call that draws a
# two-stop gradient draws this one - the stitching is the serialiser's problem.
pdf =
  Tincture.linear_gradient(
    pdf,
    margin,
    page_h - 240,
    page_w - margin * 2,
    3,
    [
      {0.0, {0.95, 0.62, 0.20}},
      {0.5, {0.85, 0.25, 0.35}},
      {1.0, {0.35, 0.45, 0.85}}
    ],
    direction: :horizontal
  )

# --- the sheet below ------------------------------------------------------
pdf =
  pdf
  |> Tincture.set_fill_color(paper)
  |> Tincture.rectangle(0, 0, page_w, page_h - band_h, :fill)

summary =
  "This cover exists to exercise two additions: constant alpha, and axial and " <>
    "radial shadings. Neither changes how text is measured or laid out — the " <>
    "paragraph below is set by the same typography engine as every other " <>
    "example, with hyphenation and optimal line breaking — but until now there " <>
    "was no way to put anything behind it except a flat rectangle."

pdf =
  Tincture.text_paragraph(
    pdf
    |> Tincture.set_fill_color(ink),
    margin,
    page_h - band_h - 60,
    RichText.from_plain(summary, font: body, size: 11),
    page_w - margin * 2,
    align: :justified,
    line_break: :optimal
  )

# --- a watermark ----------------------------------------------------------
# The plainest use of alpha: the same draw, at 8% opacity. Without save_state
# the alpha would apply to everything drawn afterwards, which is the mistake
# this fence exists to prevent.
pdf =
  pdf
  |> Tincture.save_state()
  |> Tincture.set_alpha(0.08)
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(body, 68)
  |> Tincture.text_at_rotated(margin + 40, 150, 28, "DRAFT")
  |> Tincture.restore_state()

pdf =
  pdf
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 8)
  |> Tincture.text_at(margin, 40, "Northgate Instruments Ltd · generated by Tincture")

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("gradient.pdf")
File.write!(path, binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")
