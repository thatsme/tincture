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

## [`accessible.exs`](accessible.exs) → [`output/accessible.pdf`](output/accessible.pdf)

A quarterly report carrying logical structure: headings to navigate by, a table
whose header cells declare what they govern, alternative text for the chart, and
an explicit reading order.

Nothing in it changes what the page looks like — that is the point. Tagging is
invisible until something needs to *read* the document rather than display it.

Shows:

- **`Tincture.tag/4`**, nesting containers (`:document`, `:section`, `:table`,
  `:tr`) around content elements (`:h1`, `:p`, `:th`, `:td`, `:figure`).
- **`/Scope` on header cells**, which is what lets a reader announce
  "South West, Revenue, 742,300" rather than a bare number.
- **Alternative text** on a figure drawn as vector shapes, which carry no text
  at all — the alt text is the only description that exists.
- **`Tincture.set_language/2`**, without which a screen reader guesses the
  pronunciation.

The table comes from `Layout.Table`, which tags itself — rows, cells, header
scope and artifact borders — when the document is being tagged. The row rules
are marked with `Tincture.artifact/2`, so a reader skips them instead of
announcing them as content.

**Validated.** This document passes veraPDF 1.30.2 against the PDF/UA-1 profile
— 106 of 106 rules, 1701 of 1701 checks:

    verapdf --flavour ua1 examples/output/accessible.pdf

The other examples are not tagged and do not claim conformance; they parse
cleanly but fail the UA rules about structure, as they should.

## [`compliant.exs`](compliant.exs) → [`output/compliant.pdf`](output/compliant.pdf)

The same subject as `accessible.exs` from the other direction: where that is a
report that happens to be tagged, this is a **template**, with each PDF/UA
requirement called out at the point it is satisfied. Copy it and fill it in.

Covers the requirements the other example does not — lists (`:list`,
`:list_item`, `:label`, `:list_body`, so a reader announces "list, four items"
and can skip it) — alongside headings in order, an artifact rule, a tagged
table, and a figure with alternative text.

The script prints a checklist of each requirement and where it came from.

**Validated:** passes veraPDF 1.30.2 against PDF/UA-1 — 106 of 106 rules, 2605
of 2605 checks:

    verapdf --flavour ua1 examples/output/compliant.pdf

## [`archival.exs`](archival.exs) → [`output/archival.pdf`](output/archival.pdf)

A calibration certificate that has to outlive the software that made it,
claiming **PDF/A-2a** — the accessible archival level, which subsumes 2u (text
extractable) and 2b (visual reproduction preserved) and additionally requires
tagging. So one document conforms to both PDF/A and PDF/UA at once.

Shows:

- **`Tincture.set_pdf_a/2`**, which adds the sRGB output intent, the XMP
  conformance claim and the file identifier.
- **The built-in ICC profile.** PDF/A forbids device colour with no stated
  meaning — `1 0 0 rg` alone means "as red as this device gets" — so an output
  intent has to say which red. `Tincture.PDF.ICC` builds one rather than
  depending on a profile being installed.
- **Why the standard 14 fonts are unusable here**: PDF/A requires every font to
  be embedded, and those are referenced by name for the reader to resolve,
  which is the outside dependency the format exists to remove.

Output is deterministic — the file identifier comes from the content and the
ICC profile carries no creation date — so an archived file can be checked
against a rebuild.

**Validated** at three flavours:

    verapdf --flavour 2a  examples/output/archival.pdf
    verapdf --flavour 2b  examples/output/archival.pdf
    verapdf --flavour ua1 examples/output/archival.pdf

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
