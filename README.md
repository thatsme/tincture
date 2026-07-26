# Tincture

Native, high-fidelity PDF generation for Elixir, distilled from the heritage of Joe Armstrong.

Tincture is a **fork of [ex_guten](https://github.com/hwatkins/ex_guten)** by Hugh Watkins (MIT), which is itself an Elixir port of Joe Armstrong's Erlang [erlguten](https://github.com/CarlWright/NGerlguten). It aims to produce professional-grade PDF documents — from simple one-pagers to complex multi-page layouts with sophisticated typesetting.

Most of the engine — the TrueType/OpenType parser, the Knuth-Plass line breaker, the TeX hyphenation port, the PDF object serialiser — is Hugh Watkins' work, carried forward here. See [Heritage](#heritage) and [NOTICE](NOTICE) for the full attribution chain.

## Why?

The Elixir ecosystem lacks a native PDF generation library with real typographic capabilities. Most existing options are either wrappers around external tools (wkhtmltopdf, Chrome headless) or basic PDF writers without proper text layout. Tincture fills this gap by bringing battle-tested typesetting algorithms — including TeX-style hyphenation and global line-break optimization — directly into Elixir.

## Heritage

Tincture is the fourth link in a chain, and none of it started here:

| | | |
|---|---|---|
| **erlguten** | Joe Armstrong | The original Erlang typesetting system, named for Gutenberg. Armstrong designed the typographic model, the box/glue layout approach and the PDF object assembly that Tincture still follows. |
| **[NGerlguten](https://github.com/CarlWright/NGerlguten)** | Carl Wright | The maintained continuation, which carried erlguten forward with font handling and additional layout work. Last released 2013. |
| **[ex_guten](https://github.com/hwatkins/ex_guten)** | Hugh Watkins, MIT, 2026 | The Elixir port Tincture forks from. Its struct-based (non-`gen_server`) architecture, TrueType/OpenType embedding, Knuth-Plass implementation and parity suite against Armstrong's original `eg_test` documents are all retained here. |
| **Tincture** | this repository | Continues the line. |

The git history is intentionally preserved rather than squashed, so Hugh Watkins' original commits remain attributable in the log. His copyright notice is retained in [LICENSE](LICENSE), and [NOTICE](NOTICE) records the full chain along with the provenance of the bundled font metrics and hyphenation data under `priv/`.

Tincture is an independent continuation. It is not endorsed by, affiliated with, or maintained by any of the above authors.

## Quick Start

```elixir
# Add to mix.exs
{:tincture, "~> 0.1.0"}
```

```elixir
pdf = Tincture.new()
|> Tincture.page_size(:a4)
|> Tincture.export()

File.write!("hello.pdf", pdf)
```

## Features

### Milestone 1 — Core PDF (current)
- [x] Mix project scaffold and test setup
- [x] PDF state struct bootstrap
- [x] Page sizing state API (`:a4`, `:letter`, `:legal`, custom tuple)
- [x] Multi-page state API (`add_page/1`, `set_page/2`)
- [x] Bootstrap PDF binary export (`%PDF-1.4` header)
- [x] Font selection + positioned text (`set_font/3`, `text_at/4`)
- [x] Rotated positioned text (`text_at_rotated/5`)
- [x] Basic vector drawing (`line/5`, `rectangle/5`)
- [x] Circle drawing (`circle/4`) via Bezier curves
- [x] RGB color ops (`set_stroke_color/2`, `set_fill_color/2`)
- [x] Path and graphics-state ops (`move_to/3`, `line_to/3`, `bezier/7`, `stroke/1`, `save_state/1`, `restore_state/1`)
- [x] Fill/clip and line style controls (`fill/1`, `clip/1`, `set_line_width/2`, `set_line_cap/2`, `set_line_join/2`, `set_dash/3`)
- [x] Minimal integration parity test for `eg_test6` and `save/2` disk export helper
- [x] Real PDF object model and serialization (xref/trailer/object consistency covered by parity tests)
- [x] Built-in PDF fonts (14 standard fonts)
- [x] Even-odd fill/clip variants and miter limits (`fill_even_odd/1`, `clip_even_odd/1`, `set_miter_limit/2`)

### Milestone 2 — Typography
- [x] AFM parser bootstrap with character widths and kerning pairs
- [x] `text_width/3` kerning-aware width calculation in the font layer
- [x] Base-14 standard font helpers and `set_font/3` validation
- [x] Font metrics and kerning coverage for standard PDF fonts
- [x] Font-aware PDF content stream text encoding
- [x] English hyphenation bootstrap with upstream rule parity (`hyphenate/1`)
- [x] Greedy ragged-left line breaking bootstrap (`LineBreak.break_text/4`)
- [x] Rich text token model bootstrap (`RichText.from_plain/2`, `RichText.from_runs/1`)
- [x] Paragraph layout bootstrap (`Typography.layout_paragraph/3`) with token-preserving wrapping and line positioning
- [x] Greedy paragraph justification bootstrap (space expansion on non-final lines)
- [x] Paragraph-to-PDF rendering bootstrap (`Tincture.text_paragraph/6`)
- [x] Rotated paragraph rendering via `text_paragraph(..., rotate: degrees)`
- [x] Overflow/spill reporting bootstrap (`Typography.layout_paragraph_with_spill/4`)
- [x] Additional locale ingest from `priv/hyphen/*.dic` (`:da_dk`, `:fi_fi`, `:nb_no`, `:sv_se`)
- [x] Global line-break optimization baseline (`line_break: :optimal` DP badness minimization)
- [x] Full mixed-run justification and optimal line-breaking across styled tokens

### Milestone 3 — Layout Engine
- [x] Text boxes with bounded automatic flow and spill reporting
- [x] Multi-box text flow across columns/regions (`Layout.Box.flow_across_boxes/4`)
- [x] Tables bootstrap (`Layout.Table.render/6`) with headers, borders, and auto column widths
- [x] Table cell vertical alignment (`valign: :top | :middle | :bottom`)
- [x] Styled spill continuity across box boundaries (`RichText.from_tokens/1` + `flow_across_boxes/4`)
- [x] `eg8`-style table parity coverage (multiple tables + escaped text cells)
- [x] Page templates bootstrap (`Layout.Template.new/1`, `with_header/3`, `with_footer/3`, `render/4`, `render_document/4`)
- [x] Full `eg_tmo`-style multi-page integration fixture (template flow + table composition)
- [x] Header/footer slots with page placeholders (`{page}`, `{total}`)

### Milestone 4 — Advanced
- [x] XML/template-driven document generation (`Layout.Template.parse_xml/1`, `render_xml_document/3`)
- [x] JPEG image embedding and positioning (`Tincture.image_jpeg/6`)
- [x] PNG image embedding (alpha channel support, `Tincture.image_png/6`)
- [x] TrueType font embedding baseline (`Tincture.register_ttf_font/3`)
- [x] OpenType font embedding baseline (`Tincture.register_otf_font/3`)
- [x] Embedded font subsetting, **on by default** (`subset: :used_text`; also `:ascii_basic` and `:none`). Typically cuts an embedded font by 70-90%.
- [x] Unicode/UTF-8 PDF string encoding (UTF-16BE hex for non-ASCII text)
- [x] PDF metadata (`Tincture.set_metadata/2`)
- [x] PDF bookmarks / table of contents (`Tincture.add_bookmark/3`)
- [x] Hyperlinks and annotations — external URLs and internal page targets (`Tincture.link/6`, `Tincture.text_link/5`)
- [x] Interactive forms (AcroForm) — text fields, checkboxes and choice fields (`Tincture.text_field/7`, `Tincture.checkbox/6`, `Tincture.choice_field/7`)
- [x] `kd_test1`-style commercial bill parity fixture with logo (`test/kd_test1_parity_test.exs`)

## Architecture

Tincture is organized into layers, each usable independently:

```
┌─────────────────────────────────┐
│  Tincture (high-level API)       │  ← What most users interact with
├─────────────────────────────────┤
│  Tincture.Layout                 │  ← Text boxes, columns, templates
├─────────────────────────────────┤
│  Tincture.Typography             │  ← Hyphenation, justification, kerning
├─────────────────────────────────┤
│  Tincture.PDF                    │  ← PDF object model, pages, fonts
├─────────────────────────────────┤
│  PDF serialization layer        │  ← Binary PDF output
└─────────────────────────────────┘
```

### Module Mapping (erlguten → Tincture)

| erlguten module | Tincture module | Purpose |
|---|---|---|
| `eg_pdf` | `Tincture.PDF` | Core PDF process/state |
| `eg_pdf_page` | `lib/tincture/pdf/page.ex` | Page management |
| `eg_pdf_lib` | `lib/tincture/pdf/ops.ex` | PDF drawing operations |
| `eg_pdf_obj` / `eg_pdf_op` / `eg_pdf` export path | `lib/tincture/pdf/serialize.ex` | PDF binary assembly |
| `eg_pdf_image` | `lib/tincture/pdf/image.ex` | Image embedding |
| `eg_font_map` | `lib/tincture/font.ex` | Font registry and metrics |
| `eg_afm` | `lib/tincture/font/afm.ex` | Adobe Font Metrics parsing |
| `eg_richText` | `lib/tincture/typography/rich_text.ex` | Rich text representation |
| `eg_line_break` | `lib/tincture/typography/line_break.ex` | Line breaking algorithm |
| `eg_hyphenate` | `lib/tincture/typography/hyphen.ex` | TeX hyphenation |
| `eg_table` | `lib/tincture/layout/table.ex` | Table layout |
| `eg_block` | `lib/tincture/layout/box.ex` | Text box layout |
| `eg_xml_lite` / `eg_xml_tokenise` / `eg_xml2richText` | `lib/tincture/layout/template.ex` | XML template processing |

## Design Decisions

**Structs over gen_server:** The original erlguten uses a `gen_server` process to hold PDF state. ex_guten replaced that with immutable structs and a pipeline API (`|>`), which is more idiomatic Elixir and easier to test; Tincture keeps that design.

**Layered architecture:** Each layer can be used independently. Need just raw PDF output? Use `Tincture.PDF` directly. Need full typesetting? Use the top-level `Tincture` API.

**Progressive porting:** Not everything needs to be ported at once. The core PDF generation layer is useful on its own, even before the typography engine is complete.

## Development

```bash
git clone https://github.com/thatsme/tincture.git
cd tincture
mix deps.get
mix test
```

Typography benchmark (local):

```bash
EX_GUTEN_BENCH_ITERS=500 EX_GUTEN_BENCH_WARMUP=100 mix run scripts/benchmark_typography.exs
```

Optional typography guardrail scaling:

```bash
EX_GUTEN_BENCH_SPEED_FACTOR=1.5 mix run scripts/benchmark_typography.exs
```

Document benchmark (local):

```bash
EX_GUTEN_DOC_BENCH_ITERS=100 EX_GUTEN_DOC_BENCH_WARMUP=10 mix run scripts/benchmark_document.exs
```

Optional document guardrail scaling:

```bash
EX_GUTEN_DOC_BENCH_SPEED_FACTOR=1.5 EX_GUTEN_DOC_BENCH_MEMORY_FACTOR=1.5 mix run scripts/benchmark_document.exs
```

Showcase renders (local):

```bash
# invoice showcase
mix run scripts/render_invoice_showcase.exs tmp/invoice_showcase.pdf

# bank statement (retail baseline variant)
mix run scripts/render_bank_statement_showcase.exs retail tmp/bank_statement_showcase.pdf

# bank statement (joint fee/interest variant)
mix run scripts/render_bank_statement_showcase.exs joint tmp/bank_statement_joint_fee_interest_showcase.pdf

# graphics-heavy marketing poster
mix run scripts/render_marketing_poster_showcase.exs tmp/marketing_poster_showcase.pdf

# multi-font report
mix run scripts/render_multi_font_report_showcase.exs tmp/multi_font_report_showcase.pdf

# markdown subset -> PDF (uses bundled sample markdown by default)
mix run scripts/render_markdown_showcase.exs tmp/markdown_showcase.pdf

# markdown subset -> PDF (custom markdown file)
mix run scripts/render_markdown_showcase.exs path/to/input.md tmp/markdown_from_file_showcase.pdf
```

## Acknowledgments

- **Joe Armstrong** — Original erlguten author and Erlang co-creator
- **Carl Wright** — NGerlguten maintainer, who kept erlguten alive
- **Hugh Watkins** — Author of ex_guten, the Elixir port Tincture forks from and
  the source of most of the engine in this repository
- **The TeX community** — Hyphenation algorithms and typesetting principles

## License

MIT.


