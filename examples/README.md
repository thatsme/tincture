# Examples

Runnable scripts, each producing a document in [`output/`](output/). The PDFs
are committed, so you can see what the library produces without running
anything.

    mix examples          # run them all
    mix run examples/invoice.exs

Each script embeds a real TrueType font. Font paths are not portable, so
[`support/fonts.exs`](support/fonts.exs) picks the first that exists — Georgia
and Verdana on macOS, Liberation or DejaVu on Linux — and falls back to the
standard 14 if none are installed, in which case the document still renders but
stops demonstrating embedding.

---

## [`invoice.exs`](invoice.exs) → [`output/invoice.pdf`](output/invoice.pdf)

A commercial invoice: filled header band, vector logo, a line-item table with
computed column widths, totals, justified payment terms through the typography
engine, a clickable payment link, and a footer.

Shows:

- **Embedded fonts throughout**, including the justified paragraph. That
  paragraph is the reason this example exists — laying out text in an embedded
  font used to raise `unknown font`, because measurement went through a pure
  function that could only see the standard 14. See `Tincture.Font.Context`.
- **Subsetting**, roughly 75% off each font.
- **Knuth-Plass line breaking** with hyphenation, widow and orphan penalties —
  the same global optimisation TeX uses, rather than greedy first-fit.
- **Paint modes.** `rectangle/6` takes `:fill`, which is newer than it sounds:
  the shape helpers used to stroke unconditionally, and a path-painting
  operator ends the path, so a filled rectangle was impossible.

## [`form.exs`](form.exs) → [`output/form.pdf`](output/form.pdf)

A supplier account application exercising every field type: text (single-line
and multiline), choice, checkbox, radio group, signature and push buttons.

Shows:

- **Radio groups**, the one field that is not a single object. The
  specification models a group as a parent field holding the value with a kid
  widget per button, and a button's export value *is* the name of its "on"
  appearance state.
- **Generated appearance streams.** Every button-like field carries a real
  `/AP`, so the checkboxes and buttons are visible in this static render.
  Relying on `/NeedAppearances` alone leaves them drawn only by interactive
  viewers — invisible when printed, thumbnailed or rasterised server-side.
- **Actions**: submit, reset and open-URL.
- Static text in embedded fonts alongside field values in standard ones. A
  field's value is drawn by the viewer from the AcroForm resource dictionary,
  which cannot reference an embedded font, so form fields are restricted to the
  standard 14 and say so if you try otherwise.

## [`telemetry.exs`](telemetry.exs) → [`output/telemetry.pdf`](output/telemetry.pdf)

Three pages of justified text, with the telemetry events printed as they fire:

```
  font Body      0.38ms  370.7kB -> 83.7kB (77.4% smaller, subset: used_text)
  page 1         0.02ms    3.6kB of content, 75 ops
  page 2         0.16ms    7.3kB of content, 150 ops
  page 3         0.05ms   10.9kB of content, 225 ops
document         5.67ms  106.5kB
  pages 3 · fields 0 · fonts 2 · images 0
```

Shows the three spans — document, page and font — and how to read them. See
`Tincture.Telemetry`. `:telemetry` is an optional dependency; without it the
event calls compile away and the script says so.
