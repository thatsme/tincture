# Tincture

Typographic-quality PDF generation for Elixir, with no runtime dependencies.

No Chrome, no wkhtmltopdf, no NIFs, no ports. Font parsing, subsetting,
hyphenation, line breaking, PDF serialisation, encryption and signing are all
Elixir and Erlang/OTP. It runs anywhere the BEAM runs.

```elixir
Tincture.new()
|> Tincture.page_size(:a4)
|> Tincture.register_ttf_font("Body", "Georgia.ttf")
|> Tincture.set_font("Body", 11)
|> Tincture.text_paragraph(50, 700, RichText.from_plain(text, font: "Body", size: 11), 495,
     align: :justified, line_break: :optimal)
|> Tincture.export()
```

Tincture is a **fork of [ex_guten](https://github.com/hwatkins/ex_guten)** by
Hugh Watkins (MIT), itself an Elixir port of Joe Armstrong's Erlang
[erlguten](https://github.com/CarlWright/NGerlguten). Most of the engine is his
work, carried forward here — see [Heritage](#heritage) and [NOTICE](NOTICE).

## Verified against real validators

Standards conformance is easy to claim and easy to get subtly wrong, so it is
checked with [veraPDF](https://verapdf.org) and OpenSSL rather than asserted:

| Standard | Result |
|---|---|
| **PDF/UA-1** (accessibility, ISO 14289-1) | `isCompliant=true` — 106/106 rules |
| **PDF/A-2b** (archival, ISO 19005-2) | `isCompliant=true` — 144/144 rules |
| **PDF/A-2u** (archival, text extractable) | `isCompliant=true` — 146/146 rules |
| **PDF/A-2a** (accessible archival) | `isCompliant=true` — 153/153 rules |
| **PKCS#7 detached signatures** | verified by `openssl cms -verify` |

Reproduce them yourself — the documents are committed:

```bash
verapdf --flavour ua1 examples/output/compliant.pdf
verapdf --flavour 2a  examples/output/archival.pdf
```

Validation earned its place: it found five real defects that 1,200 tests had
not, including every content stream declaring a `/Length` one byte too large,
and `/Scope` on table headers being written somewhere readers ignore. Those are
recorded in [CHANGELOG.md](CHANGELOG.md).

## Install

```elixir
# mix.exs
{:tincture, "~> 0.1"}
```

[Docs on HexDocs](https://hexdocs.pm/tincture). `0.x` is deliberate: the engine
is mature and the standards output is independently verified, but the API under
this name is new and may still move before 1.0.

1,250 tests · 89% coverage · Credo `--strict` clean · Dialyzer clean · CI on
Elixir 1.16–1.19.

## What it does

**Text and typography** — TeX hyphenation (Liang patterns, five locales),
Knuth-Plass global line breaking, justification with configurable widow, orphan
and hyphen penalties, GPOS kerning, GSUB ligatures, basic bidi.

**Fonts** — the standard 14, plus TrueType and OpenType embedding with
**subsetting on by default**, typically 70–90% off an embedded font. Full
`cmap`, `glyf`, `CFF`, `name` and `OS/2` parsing.

**Layout** — text boxes with flow and spill, multi-column flow, tables with
automatic column widths, page templates with headers, footers and numbering,
XML-driven documents.

**Graphics** — lines, rectangles, circles and Bézier paths with fill, stroke and
clip; axial and radial gradients with any number of stops; constant alpha on
fill and stroke; JPEG and PNG embedding with alpha.

**Documents** — metadata, bookmarks, hyperlinks, interactive forms (text,
choice, checkbox, radio group, push button, signature), AES-256 encryption.

**Standards** — tagged PDF for accessibility, PDF/A archival output with a
built-in sRGB output intent, and detached PKCS#7 digital signatures.

**Operations** — telemetry spans per document, per page and per embedded font,
with `:telemetry` as an *optional* dependency so the zero-dependency position
holds.

## Examples

Eight runnable scripts, each with its PDF committed so you can see the output
without running anything. See [examples/README.md](examples/README.md).

```bash
mix examples
```

| | |
|---|---|
| [`gradient.exs`](examples/gradient.exs) | A report cover — axial and radial gradients, alpha, a watermark |
| [`invoice.exs`](examples/invoice.exs) | A commercial invoice — embedded fonts, a table, justified terms, a payment link |
| [`form.exs`](examples/form.exs) | Every interactive field type, with generated appearances |
| [`accessible.exs`](examples/accessible.exs) | A tagged report — headings, table scope, alt text |
| [`compliant.exs`](examples/compliant.exs) | A PDF/UA template, annotated requirement by requirement |
| [`archival.exs`](examples/archival.exs) | PDF/A-2a and PDF/UA-1 in one document |
| [`signed.exs`](examples/signed.exs) | A digitally signed agreement |
| [`telemetry.exs`](examples/telemetry.exs) | The telemetry spans, printed as a document is built |

## What it does not do

Stated plainly, because a library's gaps matter as much as its features:

- **It cannot read PDFs.** Write-only: no merging, stamping, filling someone
  else's template, or text extraction.
- **Complex scripts.** Arabic and the Indic scripts need contextual shaping,
  which is not implemented. "Supports Unicode" is not "typesets Arabic".
- **No timestamp authority.** A signature proves a document has not changed,
  not *when* it was signed.
- **Content streams are uncompressed**, and there are no object or
  cross-reference streams, so files are larger than they need to be.
- **Colour is device RGB, grey and CMYK** — no spot colours, no ICC-based
  spaces beyond the PDF/A output intent.
- **No transparency or gradients** — no `/ExtGState`, no shading.

[ROADMAP.md](ROADMAP.md) sets out each of these and roughly in what order.

## Heritage

Tincture is the fourth link in a chain, and none of it started here:

| | | |
|---|---|---|
| **erlguten** | Joe Armstrong | The original Erlang typesetting system, named for Gutenberg. Armstrong designed the typographic model, the box/glue layout approach and the PDF object assembly that Tincture still follows. |
| **[NGerlguten](https://github.com/CarlWright/NGerlguten)** | Carl Wright | The maintained continuation, which carried erlguten forward with font handling and additional layout work. Last released 2013. |
| **[ex_guten](https://github.com/hwatkins/ex_guten)** | Hugh Watkins, MIT, 2026 | The Elixir port Tincture forks from. Its struct-based (non-`gen_server`) architecture, TrueType/OpenType embedding, Knuth-Plass implementation and parity suite against Armstrong's original `eg_test` documents are all retained here. |
| **Tincture** | this repository | Continues the line. |

The git history is intentionally preserved rather than squashed, so Hugh
Watkins' original commits remain attributable in the log. His copyright notice
is retained in [LICENSE](LICENSE), and [NOTICE](NOTICE) records the full chain
along with the provenance of the bundled font metrics and hyphenation data
under `priv/`.

Tincture is an independent continuation. It is not endorsed by, affiliated
with, or maintained by any of the above authors.

## Architecture

Each layer is usable on its own; the one above it is a convenience.

```
┌──────────────────────────────────────────────┐
│ Tincture            drawing, text, links,    │
│                     forms, tagging, signing  │
├──────────────────────────────────────────────┤
│ Tincture.Layout     boxes, tables, templates │
├──────────────────────────────────────────────┤
│ Tincture.Typography hyphenation, line        │
│                     breaking, kerning        │
├──────────────────────────────────────────────┤
│ Tincture.PDF        document state, fonts,   │
│                     serialisation, crypto    │
├──────────────────────────────────────────────┤
│ Tincture.Font       TrueType, OpenType, CFF  │
└──────────────────────────────────────────────┘
```

A document is an immutable struct threaded through a pipeline. Nothing is
written until `export/2`, so a document can be built, inspected and tested
before any bytes exist — with one deliberate exception: a signature covers the
finished file, so `Tincture.PDF.Sign` reserves space, measures the real offsets
and patches the result.

### Module mapping (erlguten → Tincture)

Names in plain text are internal — they record where the code came from, not an
API you can call.

| erlguten module | Tincture module | Purpose |
|---|---|---|
| `eg_pdf` | `Tincture.PDF` | Core PDF state |
| `eg_pdf_page` | Tincture.PDF.Page | Page management |
| `eg_pdf_lib` | Tincture.PDF.Ops | Drawing operations |
| `eg_pdf_obj` / `eg_pdf_op` | `Tincture.PDF.Serialize`, `.Object`, `.FontEmbed` | Binary assembly |
| `eg_pdf_image` | Tincture.PDF.Image | Image embedding |
| `eg_font_map` | Tincture.Font | Font registry and metrics |
| `eg_afm` | Tincture.Font.AFM | Adobe Font Metrics parsing |
| `eg_richText` | `Tincture.Typography.RichText` | Rich text representation |
| `eg_line_break` | Tincture.Typography.LineBreak | Line breaking |
| `eg_hyphenate` | `Tincture.Typography.Hyphen` | TeX hyphenation |
| `eg_table` | `Tincture.Layout.Table` | Table layout |
| `eg_block` | `Tincture.Layout.Box` | Text box layout |
| `eg_xml_lite` / `eg_xml2richText` | `Tincture.Layout.Template` | XML templates |

Modules with no erlguten ancestor: `Font.Context`, `Font.UnicodeRanges`,
`PDF.Archival`, `PDF.CMS`, `PDF.Encrypt`, `PDF.ICC`, `PDF.Sign`,
`PDF.Structure`, `Telemetry`.

## Design decisions

**Structs over `gen_server`.** erlguten holds PDF state in a process. ex_guten
replaced that with immutable structs and a pipeline API; Tincture keeps it.

**Layered.** Need raw PDF output? Use `Tincture.PDF`. Need typesetting? Use the
top-level API.

**Refuse to lie about the output.** `set_pdf_a/2` writes a conformance claim
into the file, so `export/2` refuses to produce one the document does not meet,
naming every violation. Passing that check is not conformance — Tincture sees
the document it built, not the file a validator sees — which is why the
examples are validated rather than trusted.

## Development

```bash
git clone https://github.com/thatsme/tincture.git
cd tincture
mix deps.get
mix check      # format, warnings-as-errors, Credo, Dialyzer, coverage
mix examples   # rebuild every example PDF
```

Benchmarks and showcase renders live under `scripts/`:

```bash
EX_GUTEN_BENCH_ITERS=500 mix run scripts/benchmark_typography.exs
EX_GUTEN_DOC_BENCH_ITERS=100 mix run scripts/benchmark_document.exs
mix run scripts/render_invoice_showcase.exs tmp/invoice_showcase.pdf
```

## Acknowledgments

- **Joe Armstrong** — original erlguten author and Erlang co-creator
- **Carl Wright** — NGerlguten maintainer, who kept erlguten alive
- **Hugh Watkins** — author of ex_guten, the Elixir port Tincture forks from and
  the source of most of the engine in this repository
- **The TeX community** — hyphenation algorithms and typesetting principles

## License

MIT.
