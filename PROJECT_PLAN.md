# Tincture Project Plan
## Porting erlguten to Elixir

### Overview

erlguten is a mature Erlang codebase with 47 Erlang modules in `src/`. The non-generated core is ~15,775 lines, and generated hyphen-rule modules bring the full `src/` total to ~57,267 lines. This plan breaks the port into incremental milestones, each producing a usable, publishable library.

**Estimated total effort:** 3-6 months of part-time work
**Strategy:** Port bottom-up (PDF primitives → typography → layout), with each milestone deployable to Hex.pm

### Upstream Snapshot (source of truth for this plan)

- Upstream repo: `https://github.com/hwatkins/erlguten`
- HEAD commit: `9a95e2bf3d4d13f764574cd7c7c27403b8a478e5`
- Commit date: 2017-01-11
- Modules: 47 (`src/*.erl`)
- Test modules: 16 (`test/*.erl`)

---

### Phase 0: Project Setup (Week 1)

**Goal:** Repo scaffolding, CI, initial structure

- [x] Create `tincture` repo with `mix new tincture --module Tincture`
- [x] Set up GitHub Actions CI (Elixir 1.16+, OTP 26+)
- [x] Add LICENSE (Apache 2.0)
- [x] Add README with vision and architecture diagram
- [x] Add `.formatter.exs`, `credo`, `dialyxir` to dev deps
- [x] Create module directory structure:
  ```
  lib/
    tincture.ex                    # Top-level API
    tincture/
      pdf.ex                       # Core PDF state
      pdf/
        page.ex                    # Page management
        ops.ex                     # Drawing operations
        serialize.ex               # PDF binary output
        image.ex                   # Image embedding
        object.ex                  # PDF object types
      font.ex                      # Font registry
      font/
        afm.ex                     # AFM parser
        metrics.ex                 # Font metrics
      typography/
        rich_text.ex               # Rich text structs
        line_break.ex              # Line breaking
        hyphen.ex                  # Hyphenation
      layout/
        table.ex                   # Table layout
        box.ex                     # Text boxes
        template.ex                # XML templates
  ```
- [x] Copy font metrics files (`priv/afm/`) from erlguten
- [x] Copy TeX hyphenation patterns (`priv/hyphen/`) from erlguten
- [x] First commit, first green CI badge

**Deliverable:** Empty but well-structured project with passing CI

---

### Phase 1: Core PDF Generation (Weeks 2-5)

**Goal:** Generate valid PDF files with text and basic graphics

**Port these erlguten modules:**
| erlguten | Tincture | Lines (approx) | Complexity |
|---|---|---|---|
| `eg_pdf` | `Tincture.PDF` | ~800 | High — gen_server → struct |
| `eg_pdf_page` | `Tincture.PDF.Page` | ~200 | Medium |
| `eg_pdf_lib` | `Tincture.PDF.Ops` | ~400 | Medium — drawing primitives |
| `eg_pdf_obj` | `Tincture.PDF.Object` | ~200 | Medium — PDF object construction |
| `eg_pdf_op` | `Tincture.PDF.Op` | ~500 | Medium — operation encoding |
| `eg_pdf` (export path) | `Tincture.PDF.Serialize` | ~700 | High — binary PDF format |

**Key tasks:**
- [x] Define `%Tincture.PDF{}` struct (replaces gen_server state)
  - Pages list, current page, fonts, images, metadata
- [x] Implement page management
  - `new/0`, `page_size/2`, `set_page/2`, `add_page/1`
  - Support: `:a4`, `:letter`, `:legal`, and custom `{width, height}`
- [x] Implement PDF drawing operations (port `eg_pdf_lib`)
  - `text_at/4` — place text at coordinates
  - `line/5` — draw line between points
  - `rectangle/5` — draw rectangle
  - `circle/4` — draw circle
  - `set_font/3` — set current font and size
  - `set_fill_color/2`, `set_stroke_color/2`
  - `save_state/1`, `restore_state/1`
  - `move_to/3`, `line_to/3`, `bezier/coordinates`
- [x] Implement PDF serialization (port export/object assembly paths from `eg_pdf`, `eg_pdf_obj`, and `eg_pdf_op`)
  - PDF header, object table, cross-reference table, trailer
  - Page tree construction
  - Content stream generation
  - `export/1` → returns PDF binary
- [x] Write tests that generate PDFs and verify structure
  - Port `eg_test6` (minimal PDF) as first integration test
  - Port `eg_test1` (comprehensive feature test)

**Current progress (2026-02-18):**
- Implemented multi-page `%Tincture.PDF{}` state with current page tracking and per-page operation storage
- Implemented `new/0`, `page_size/2`, `set_page/2`, `add_page/1`, `set_font/3`, `text_at/4`, `text_at_rotated/5`, `line/5`, `rectangle/5`, `circle/4`, `set_fill_color/2`, `set_stroke_color/2`, `move_to/3`, `line_to/3`, `bezier/7`, `stroke/1`, `fill/1`, `clip/1`, `set_line_width/2`, `set_line_cap/2`, `set_line_join/2`, `set_dash/3`, `save_state/1`, `restore_state/1`, `export/1`, `save/2`
- Implemented valid PDF serialization with catalog/page tree, per-page content streams/resources, xref, and trailer
- Added tests for structure, page switching, multi-page serialization, page size, font resources, drawing operations, and `eg_test6`/`eg_test1` integration parity coverage

**Milestone test:**
```elixir
pdf = Tincture.new()
|> Tincture.page_size(:a4)
|> Tincture.set_font("Helvetica", 14)
|> Tincture.text_at(50, 700, "Hello from Tincture!")
|> Tincture.line(50, 695, 200, 695)
|> Tincture.export()

File.write!("test.pdf", pdf)
# Opens in any PDF reader ✓
```

**Deliverable:** Publish `tincture` v0.1.0 to Hex.pm — basic PDF generation

---

### Phase 2: Font System (Weeks 6-8)

**Goal:** Proper font metrics, kerning, and the 14 standard PDF fonts

**Port these modules:**
| erlguten | Tincture | Lines (approx) | Complexity |
|---|---|---|---|
| `eg_font_map` | `Tincture.Font` | ~300 | Medium |
| `eg_afm` | `Tincture.Font.AFM` | ~400 | Medium — file parsing |
| `eg_font_14` | `Tincture.Font.Standard` | ~100 | Low |

**Key tasks:**
- [x] Port AFM (Adobe Font Metrics) parser
  - Parse character widths, kerning pairs, font bounding box
  - Load from `priv/afm/*.afm` files at compile time or on demand
- [x] Implement font registry
  - Map font names → metrics
  - 14 standard PDF fonts: Helvetica, Times-Roman, Courier (+ bold/italic variants), Symbol, ZapfDingbats
- [x] Implement text width calculation
  - `Tincture.Font.text_width(font, size, string)` → points
  - Account for kerning pairs
- [x] Integrate with PDF ops — font encoding in content streams
- [x] Port `eg_test4` (font showcase test)

**Current progress (2026-02-18):**
- Implemented `Tincture.Font.AFM.parse_file/1` and `parse_string/1` for AFM font name, char widths, glyph names, and kern pairs
- Implemented `Tincture.Font.text_width/3` with kerning-aware width calculation from AFM metrics
- Implemented cached font registry lookup and base-14 standard font helpers (`standard_font?/1`, `font_available?/1`)
- Imported and parsed upstream `eg_font_1..14` metric sources under `priv/standard_fonts/` for standard font width/kerning coverage
- Integrated font-aware content stream encoding (single-byte PDF string encoding with escaping + unsupported glyph fallback)
- Added tests for AFM parse behavior and kerning-adjusted width calculations
- Added `eg_test4`-style parity coverage to assert base-14 font showcase serialization

**Deliverable:** Publish v0.2.0 — accurate font metrics and kerning

---

### Phase 3: Typography Engine (Weeks 9-14)

**Goal:** Paragraph layout with hyphenation and justification

**Port these modules:**
| erlguten | Tincture | Lines (approx) | Complexity |
|---|---|---|---|
| `eg_richText` | `Tincture.Typography.RichText` | ~500 | High |
| `eg_line_break` | `Tincture.Typography.LineBreak` | ~600 | High — Knuth-Plass |
| `eg_hyphenate` | `Tincture.Typography.Hyphen` | ~300 | Medium |
| `eg_hyphen_rules_*` | `Tincture.Typography.Hyphen.Rules` | ~2000 | Low (data) |

**Key tasks:**
- [x] Define rich text structs
  - `%RichText{}` — text with inline font/size/style changes
  - `%Word{}`, `%Space{}`, `%Break{}` types
- [x] Port TeX hyphenation algorithm (baseline + locale ingest)
  - Load hyphenation patterns from `priv/hyphen/` files (`.dic` ingest for multiple locales)
  - Support English (default), extensible to other languages
  - `Tincture.Typography.Hyphen.hyphenate("algorithm")` → `["al", "go", "rithm"]`
- [x] Port line-breaking algorithm (global optimization baseline)
  - DP badness minimization (Knuth-Plass-lite) for balanced raggedness
  - Support justification modes: `:left`, `:right`, `:center`, `:justified`
  - Handle mixed fonts within a line
- [x] Build paragraph layout
  - `Tincture.Typography.layout_paragraph(rich_text, width, opts)`
  - Returns list of laid-out lines with positions
- [x] Port `eg_test3` (justification tests)
- [x] Port `eg_test5` (rotated text blocks)

**Current progress (2026-02-18):**
- Implemented `Tincture.Typography.Hyphen.hyphenate/1` with upstream `eg_hyphen_rules_en_GB` clause parity and exceptions
- Added hyphenation parity tests for `hyphenation`, `algorithm`, `supercalifragilisticexpialidocious`, and `however`
- Short-word behavior implemented (`length <= 4` no hyphenation), matching upstream cutoff behavior
- Added `.dic` hyphen pattern ingest for additional locales (`:da_dk`, `:fi_fi`, `:nb_no`, `:sv_se`)
- Implemented greedy ragged-left line-breaking bootstrap in `Tincture.Typography.LineBreak.break_text/4` with width checks from `Tincture.Font.text_width/3`
- Added line-breaking tests for exact-fit, greedy wraps, and hyphenation-assisted splits
- Added `eg_test3`-style parity coverage for justification/centering/right alignment blocks and mixed-font paragraph rendering
- Implemented rich-text tokenization bootstrap in `Tincture.Typography.RichText` with `%Run{}`, `%Word{}`, `%Space{}`, and `%Break{}` tokens
- Implemented paragraph layout bootstrap in `Tincture.Typography.layout_paragraph/3` with greedy token wrapping, line `x`/`y` positions, and `:left`/`:center`/`:right`/`:justified` alignment offsets
- Added `line_break: :optimal` mode in `Tincture.Typography.layout_paragraph/3` with global dynamic-programming line selection
- Added regression coverage proving optimal mode improves raggedness vs greedy on a deterministic case
- Added mixed-run regression coverage for styled-token optimal wrapping with `align: :justified`
- Implemented justification space expansion for non-final lines in `:justified` mode
- Added high-level paragraph rendering API `Tincture.text_paragraph/6` to emit positioned text operations from `RichText` layout output
- Added paragraph rotation option (`rotate:`) in `Tincture.text_paragraph/6` using rotated PDF text matrices
- Added overflow/spill reporting API `Tincture.Typography.layout_paragraph_with_spill/4` for bounded-line layout
- Added `eg5`-style parity coverage for multiple rotated paragraph blocks with mixed alignment modes

**Deliverable:** Publish v0.3.0 — typographic paragraph layout

---

### Phase 4: Layout Engine (Weeks 15-20)

**Goal:** Text boxes, tables, multi-column, and page templates

**Port these modules:**
| erlguten | Tincture | Lines (approx) | Complexity |
|---|---|---|---|
| `eg_table` | `Tincture.Layout.Table` | ~400 | Medium |
| `eg_block` | `Tincture.Layout.Box` | ~300 | Medium |
| `eg_xml_lite` / `eg_xml_tokenise` / `eg_xml2richText` | `Tincture.Layout.Template` | ~500 | High |

**Key tasks:**
- [x] Implement text boxes
  - Auto-flowing text within a defined rectangle
  - Overflow detection (text that doesn't fit)
  - Rotation support
- [x] Implement tables
  - Column definitions with widths
  - Cell padding and borders
  - Header rows
  - Auto-sizing columns based on content
- [x] Implement page templates
  - Define reusable page layouts (margins, columns, headers/footers)
  - Template-based document generation
- [x] Implement multi-column text flow
  - Text flows from one box to the next across columns/pages
- [x] Port `eg_test8` (table tests)
- [x] Port `eg_tmo_test` (full document)

**Current progress (2026-02-18):**
- Implemented `Tincture.Layout.Box.flow_text/7` for bounded text flow in a rectangle
- Integrated with `Tincture.Typography.layout_paragraph_with_spill/4` to expose visible lines + spill metadata
- Added support for alignment, custom line height, and optional rotation (`rotate:`) for rendered box text
- Added unit coverage for flow rendering, spill behavior, and invalid option handling
- Implemented `Tincture.Layout.Box.flow_across_boxes/4` to chain text flow across multiple boxes/columns with aggregated overflow reporting
- Implemented `Tincture.Layout.Table.render/6` bootstrap with explicit or auto-scaled column widths, cell borders/padding, header rows, and render metadata
- Added styled spill continuity across boxes by reconstructing rich text from spill tokens (`RichText.from_tokens/1`)
- Added `eg8`-style parity coverage for multi-table rendering, header rows, auto widths, and escaped cell text
- Implemented `Tincture.Layout.Template` bootstrap (`new/1`, `with_header/3`, `with_footer/3`, `render/4`) with reusable region layout and slot rendering
- Added full `eg_tmo`-style multi-page parity coverage (template document flow with page placeholders and composed table sections)

**Deliverable:** Publish v0.4.0 — full layout engine

---

### Phase 5: Images and Advanced Features (Weeks 21-26)

**Goal:** Image support, unicode, and XML templates

**Port these modules:**
| erlguten | Tincture | Lines (approx) | Complexity |
|---|---|---|---|
| `eg_pdf_image` | `Tincture.PDF.Image` | ~300 | Medium |

**Key tasks:**
- [x] JPEG image embedding
- [x] PNG image embedding (with alpha)
- [x] Image scaling and positioning
- [x] Unicode/UTF-8 text support (baseline PDF UTF-16BE string encoding)
- [x] TrueType font embedding
- [x] PDF metadata (title, author, keywords)
- [x] PDF bookmarks / table of contents
- [x] XML template parsing (optional — EEx might be better for Elixir)
- [x] Port `kd_test1` (commercial bill with logo)

**Current progress (2026-02-18):**
- Added `Tincture.image_jpeg/6` and `Tincture.PDF.Image` JPEG metadata parsing (dimensions, color space, bits/component)
- Added PDF image state tracking (`PDF.images`) and image operations (`{:image, ...}`) with per-page placement
- Extended serializer to emit JPEG XObjects (`/Subtype /Image`, `/Filter /DCTDecode`) and page `/XObject` resource dictionaries
- Added `Tincture.image_png/6` with PNG parsing, scanline decoding, and `/FlateDecode` image objects
- Added PNG alpha support via soft masks (`/SMask`) by extracting alpha channels into grayscale image XObjects
- Added transform-matrix image painting (`cm` + `Do`) for explicit scaling and positioning
- Added regression coverage for JPEG and PNG(+alpha) embedding and draw command serialization in `test/tincture_test.exs`
- Added `Tincture.add_bookmark/3` and PDF outline serialization (`/Outlines`, `/Dest`, linked `Prev`/`Next` items)
- Added UTF-8-safe PDF text/metadata/bookmark encoding via UTF-16BE hex strings for non-ASCII content
- Added `Tincture.register_ttf_font/3` and baseline embedded TrueType serialization (`/FontFile2`, descriptor, `/Subtype /TrueType`)
- Added `Tincture.register_otf_font/3` and baseline embedded OpenType serialization (`/FontFile3`, `/Subtype /OpenType`)
- Added XML template parsing/rendering entry points (`Layout.Template.parse_xml/1`, `render_xml_document/3`) using `:xmerl`
- Added `kd_test1`-style commercial bill parity coverage with logo image, metadata, bookmarks, and line-item table

**Deliverable:** Publish v1.0.0 — feature-complete

---

### Phase 6: Beyond Baseline (Post-v1.0)

**Goal:** Move typography/font/unicode behavior from baseline parity to production-grade quality

**Key tasks:**
- [x] Full Knuth-Plass line breaking
  - [x] Replace current DP badness scoring with box/glue/penalty model (default migrated to `:box_glue`; `:quadratic` retained as explicit compatibility opt-in)
  - [x] Add penalties for hyphenation, consecutive hyphens, widows/orphans, and fitness classes
  - [x] Support controlled stretch/shrink behavior for justified lines (opt-in multipliers implemented)
- [x] Production-grade font embedding
  - [x] Parse real font tables (`cmap`, `hmtx`, `glyf/loca` or CFF, `OS/2`, etc.)
    - [x] Added strict TTF metric-table parser for `head`, `maxp`, `hhea`, and `hmtx` (`Tincture.Font.TTF.parse_basic_tables/1`)
    - [x] Added `head` table FontBBox extraction (`xMin`/`yMin`/`xMax`/`yMax`) for descriptor fallback metrics
    - [x] Added `cmap` extraction (format 0/2/4/6/8/10/12/13/14 support), including format-2 high-byte mappings, format-4 mappings beyond Latin-1, format-6 trimmed-table mappings, format-8 group mappings, format-10 trimmed 32-bit mappings, format-12 non-BMP codepoint→glyph lookup, format-13 many-to-one group mappings, and format-14 variation-selector metadata
    - [x] Added optional `loca`/`glyf` parsing for glyph offsets and glyph bounding boxes
    - [x] Added `glyf` outline-kind extraction (`:simple`/`:composite`) from glyph headers for parsed outline metadata
    - [x] Added `glyf` contour-count extraction for simple glyphs (`glyph_contour_counts_by_id`) for parsed outline metadata
    - [x] Added `glyf` simple point-count extraction (`glyph_point_counts_by_id`) from endpoint arrays for parsed outline metadata
    - [x] Added `glyf` composite instruction-length extraction (`glyph_composite_instruction_lengths_by_id`) from composite instruction records for parsed outline metadata
    - [x] Added `glyf` composite component-count extraction (`glyph_component_counts_by_id`) from component records for parsed outline metadata
    - [x] Added `glyf` composite component-glyph extraction (`glyph_component_glyph_ids_by_id`) from component records for parsed outline metadata
    - [x] Added `hhea` + optional `OS/2` vertical metric extraction (`hhea_ascender`/`hhea_descender`/`hhea_line_gap`, `typo_ascender`/`typo_descender`/`typo_line_gap`, `cap_height`)
    - [x] Added `hhea` `advanceWidthMax` extraction for descriptor width metrics
    - [x] Added `hmtx` max-advance-width extraction for descriptor width metrics
    - [x] Added `OS/2` `sxHeight` extraction for descriptor x-height metrics
    - [x] Added `OS/2` weight-class extraction (`usWeightClass`) for descriptor style metrics
    - [x] Added `OS/2` width-class extraction (`usWidthClass`) for descriptor stretch metrics
    - [x] Added `OS/2` average-char-width extraction (`xAvgCharWidth`) for descriptor width metrics
    - [x] Added `OS/2` first/last-char extraction (`usFirstCharIndex`/`usLastCharIndex`) for non-subset char-range metrics
    - [x] Added `OS/2` default-char extraction (`usDefaultChar`) for descriptor missing-width metrics
    - [x] Added `OS/2` break-char extraction (`usBreakChar`) for descriptor missing-width fallback metrics
    - [x] Added `OS/2` max-context extraction (`usMaxContext`) for shaping-policy metrics
    - [x] Added `OS/2` optical-size extraction (`usLowerOpticalPointSize`/`usUpperOpticalPointSize`) for parser metadata completeness
    - [x] Added `OS/2` family/vendor extraction (`sFamilyClass`/`achVendID`) for parser metadata completeness
    - [x] Added `OS/2` raw-version and selection extraction (`version`/`fsSelection`) for parser metadata completeness
    - [x] Added baseline GSUB/GPOS layout metadata extraction (script/feature tags) for shaping groundwork
    - [x] Added baseline GSUB ligature lookup parsing (LookupType 4 / LigatureSubst Format 1) with codepoint-mapped substitutions
    - [x] Added baseline GSUB single-substitution lookup parsing (LookupType 1 / SingleSubst Formats 1 and 2) with codepoint-mapped substitutions
    - [x] Added baseline GPOS pair-adjustment parsing (LookupType 2 / PairPos Format 1) with codepoint-mapped x-advance kerning pairs
    - [x] Filtered GSUB/GPOS lookup parsing to feature-linked lookup indices via ScriptList/LangSys/FeatureList linkage (`liga` and `kern`)
    - [x] Added all-script GSUB substitution map extraction (`gsub_substitutions_all`) from feature-linked `liga`/`rlig`/`ccmp` lookups for shaping-mode replacements
    - [x] Added LangSys prioritization for feature-linked GSUB/GPOS lookups (prefer default LangSys; fallback to named when default has no usable features)
    - [x] Added script-tag prioritization for feature-linked GSUB/GPOS lookups (prefer `latn`, then `DFLT`, then fallback to available scripts)
    - [x] Added `OS/2` unicode-range extraction (`ulUnicodeRange1..4`) for glyph-support heuristics
    - [x] Added `OS/2` code-page-range extraction (`ulCodePageRange1..2`) for glyph-support heuristics
    - [x] Added `OS/2` embedding-permissions extraction (`fsType`) for descriptor policy metrics
    - [x] Added `OS/2` win ascent/descent extraction (`usWinAscent`/`usWinDescent`) for descriptor fallback metrics
    - [x] Added `OS/2` fsSelection extraction for style metadata (`italic`/`bold`/`oblique` bits)
    - [x] Added `OS/2` Panose extraction for descriptor style dictionaries
    - [x] Added `OS/2` script/decoration metric extraction (`ySubscript*`, `ySuperscript*`, `yStrikeout*`) for parser metadata completeness
    - [x] Added `head`/`post` style extraction for italic metadata (`macStyle` italic bit + fixed-point `italicAngle`)
    - [x] Added `head` macStyle bold extraction for descriptor force-bold metrics
    - [x] Added `post` fixed-pitch extraction (`isFixedPitch`) for descriptor flag metrics
    - [x] Added `name` table extraction for family-name metadata (`font_family`) and descriptor naming support
    - [x] Added baseline `CFF ` family-name fallback extraction (Top DICT `FamilyName` SID + String INDEX) when `name` metadata is unavailable
    - [x] Added baseline `CFF ` full-name fallback extraction (Top DICT `FullName` SID + String INDEX) when `FamilyName` and `name` metadata are unavailable
    - [x] Added baseline `CFF ` font-name fallback extraction (Top DICT `FontName` SID + String INDEX) when `FamilyName`, `FullName`, and `name` metadata are unavailable
    - [x] Added baseline `CFF ` weight fallback extraction (Top DICT `Weight` SID + String INDEX) when `OS/2 usWeightClass` metadata is unavailable
    - [x] Added baseline `CFF ` Private DICT `StdVW` extraction for descriptor stem metrics when `OS/2 usWeightClass` metadata is unavailable
    - [x] Enforced parser-backed TTF validation in `register_ttf_font/3` and attached parsed `:ttf_metrics` to embedded font state
    - [x] Added baseline `CFF ` Top DICT `FontBBox` extraction for OTF/CFF fonts when `loca`/`glyf` tables are unavailable
    - [x] Added baseline `CFF ` CharStrings INDEX extraction (`cff_charstring_count`, `cff_charstring_lengths_by_id`) for OTF/CFF outline metadata when `loca`/`glyf` tables are unavailable
    - [x] Added baseline `CFF ` Top DICT style extraction (`ItalicAngle`, `isFixedPitch`) when `post` metadata is unavailable
    - [x] Extended CFF DICT number parsing in OTF subset scanning to handle real (`30`) and fixed (`255`) operands, preserving CharStrings discovery when Top DICT metadata (for example `FontMatrix`) precedes `CharStrings`
    - [x] Extend parsing to glyph outlines and additional descriptor tables (CFF, full `OS/2` coverage, etc.)
  - [x] Subset embedded fonts to only used glyphs (TTF `glyf`/`loca` path + OTF/CFF CharStrings shrink path for subset modes, with full-font fallback when subsetting is unsafe)
  - [x] Emit proper Type0/CID font objects and accurate widths/metrics
    - [x] Replaced placeholder embedded `/Widths` output with parser-driven TTF widths for subset character ranges (using parsed `cmap` + `hmtx`, scaled by `units_per_em`)
    - [x] Replaced static descriptor `/FontBBox` values with parser-driven glyph-bound unions when `loca`/`glyf` metrics are available
    - [x] Replaced static descriptor vertical metrics (`/Ascent`, `/Descent`, `/CapHeight`) with parser-driven values from `OS/2`/`hhea` when available
    - [x] Added descriptor `/Leading` emission from parser-driven `OS/2 sTypoLineGap` with fallback to `hhea lineGap`
    - [x] Added Type0/CID font object emission for embedded TTF unicode text runs (`/Subtype /Type0`, `/Encoding /Identity-H`, `/CIDFontType2` descendant)
    - [x] Added CID width arrays (`/W`) for Type0 descendant fonts using parsed `cmap` + `hmtx` widths and unicode-codepoint fallback
    - [x] Added TTF CIDToGIDMap stream emission for Type0 descendants using parsed `cmap` glyph IDs (with `/CIDToGIDMap /Identity` fallback when `cmap` metadata is unavailable)
    - [x] Added ToUnicode CMap stream generation for Type0 embedded unicode fonts (used-codepoint bfchar mappings)
    - [x] Added surrogate-aware non-BMP handling for Type0 text (`Identity-H` UTF-16 code-unit tracking, ToUnicode mappings, and CID `/W` entries)
    - [x] Added range compaction for large ToUnicode and `/W` maps (`bfrange` grouping + contiguous CID width ranges)
    - [x] Extended unicode Type0/CID emission to embedded OTF fonts (`/Subtype /CIDFontType0` descendant with parser-driven `/W` widths for mapped unicode codepoints)
- [x] Unicode and script shaping
  - [x] Add shaping pipeline (GSUB/GPOS) for ligatures and complex scripts
  - [x] Add opt-in latin ligature shaping baseline (`:latin_ligatures`) across positioned and paragraph fallback rendering
  - [x] Add opt-in GSUB ligature shaping mode (`:gsub_ligatures`) for cross-script ligature replacement while preserving latin script-priority behavior
  - [x] Add opt-in GPOS pair-kerning render mode (`kerning: :gpos`) across positioned and paragraph fallback rendering
  - [x] Add bidi handling baseline for RTL/LTR mixed paragraphs (opt-in visual reordering mode)
  - [x] Add fallback font chaining for missing glyphs (baseline run-splitting API for positioned text)
- [x] Hyphenation and locale hardening
  - [x] Expand `.dic` locale coverage tests and exception parity corpus
  - [x] Support locale-specific left/right hyphen minima and policy controls (option controls implemented)
  - [x] Add regression corpus for mixed-locale paragraphs
- [x] Quality and performance hardening
  - [x] Add visual regression tests against locked PDF fixtures (core/typography/table hash locks landed)
  - [x] Add large-document benchmark suite and memory profiling guardrails (typography + document benchmark baselines + enforce mode landed)
  - [x] Add fuzz tests for malformed font/image/XML inputs (deterministic malformed-input corpus landed)

**Current progress (2026-02-20):**
- Added configurable optimal line-break penalties in `Typography.layout_paragraph/3`:
  - `widow_penalty`
  - `orphan_penalty`
  - `hyphen_penalty`
  - `fitness_class_penalty`
  - `consecutive_hyphen_penalty`
- Added opt-in justification space stretch control:
  - `justify_max_space_multiplier` (caps per-line space expansion instead of forcing full width)
- Added opt-in justification space shrink control:
  - `justify_min_space_multiplier` (allows controlled space compression to fit slightly overfull lines)
- Updated line-fit logic in greedy and optimal modes to honor justification stretch/shrink constraints during break decisions
- Added opt-in optimal cost-model selector:
  - `optimal_cost_model: :quadratic | :box_glue`
  - `:box_glue` uses ratio-based demerits and can reject over-tolerance justified lines during optimal break search
- Migrated optimal line-breaking default to box/glue costing:
  - `line_break: :optimal` now defaults to `optimal_cost_model: :box_glue`
  - `:quadratic` remains available as an explicit opt-in for compatibility/testing
  - Benchmark scenario wiring now pins `:optimal_quadratic` explicitly to avoid drift when defaults change
- Added hyphen minima controls:
  - `Hyphen.hyphenate/3` now accepts `left_min` and `right_min`
  - `LineBreak.break_text/5` supports `hyphen_left_min` and `hyphen_right_min` and forwards these controls
- Added mixed-locale line-break baseline support:
  - `LineBreak.break_text/5` now accepts `locale_resolver` for per-word locale selection
  - Added regression tests for mixed-locale hyphenation behavior
- Added `.dic` locale regression corpus samples:
  - Added fixed split assertions for `:da_dk`, `:fi_fi`, `:nb_no`, and `:sv_se` to catch locale ingest regressions
- Added fixture-driven mixed-locale paragraph corpus:
  - `test/fixtures/hyphen/mixed_locale_corpus.exs` with deterministic locale-resolved break expectations
  - `MixedLocaleCorpusTest` verifies corpus stability across resolver + hyphen minima combinations
- Expanded hyphenation exception parity corpus coverage:
  - Added explicit exception regressions for upstream `:en_gb` exception words (`however`, `manuscript`, `throughout`, `university`, etc.)
  - Added `.dic`-derived `:nb_no` exception regressions (`andror`, `attende`, `bakover`, `bortafor`, etc.)
- Added malformed image input regression coverage:
  - `image_jpeg/6` and `image_png/6` now have tests for unreadable paths and invalid payload bytes
- Added malformed font input regression coverage:
  - `register_ttf_font/3` and `register_otf_font/3` now validate font signatures and reject unreadable/invalid payloads
- Added baseline embedded-font subset controls:
  - `register_ttf_font/4` and `register_otf_font/4` now accept `subset: :none | :ascii_basic | :used_text`
  - Serializer emits subset-style font naming and reduced `FirstChar`/`LastChar` width ranges for opt-in subset modes
- Added baseline TTF font-program glyph subsetting:
  - Serializer now subsets embedded TTF FontFile2 programs by used glyph IDs (from parsed `cmap` + `loca`/`glyf`) for `subset: :ascii_basic | :used_text`
  - TTF subset expansion now follows composite glyph dependencies and preserves required component glyph programs instead of bailing out on composite glyphs
  - Added explicit subset guardrail diagnostics: invalid composite component references now log a warning and force full-font fallback instead of silently failing subset construction
  - Added explicit subset guardrail diagnostics: malformed composite component records now log a warning and force full-font fallback instead of silently failing subset construction
  - Subsetting rewrites `glyf` + `loca` tables and falls back to full font data when subset construction is invalid/unsafe
  - SFNT rebuild now emits 4-byte table-aligned offsets and populated header search fields (`searchRange`, `entrySelector`, `rangeShift`) for subset streams
  - SFNT rebuild now applies `head.checkSumAdjustment` recalculation against rebuilt subset binaries for checksum-consistent FontFile2 streams
  - Added regression coverage for smaller subsetted FontFile2 stream lengths, `subset: :none` full-stream parity, subset SFNT table-offset alignment, valid `checkSumAdjustment`, and composite dependency preservation
- Added baseline OTF/CFF font-program subsetting:
  - Serializer now subsets embedded OTF FontFile3 CFF streams by shrinking unused CharStrings to minimal `endchar` programs for `subset: :ascii_basic | :used_text`
  - CFF subsetting is guarded to safe layouts (CharStrings at table end, or with only unreferenced trailing bytes beyond CharStrings); unsupported layouts fall back to full-font embedding
  - Added top-dict offset patching for referenced trailing regions (absolute offset operators) so CFF subset shrink can proceed when trailing private data is referenced
  - Extended referenced-tail offset patching into FDArray Font DICTs so nested Private offsets stay valid when CFF tails shift during subset shrink
  - Extended CFF subset DICT scanning to parse real (`30`) and fixed (`255`) numeric operands, preventing false fallback when Top DICT contains `FontMatrix`-style values before `CharStrings`
  - Added regression coverage for reduced OTF FontFile3 stream size and CFF CharStrings shrink behavior on unused glyph IDs, including unreferenced trailing-byte layouts
  - Added regression coverage for referenced trailing private-data layouts (`Top DICT Private` and FDArray Font DICT Private offset updates + marker preservation after subset shrink)
- Added strict TTF table parsing scaffold:
  - Introduced `Tincture.Font.TTF.parse_basic_tables/1` to parse `head`, `maxp`, `hhea`, and `hmtx` with bounds/integrity checks
  - `register_ttf_font/3` now requires successful parser validation and stores parsed `:ttf_metrics` on embedded font state
  - Added regression coverage for valid-signature TTF payloads missing required metric tables
- Extended embedded TTF parser/serializer baseline:
  - Added `cmap` parsing support (format 0/4) in `Tincture.Font.TTF.parse_basic_tables/1` with extracted `cmap_by_code` mappings
  - Serializer now emits TTF metric-based `/Widths` values for embedded subset ranges instead of static defaults when parser metrics are present
  - Added parser and integration regressions for mapped codepoint widths (`"AB"` subset range width emission)
  - Extended parser-backed metric extraction to OTTO/sfnt OpenType containers when required tables are present, enabling parser-driven width emission for OTF subset ranges
  - Added `CFF ` family-name fallback parsing via Top DICT `FamilyName` SID + String INDEX resolution when `name` table metadata is absent
  - Added integration regression coverage for OTF descriptor `/FontFamily` emission from CFF fallback metadata when `name` table metadata is unavailable
  - Added `CFF ` full-name fallback parsing via Top DICT `FullName` SID + String INDEX resolution when `FamilyName` and `name` table metadata are absent
  - Added integration regression coverage for OTF descriptor `/FontFamily` emission from CFF FullName fallback metadata when `FamilyName` and `name` table metadata are unavailable
  - Added `CFF ` font-name fallback parsing via Top DICT `FontName` SID + String INDEX resolution when `FamilyName`, `FullName`, and `name` table metadata are absent
  - Added integration regression coverage for OTF descriptor `/FontFamily` emission from CFF FontName fallback metadata when `FamilyName`, `FullName`, and `name` table metadata are unavailable
  - Added `CFF ` weight fallback parsing via Top DICT `Weight` SID + String INDEX resolution when `OS/2` weight metadata is absent
  - Extended CFF weight fallback parsing to accept numeric weight strings (e.g. `650`) as direct `/FontWeight` values when in `1..1000`
  - Extended CFF weight-name normalization to accept separator variants (`Semi-Bold`, `Extra_Bold`, etc.) when mapping fallback names to numeric weight classes
  - Added spec-aligned `CFF ` Private DICT `StdVW` extraction (`operator 11`) and wired descriptor `/StemV` fallback to parser metrics when `OS/2` weight metadata is absent
  - Added `CFF ` Private DICT `StdHW` extraction (`operator 10`) and descriptor `/StemV` fallback to `StdHW` when `StdVW` and `OS/2` weight metadata are unavailable
  - Kept legacy escaped-op fallback (`12 8`) during parser migration for synthetic fixture compatibility
  - Extended descriptor `/StemV` fallback to derive from parsed `CFF Weight` class when both `OS/2 usWeightClass` and `CFF StdVW` are unavailable
  - Added CFF standard SID resolution support for fallback metadata (baseline coverage for family/full/weight style strings)
  - Added integration regression coverage for OTF descriptor `/FontWeight` emission from CFF fallback metadata when `OS/2` weight metadata is unavailable
  - Added `CFF ` Top DICT style fallback parsing (`ItalicAngle`, `isFixedPitch`) for OTF/CFF fonts when `post` table metadata is absent
- Extended GSUB shaping metadata baseline:
  - Added GSUB LookupType 1 (SingleSubst Format 1/2) parsing and codepoint-mapped substitution extraction, wired into existing shaping replacement maps behind feature-linked lookup filtering
  - Added feature-tag expansion for all-script shaping substitutions (`liga`/`rlig`/`ccmp`) and exposed parser metadata map `gsub_substitutions_all`
  - Updated `:gsub_ligatures` replacement selection to prefer `gsub_substitutions_all` and accept fonts exposing `rlig`/`ccmp` features without requiring `liga`
- Extended glyph metric extraction baseline:
  - Added optional `loca`/`glyf` parsing in `Tincture.Font.TTF.parse_basic_tables/1` for glyph offset tables and per-glyph bounding boxes
  - Added `glyf` outline-kind metadata extraction (`glyph_outline_types_by_id`) to distinguish simple vs composite glyph programs
  - Added `glyf` simple-glyph contour-count metadata extraction (`glyph_contour_counts_by_id`) for outline-shape baselines
  - Added `glyf` simple-glyph point-count metadata extraction (`glyph_point_counts_by_id`) from contour endpoint arrays when point records are present
  - Added `glyf` simple-glyph instruction-length metadata extraction (`glyph_simple_instruction_lengths_by_id`) from simple-glyph instruction headers when present
  - Added `glyf` composite instruction-length metadata extraction (`glyph_composite_instruction_lengths_by_id`) from composite instruction records when present
  - Added `glyf` composite component-count metadata extraction (`glyph_component_counts_by_id`) from parsed component records
  - Added `glyf` composite component-glyph ID metadata extraction (`glyph_component_glyph_ids_by_id`) from parsed component records
  - Added baseline `CFF ` Top DICT `FontBBox` parsing for OTF/CFF fonts without `loca`/`glyf` tables
  - Added baseline `CFF ` CharStrings INDEX parsing for OTF/CFF fonts without `loca`/`glyf` tables, exposing `cff_charstring_count` and `cff_charstring_lengths_by_id` outline metadata
  - Added CFF DICT real-number (`30`) decoding support so `FontBBox` extraction handles non-integer Top DICT operands
  - Added parser-derived font bounding box unions (`font_bbox`) and wired serializer descriptor `/FontBBox` emission to these metrics when available
  - Added parser and integration regressions for glyph offset extraction and descriptor bounding-box serialization
- Extended head-bbox fallback metrics baseline:
  - Added parser extraction for `head` table bounding box values (`xMin`, `yMin`, `xMax`, `yMax`) as `head_bbox`
  - Serializer now falls back to parser-derived `head_bbox` for descriptor `/FontBBox` when `loca`/`glyf`-derived unions are unavailable
  - Added parser and integration regressions for head-table bbox extraction and descriptor fallback emission
- Extended vertical font metrics baseline:
  - Added parser extraction for `hhea` ascender/descender and optional `OS/2` typo ascender/descender + cap height in `Tincture.Font.TTF.parse_basic_tables/1`
  - Serializer now emits descriptor `/Ascent`, `/Descent`, `/XHeight`, and `/CapHeight` from parsed metrics (with existing fallbacks when absent)
  - Added parser extraction for `hhea`/`OS/2` line-gap metrics and serializer descriptor `/Leading` emission (`OS/2 sTypoLineGap` fallback to `hhea lineGap`)
  - Added fallback to `OS/2` win ascent/descent for descriptor `/Ascent` and `/Descent` when typo/hhea values are zero or unavailable
  - Added parser and integration regressions for vertical metric extraction and descriptor emission
- Extended descriptor stem metrics baseline:
  - Added parser extraction for `OS/2` `usWeightClass` (`os2_weight_class`)
  - Serializer now emits parser-informed `/StemV` (`round(usWeightClass / 5)`) when available, with existing fallback otherwise
  - Serializer now emits descriptor `/StemH` (preferring parsed `CFF StdHW`, otherwise mirroring the resolved `/StemV` fallback)
  - Added parser and integration regressions for weight-class extraction and `/StemV` descriptor emission
  - Serializer now emits descriptor `/FontWeight` from parsed `OS/2 usWeightClass` when available
- Extended descriptor stretch metrics baseline:
  - Added parser extraction for `OS/2` `usWidthClass` (`os2_width_class`)
  - Serializer now emits descriptor `/FontStretch` using PDF stretch names (`Condensed`, `Expanded`, etc.) mapped from parsed width classes
  - Added parser and integration regressions for width-class extraction and `/FontStretch` descriptor emission
- Extended descriptor width metrics baseline:
  - Added parser extraction for `OS/2` `xAvgCharWidth` (`os2_avg_char_width`)
  - Serializer now emits descriptor `/AvgWidth` from parsed average width (scaled to PDF 1000-unit space)
  - Added parser and integration regressions for `xAvgCharWidth` extraction and `/AvgWidth` descriptor emission
  - Added parser extraction for `hmtx` max advance width (`max_advance_width`)
  - Serializer now emits descriptor `/MaxWidth` from parsed max advance width (scaled to PDF 1000-unit space)
  - Added parser and integration regressions for `hmtx` max-width extraction and `/MaxWidth` descriptor emission
  - Added parser extraction for `hhea` `advanceWidthMax` (`hhea_advance_width_max`)
  - Serializer now prefers `/MaxWidth` from parsed `hhea advanceWidthMax` when non-zero, with `hmtx` max-width fallback
  - Added parser and integration regressions for `hhea advanceWidthMax` extraction and `/MaxWidth` preference behavior
  - Added parser extraction for `OS/2` `usFirstCharIndex`/`usLastCharIndex` (`os2_first_char_index`/`os2_last_char_index`)
  - Serializer now uses parsed non-subset char ranges for `/FirstChar` and `/LastChar` when values are sane WinAnsi codepoints
  - Added parser and integration regressions for OS/2 char-range extraction and embedded-font range emission
  - Serializer now emits descriptor `/MissingWidth` from parsed glyph-0 advance width (scaled to PDF 1000-unit space)
  - Added integration regression coverage for `/MissingWidth` descriptor emission
  - Added parser extraction for `OS/2` `usDefaultChar` (`os2_default_char`)
  - Serializer now prefers `/MissingWidth` from the parsed default-char glyph width when `cmap` mappings are available, with glyph-0 fallback
  - Added parser and integration regressions for `usDefaultChar` extraction and `/MissingWidth` preference behavior
  - Added parser extraction for `OS/2` `usBreakChar` (`os2_break_char`)
  - Serializer now falls back `/MissingWidth` to parsed break-char glyph width when default-char mapping is unavailable, with glyph-0 fallback
  - Added parser and integration regressions for `usBreakChar` extraction and `/MissingWidth` fallback behavior
- Extended shaping-policy metadata baseline:
  - Added parser extraction for `OS/2` `usMaxContext` (`os2_max_context`)
  - Latin ligature shaping now respects parsed max-context limits per embedded fallback font
  - Added parser and fallback-shaping regressions for `usMaxContext` extraction and shaping-limit behavior
- Extended descriptor embedding-policy metrics baseline:
  - Added parser extraction for `OS/2` `fsType` (`os2_fs_type`)
  - Serializer now emits descriptor `/FSType` when parsed embedding metadata is available
  - Added parser and integration regressions for `fsType` extraction and `/FSType` descriptor emission
  - Added opt-in registration enforcement (`enforce_embedding_permissions: true`) to reject restricted-license, bitmap-only, and no-subsetting `OS/2 fsType` combinations
  - Added default warning logs for restrictive `OS/2 fsType` combinations when enforcement is disabled, with guidance to enable `enforce_embedding_permissions: true`
  - Added OTF parity regressions for enforcement/warning behavior (`register_otf_font/4`) on restrictive, no-subsetting, and bitmap-only `OS/2 fsType` values
  - Added combined-flag diagnostics for `OS/2 fsType` policy checks so enforcement/warning paths report multiple active restrictions together (e.g. bitmap-only + no-subsetting)
  - Added OTF combined-flag parity regressions (`OS/2 fsType = 768`) to validate multi-restriction diagnostics in both enforcement and warning paths
- Extended descriptor family metadata baseline:
  - Added parser extraction for `name` table family records (`nameID=1`) with unicode decoding priority for Windows Unicode entries
  - Serializer now emits descriptor `/FontFamily` when parser-provided family metadata is available
  - Added parser and integration regressions for family-name extraction and descriptor emission
- Extended descriptor style dictionary baseline:
  - Added parser extraction for `OS/2` Panose bytes (`os2_panose`)
  - Serializer now emits descriptor `/Style << /Panose <...> >>` when parsed Panose metadata is available
  - Added parser and integration regressions for Panose extraction and style-dictionary emission
- Extended OS/2 script/decoration metadata baseline:
  - Added parser extraction for `OS/2` subscript/superscript metrics (`ySubscriptXSize`, `ySubscriptYSize`, `ySubscriptXOffset`, `ySubscriptYOffset`, `ySuperscriptXSize`, `ySuperscriptYSize`, `ySuperscriptXOffset`, `ySuperscriptYOffset`)
  - Added parser extraction for `OS/2` strikeout metrics (`yStrikeoutSize`, `yStrikeoutPosition`)
  - Added parser regression coverage for signed-value extraction across these fields
- Extended embedded font style metrics baseline:
  - Added parser extraction for italic style metadata from `head` (`macStyle`) and `post` (`italicAngle`) tables
  - Serializer now emits parser-backed descriptor `/ItalicAngle` and sets italic descriptor flag bit (`/Flags 96`) when applicable
  - Added parser and integration regressions for italic metric extraction and descriptor emission
- Extended fixed-pitch descriptor metrics baseline:
  - Added parser extraction for `post` `isFixedPitch` as `fixed_pitch`
  - Serializer now sets descriptor fixed-pitch flag bit (`/Flags` bit 1) when parser metrics indicate monospaced fonts
  - Added parser and integration regressions for fixed-pitch extraction and descriptor flag emission
- Extended force-bold descriptor metrics baseline:
  - Added parser extraction for `head` macStyle bold bit (`bold`)
  - Serializer now sets descriptor force-bold flag bit (`/Flags` bit 19) when bold metadata is present (`head` bit or heavyweight `OS/2 usWeightClass`)
  - Added parser and integration regressions for bold extraction and force-bold flag emission
  - Added parser extraction for `OS/2` fsSelection style bits (`italic`/`bold`/`oblique`) and integrated them into `bold`/`italic` style resolution when head/post metadata is absent
- Extended unicode font object baseline:
  - Serializer now emits embedded Type0/CID font objects for unicode text runs with TTF fonts (`Identity-H` + `CIDFontType2`)
  - Content stream encoding now supports Identity-H hex strings without BOM for those Type0 runs
  - Added integration coverage for Type0/CID object emission and unicode text encoding serialization
  - Extended Type0 selection to subset modes (`subset: :ascii_basic | :used_text`) for unicode text runs, avoiding WinAnsi fallback behavior in those cases
  - Extended Type0 selection to embedded OTF unicode text runs, emitting `CIDFontType0` descendants and parser-driven CID width arrays for mapped unicode codepoints
  - Added OTF unicode subset parity coverage (`subset: :used_text`) for Type0/CID emission with `/CIDSet` + `/ToUnicode` checks
- Extended Type0 text extraction baseline:
  - Added `/ToUnicode` CMap stream emission for Type0 embedded fonts with used-codepoint bfchar mappings
  - Added integration coverage validating `/ToUnicode` presence and representative unicode mappings (including `U+2603`)
- Extended Type0 width metrics baseline:
  - Added `/W` CID width array emission for Type0 descendant fonts driven by used unicode codepoints
  - Width entries now use parsed TTF `cmap` and `hmtx` metrics when available, with fallback width defaults for unmapped codepoints
  - Added format-14 non-default UVS width overrides so variation-selector sequences (for example `U+2603 U+FE0F`) emit selector-aware base CID widths and zero-width selector CIDs
  - Added zero-width handling for unmapped zero-advance unicode codepoints in Type0 `/W` emission (ZWJ/ZWNJ/word-joiner and combining-mark ranges), preventing glyph-0 fallback widths from inflating cursor metrics
  - Added parser-backed CID default-width emission (`/DW`) from glyph-0 advance width when available
  - Added stream-backed `/CIDToGIDMap` emission for Type0 CIDFontType2 descendants using parsed `cmap` glyph IDs, with `/Identity` fallback when `cmap` mappings are unavailable
  - Added format-14 non-default UVS CIDToGID overrides so variation-selector sequences map base CIDs to selector-specific glyph IDs while selector CIDs map to zero
  - Added explicit CIDToGID regressions for unmapped zero-advance codepoints (ZWJ and combining marks), asserting stream maps those CIDs to glyph `0` while retaining non-Identity CIDToGIDMap emission
  - Added `/FlateDecode` compression for CIDToGIDMap streams to reduce embedded Type0 font object size on high-CID unicode runs (for example non-BMP surrogate CIDs)
  - Added integration coverage for CID width-array serialization on mixed ASCII/unicode runs
- Extended Type0 subset descriptor baseline:
  - Added `/CIDSet` stream emission for Type0 subset fonts (`subset: :ascii_basic | :used_text`) and descriptor `/CIDSet` references
  - Added integration coverage for subset-unicode Type0 serialization including CIDSet presence
- Extended non-BMP unicode baseline:
  - Added surrogate-pair aware Type0 handling by tracking used UTF-16 code units for CID widths (`/W`)
  - Added non-BMP-aware CIDToGIDMap surrogate mapping for Type0 CIDFontType2 descendants (map high-surrogate CID to the format-12 glyph ID and low-surrogate CID to zero for each used non-BMP scalar)
  - Added ambiguity guard for CIDToGIDMap surrogate mapping: when multiple non-BMP scalars in the same high-surrogate bucket require different glyph IDs, fallback to `/CIDToGIDMap /Identity` instead of emitting an invalid conflicting map
  - Added ambiguity guard for `/W` surrogate-width overrides: when multiple non-BMP scalars in the same high-surrogate bucket resolve to different glyph widths, fallback to baseline CID width emission (no surrogate override) instead of using order-dependent overrides
  - Added serializer warning logs when non-BMP surrogate ambiguity triggers Type0 fallbacks (`/CIDToGIDMap /Identity` and baseline `/W` emission) so degraded mapping behavior is visible at export time
  - Added ToUnicode mappings that support both 2-byte (BMP) and 4-byte (non-BMP surrogate-pair) source codes with matching code-space ranges
  - Added integration coverage for emoji/non-BMP serialization (`U+1F600`) across content stream encoding, ToUnicode mapping, and CID widths
  - Added OTF format-12 non-BMP regression coverage for `CIDFontType0` descendants (`U+1F600` ToUnicode + surrogate CID width entries)
- Extended Type0 map compaction baseline:
  - Added ToUnicode compaction to emit `bfrange` entries for contiguous source/destination sequences with `bfchar` fallback for sparse mappings
  - Added CID `/W` compaction to emit contiguous same-width ranges (`start end width`) while preserving per-CID entries for mixed widths
  - Added integration coverage for compact ToUnicode (`ABC` range) and compact CID width arrays (`☃☄★` range)
- Extended cmap format-4 unicode coverage baseline:
  - Updated TTF format-4 cmap parsing to build mappings from declared segments (instead of a `0..255` scan), preserving unicode mappings such as `U+2603`
  - Added parser regression coverage for format-4 mappings beyond Latin-1
  - Added integration coverage proving Type0 CID width emission uses parsed format-4 mappings for unicode symbols
- Extended cmap format-2 unicode coverage baseline:
  - Added TTF cmap format-2 parser support for high-byte mappings (`subHeaderKeys` + subheader expansion)
  - Added parser regression coverage for format-2 codepoint→glyph extraction
  - Added integration coverage proving Type0 CID width emission uses parsed format-2 mappings for unicode symbols
- Extended cmap format-6 unicode coverage baseline:
  - Added TTF cmap format-6 parser support for trimmed-table mappings (`firstCode` + `entryCount` glyph arrays)
  - Added parser regression coverage for format-6 codepoint→glyph extraction
  - Added integration coverage proving Type0 CID width emission uses parsed format-6 mappings for unicode symbols
- Extended cmap format-8 unicode coverage baseline:
  - Added TTF cmap format-8 parser support for group-based mappings (`is32` bitmap + sequential groups)
  - Added parser regression coverage for format-8 codepoint→glyph extraction
  - Added integration coverage proving Type0 CID width emission uses parsed format-8 mappings for unicode symbols
- Extended cmap format-10 unicode coverage baseline:
  - Added TTF cmap format-10 parser support for trimmed 32-bit mappings (`startCharCode` + `numChars` glyph arrays)
  - Added parser regression coverage for format-10 codepoint→glyph extraction
  - Added integration coverage proving Type0 CID width emission uses parsed format-10 mappings for unicode symbols
- Extended cmap format-12 non-BMP baseline:
  - Added TTF cmap format-12 parser support with segment-group expansion for non-BMP codepoint mappings
  - Updated cmap subtable preference to favor Windows Unicode full-repertoire mappings (`platform 3 / encoding 10`) when present
  - Added parser regression coverage for emoji/non-BMP format-12 mappings
- Extended cmap format-13 unicode coverage baseline:
  - Added TTF cmap format-13 parser support for many-to-one group mappings (`startCharCode`..`endCharCode` -> shared glyph ID)
  - Added parser regression coverage for format-13 codepoint→glyph extraction
  - Added integration coverage proving Type0 CID width emission uses parsed format-13 mappings for unicode symbols
- Extended cmap format-14 unicode-variation baseline:
  - Added TTF cmap format-14 parser support for variation-selector metadata (`varSelector` records + non-default UVS mappings)
  - Added parser regression coverage for format-14 selector extraction and non-default UVS mapping decode
  - Added registration-path regression coverage proving parsed format-14 selector metadata is attached to embedded font metrics
- Extended format-12-driven Type0 width behavior:
  - Added scalar-codepoint tracking per embedded Type0 font so non-BMP codepoints can participate in metric lookup
  - Type0 CID width emission now applies format-12 mapped glyph widths to surrogate CID pairs (`high-surrogate = glyph width`, `low-surrogate = 0`) when mappings are available
  - Added integration coverage verifying non-BMP width emission uses parsed format-12 mappings instead of fallback widths
- Added baseline fallback font chaining for positioned text:
  - Added `Tincture.text_at_with_fallback/5` to split text into contiguous runs by first supporting font (`current_font` + ordered fallback font list)
  - Added embedded-font glyph support checks driven by parsed TTF `cmap` mappings and run-position advancement from per-font metrics
  - Added integration regressions for mixed-glyph run splitting (`A☃B`) and single-run preservation when primary font fully covers text
  - Added grapheme-aware fallback run splitting so variation-selector clusters (for example `☃️`) stay in a single run instead of splitting selector codepoints into adjacent font runs
  - Added variation-sequence font preference in fallback selection: when a later fallback font has a format-14 non-default UVS mapping, it is selected ahead of an earlier base-only font for that grapheme
  - Added variation-aware embedded fallback width advancement: format-14 non-default UVS glyph widths are used for base codepoints and variation-selector codepoints are treated as zero-width for cursor advancement and kerning-pair input
  - Added zero-width handling for unmapped zero-advance unicode codepoints (ZWJ/ZWNJ/word-joiner and combining-mark ranges) in embedded fallback width advancement, preventing glyph-0 fallback widths from over-advancing mixed-script runs
  - Updated grapheme fallback support checks to treat zero-advance controls as ignorable for font coverage decisions, so ZWJ sequences can still route to fallback fonts that cover base glyphs
  - Consolidated zero-advance unicode classification into shared `Tincture.Unicode` helpers and reused the same predicates across fallback rendering and serializer Type0 width logic
  - Extended zero-advance combining-mark detection beyond fixed ranges by adding Unicode mark-category fallback matching (`\\p{M}`), covering script-specific marks (for example Hebrew niqqud, Arabic harakat, and Indic signs)
  - Extended standard/AFM `Font.text_width/3` handling to skip unmapped zero-advance codepoints while preserving kerning context, preventing built-in/AFM fallback runs from over-advancing on sequences like `A‍B` and `ÁB`
  - Added font-metric regressions for zero-advance handling in standard and AFM width paths
  - Added script-specific combining-mark regressions across helper classification, Type0 `/W` width emission, and fallback cursor advancement (`U+05B0`)
  - Added integration regressions for variation-sequence fallback behavior (`A☃️B` run splitting/advance positions and format-14 mapping preference over base-only coverage)
  - Added integration regressions for zero-advance behavior across fallback and Type0 widths (`A‍B☃`, `ÁB☃`, and Type0 `/W` entries for U+200D/U+0301)
  - Preserved caller font state for fallback drawing APIs (`text_at_with_fallback` and `text_at_rotated_with_fallback`) so segmented fallback rendering no longer leaves `current_font` set to the last fallback segment font
  - Added fallback API regressions that assert font-state preservation for plain fallback runs, rotated fallback runs, and shaping-driven fallback substitutions
  - Extended paragraph/rotated text rendering with fallback chaining:
    - Added `fallback_fonts:` option support in `text_paragraph/6`
    - Added `Tincture.text_at_rotated_with_fallback/6` for rotated fallback run splitting
    - Added regression coverage for paragraph-level mixed-glyph fallback splitting
    - Switched paragraph cursor advancement to use measured rendered fallback width (instead of layout token `word.width`) so subsequent words line up with actual fallback/shaping output
    - Added rotated-mode parity for measured rendered fallback width advancement in paragraph rendering
    - Added paragraph regressions for rendered-width advancement (`A☃B C`) and variation-selector run preservation (`A☃️B`)
  - Added unicode-range-aware fallback heuristic for embedded fonts lacking cmap mappings:
    - Added parser extraction for `OS/2` unicode ranges (`ulUnicodeRange1..4`) as `os2_unicode_ranges`
    - Fallback glyph-support checks now use parsed unicode ranges (Basic Latin, Latin-1, Latin Extended, Greek, Cyrillic, Armenian, Hebrew, Arabic, Devanagari, and Thai baseline coverage) when cmap data is unavailable
    - Preserved permissive WinAnsi fallback behavior when unicode ranges are present but all-zero/unknown
    - Added parser extraction for `OS/2` code-page ranges (`ulCodePageRange1..2`) as `os2_code_page_ranges`
    - Fallback glyph-support checks now use parsed code-page ranges when unicode ranges are unavailable/unknown (baseline ASCII, Latin-1, Latin-2, Greek, Cyrillic, Turkish/Baltic/Vietnamese-specific Latin-Extended letters, Hebrew, Arabic, and Thai handling)
    - Added parser and integration regressions for unicode-range extraction and fallback run selection behavior
- Added opt-in bidi visual baseline for paragraph rendering:
  - Added `bidi: :off | :basic` option to `text_paragraph/6` (default `:off`)
  - `:basic` applies conservative visual reordering for mixed LTR/RTL token runs and reverses RTL word grapheme order for render-time output
  - Added regressions for mixed Latin/Hebrew paragraph rendering and invalid bidi-option validation
- Added opt-in latin ligature shaping baseline:
  - Added `shaping: :off | :latin_ligatures` to fallback text APIs (`text_at_with_fallback`, `text_at_rotated_with_fallback`) and `text_paragraph/6`
  - Added fallback-aware replacement for `ffl`, `ffi`, `ff`, `fi`, and `fl` ligatures when target glyphs are available in selected fonts
  - Added `OS/2 usMaxContext` enforcement for embedded fallback fonts so ligature replacements honor font-provided context limits
  - Added GSUB-aware ligature gating so embedded fonts with explicit GSUB feature metadata only apply latin ligature substitutions when `liga` is present
  - Added GSUB script-aware ligature gating so embedded fonts with explicit GSUB script metadata only apply latin ligature substitutions when `latn` is present
  - Added GSUB lookup-defined ligature substitution support so fonts can provide non-hardcoded latin ligature mappings (e.g. `st -> ﬆ`)
  - Added parser coverage for GSUB ligature lookup extraction and integration coverage for fallback rendering with GSUB-defined substitutions
  - Added parser coverage for GPOS pair-kerning extraction and applied parsed pair kerning to embedded fallback segment width advancement
  - Extended GPOS pair-kerning parsing to include PairPos Format 2 class-based subtables (ClassDef format 1/2), with parser and fallback-render regressions for class-driven `AV`/`AX` kerning
  - Extended GPOS pair-kerning adjustments to include ValueRecord2 `xAdvance` contributions (Format 1 and class-based Format 2), with parser + fallback cursor-advance regressions
  - Added GPOS class-pair parsing guardrail to skip oversized class matrices (`class1_count * class2_count` cap) and added parser/integration regressions for large-but-valid tables that now safely fall back without kerning
  - Added warning diagnostics when oversized GPOS class-pair matrices are skipped, with parser-level and `register_ttf_font/3` integration log regressions to keep guardrail behavior visible
  - Added parser metadata reporting for guardrail events (`ttf_metrics.gpos_guardrail_skips`) and regression coverage for normal (`0`) vs oversized-table (`1`) GPOS class-pair parse paths
  - Added GPOS PairPos Format-1 pair-set guardrail to skip oversized `pairValueCount` payloads, with parser + embedded-fallback regressions for kerning fallback behavior and warning visibility (`pair_value_count` diagnostics)
  - Added GPOS PairPos Format-1 subtable guardrail for malformed coverage/pair-set cardinality mismatches (`coverage_glyph_count != pair_set_count`), with parser + embedded-fallback regressions and warning diagnostics
  - Hardened GPOS PairPos Format-1 parsing to fail closed on truncated `PairValueRecord` payloads (drop partial pair maps instead of returning partial kerning), with parser + embedded-fallback regressions
  - Added GPOS ClassDef guardrail to skip oversized class-definition expansions (Format 1/2 entry caps) before class-pair expansion, with parser + embedded-fallback regressions and warning diagnostics (`entries` overflow visibility)
  - Added GPOS PairPos Format-2 class-count guardrail to skip malformed class-pair subtables when `class1_count` or `class2_count` is zero, with parser + embedded-fallback regressions and warning diagnostics
  - Added GPOS PairPos Format-2 malformed-record guardrail to skip subtables with truncated class-adjustment record payloads (fail-closed `class_adjustments` parse), with parser + embedded-fallback regressions and warning diagnostics
  - Added GPOS PairPos Format-2 malformed-class-definition guardrail to skip subtables with invalid ClassDef offsets/payloads (fail-closed class-definition parse), with parser + embedded-fallback regressions and warning diagnostics
  - Added GPOS class-pair expansion guardrail to skip oversized codepoint-mapped expansion sets (`estimated_pairs` cap) so dense class ranges cannot explode pair-map output, with parser + embedded-fallback regressions and warning diagnostics
  - Updated embedded fallback GPOS kerning context to ignore zero-advance codepoints (for example combining marks) while preserving width accounting, so base-letter kerning still applies across sequences like `ÁV`
  - Added feature-link filtering so GSUB/GPOS application only uses lookups actually referenced by active `liga`/`kern` features (avoids applying unrelated lookups)
  - Added parser and integration regressions for tables where `liga`/`kern` tags exist but do not link target lookups
  - Added default-vs-named LangSys prioritization for GSUB/GPOS lookup selection, with regressions validating default LangSys precedence
  - Added script-level lookup prioritization (`latn` -> `DFLT` -> fallback scripts) so latin shaping does not consume unrelated script lookups when multiple scripts are present
  - Added regressions for positioned and paragraph fallback shaping paths and invalid shaping-option validation
  - Added opt-in fallback kerning mode (`kerning: :gpos`) that applies parsed GPOS pair adjustments to per-grapheme positioned draws, with invalid-option validation for positioned and paragraph APIs
  - Added regression coverage for opt-in fallback kerning mode across rotated and paragraph rendering paths (including non-Latin fallback glyph pairs)
  - Added invalid-option regression coverage for rotated fallback rendering (`text_at_rotated_with_fallback/7` rejects unsupported `kerning` modes)
  - Added shaping+kerning interaction regression coverage so `shaping: :gsub_ligatures` and `kerning: :gpos` apply in sequence on fallback runs (GSUB substitution followed by GPOS pair adjustment)
  - Expanded shaping+kerning interaction regression coverage to rotated and paragraph fallback rendering paths
  - Added `:gsub_ligatures` shaping mode for fallback text APIs and `text_paragraph/6`, enabling GSUB `liga` substitutions across non-latin scripts
  - Extended TTF GSUB parsing with dual ligature maps: script-prioritized (`gsub_ligatures`) and all-scripts (`gsub_ligatures_all`) to preserve `:latin_ligatures` behavior while enabling cross-script GSUB shaping
  - Added parser and integration regressions for arab-script-only GSUB liga fixtures across positioned, rotated, and paragraph fallback rendering
- Added malformed XML regression coverage:
  - `Template.parse_xml/1` and `Template.render_xml_document/3` now have explicit tests for malformed XML, missing body nodes, and invalid body size attributes
- Added deterministic malformed-input fuzz corpus coverage:
  - Added `test/tincture/fuzz/malformed_input_fuzz_test.exs` with generated malformed payload corpora for TTF/OTF registration, JPEG/PNG embedding, and XML parse/render entry points
  - Coverage asserts stable error behavior across multiple payload variants while preventing parser-crash regressions
- Added benchmark baseline for typography cost models/options:
  - `Tincture.Benchmark.Typography.run/1` with scenario metrics for greedy, quadratic-optimal, and box-glue-optimal modes
  - `scripts/benchmark_typography.exs` for repeatable local performance checks via env-configured iteration counts
  - Added `run/1` custom-scenario support (`scenarios: [{name, fun}]`) and validation for focused benchmark slices and deterministic benchmark tests
  - Added non-failing guardrail warnings (`guardrail_warnings/2`) for scenario runtime thresholds
- Added benchmark baseline for large-document and memory profiling checks:
  - `Tincture.Benchmark.Document.run/1` with paragraph-flow, table-heavy, and template-paginated scenarios
  - Includes `memory_bytes_delta` metrics per scenario and a runnable script at `scripts/benchmark_document.exs`
  - Added `gpos_guardrail_skips` reporting in document benchmark metrics/output and guardrail checks (`max_gpos_guardrail_skips`) so parser fallback activity is visible in benchmark runs
  - Updated benchmark scenario execution to derive `gpos_guardrail_skips` from returned PDF embedded-font metrics (instead of static `0`) and added `run/1` custom-scenario support for focused benchmark coverage/tests
  - Added non-failing guardrail warnings for runtime and memory thresholds with env-based scaling factors
- Added strict benchmark guardrail enforcement mode:
  - Added `assert_guardrails!/2` to `Tincture.Benchmark.Typography` and `Tincture.Benchmark.Document` to raise on threshold violations
  - Updated `scripts/benchmark_typography.exs` (`EX_GUTEN_BENCH_ENFORCE=1`) and `scripts/benchmark_document.exs` (`EX_GUTEN_DOC_BENCH_ENFORCE=1`) to support fail-fast guardrail checks for CI gating
- Added locked PDF fixture baseline checks:
  - Added SHA-256 lock tests for representative core and optimal-typography PDF outputs
  - Fixture hashes stored under `test/fixtures/pdf/*.sha256` and verified in CI via ExUnit
- Expanded locked PDF fixture coverage:
  - Added a deterministic table-layout fixture lock (`test/fixtures/pdf/table_layout.sha256`) and regression test coverage in `PDFFixtureLockTest`
  - Added fixture lock maintenance script (`scripts/refresh_pdf_fixture_locks.exs`) with check mode (`EX_GUTEN_FIXTURE_LOCK_CHECK=1`) for reproducible lock refresh/verification workflows
- Added regression coverage for widow control in optimal mode (`"aa bb cc dd"` case)
- Added regression coverage for fitness-class smoothing and consecutive hyphen-ending control
- Added option validation coverage for negative penalty rejection, including new penalty fields
- Optimized optimal line-breaking hot paths in `Typography.layout_paragraph/3`:
  - Replaced repeated per-candidate token slicing/scanning with precomputed range indexes and prefix stats (width, space count/width, non-space count, hyphen endings)
  - Reworked DP candidate evaluation to compute feasible line candidates once per start index and reuse them across fitness/hyphen state transitions
  - Added benchmark regression coverage to cap optimal-mode slowdown relative to greedy baseline
- Rebaselined typography guardrails after optimization:
  - Updated default typography guardrails to reflect post-feature baselines while preserving regression detection (`optimal_quadratic: 24_000`, `optimal_box_glue: 24_000`, `optimal_box_glue_penalties: 24_000`)
  - Verified `Tincture.Benchmark.Typography` passes guardrails at `iterations=30`, `warmup=5`
  - Verified `Tincture.Benchmark.Document` guardrails still pass at `iterations=30`, `warmup=5`

**Execution strategy:**
- [x] Run each sub-track behind opt-in options first, then make defaults once parity + performance gates pass
- [x] Land work as vertical slices (test fixture → serializer/layout changes → benchmark) rather than large rewrites

**Deliverable:** Publish v1.1.x+ with production-grade typography and font stack

---

### Phase 7: Productization and Adoption (Post-v1.1)

**Goal:** Close ecosystem and operational gaps beyond feature parity

- [ ] Reader interoperability matrix
  - Validate representative fixtures in Acrobat, macOS Preview, Chrome, and Firefox PDF engines
  - Add CI smoke checks for text extraction (`pdftotext`) and structure checks (`qpdf --check`)
- [ ] Public “showcase” fixture suite
  - Maintain complex real-world samples (invoice, statement, multi-page report) with lock hashes
  - Include render scripts so examples can be regenerated outside tests
  - Progress: added invoice and statement showcase slices with end-to-end tests, lock hashes, reusable builders, and render scripts, including a second statement variant (`test/invoice_showcase_test.exs`, `test/bank_statement_showcase_test.exs`, `test/fixtures/pdf/invoice_showcase.sha256`, `test/fixtures/pdf/bank_statement_showcase.sha256`, `test/fixtures/pdf/bank_statement_joint_fee_interest_showcase.sha256`, `scripts/render_invoice_showcase.exs`, `scripts/render_bank_statement_showcase.exs`)
- [ ] API stability and upgrade discipline
  - Add API contract tests for top-level `Tincture` functions to catch accidental breaking changes
  - Add release checklist for semver/changelog/deprecation notes
- [ ] Performance SLOs in CI
  - Add explicit benchmark budget checks in CI for typography + large-document scenarios
  - Track trend deltas between commits for early regression detection
- [ ] Docs and developer onboarding
  - Publish end-to-end cookbook examples (invoice/report/template + fonts/images/unicode)
  - Add troubleshooting guide for common PDF/font embedding issues

**Deliverable:** v1.2.x with operational readiness and external adoption support

---

### Porting Strategy Notes

**1. Replace gen_server with structs**
The biggest architectural change. erlguten's `eg_pdf` is a `gen_server` — you call `eg_pdf:new()` which spawns a process, then pass the PID everywhere. In Tincture, use an immutable struct:

```erlang
%% erlguten
PDF = eg_pdf:new(),
eg_pdf:set_pagesize(PDF, a4),
eg_pdf:set_font(PDF, "Helvetica", 14),
eg_pdf_lib:moveAndShow(PDF, 50, 700, "Hello"),
Serialised = eg_pdf:export(PDF),
eg_pdf:delete(PDF).
```

```elixir
# tincture
pdf = Tincture.new()
|> Tincture.page_size(:a4)
|> Tincture.set_font("Helvetica", 14)
|> Tincture.text_at(50, 700, "Hello")
|> Tincture.export()
```

**2. Start with a mechanical first pass**
Much of the Erlang → Elixir translation is straightforward syntax changes. Do a fast first pass for each module, then manually review and make it idiomatic.

**3. Test parity**
erlguten has ~12 test modules that each produce PDF output. Port each test as you port the corresponding module. Visual comparison of output PDFs is the best verification.

**4. Data files are free**
The `priv/` directory (AFM font metrics, TeX hyphenation patterns) can be copied directly — no porting needed. This is ~16% of the codebase for free.

**5. Publish early**
Don't wait for feature-complete. A v0.1.0 that can generate basic PDFs is already useful and gets you visibility on Hex.pm.

---

### Comparable Elixir Libraries

Know the landscape before you build:

| Library | Approach | Limitations |
|---|---|---|
| `pdf` (hex) | Wrapper around `erlang-pdf` | Minimal features, unmaintained |
| `gutenex` | Elixir PDF writer | Abandoned since 2016 |
| `chromic_pdf` | Chrome headless → PDF | External dependency, no typesetting |
| `pdf_generator` | wkhtmltopdf wrapper | External binary required |
| **tincture** | Native Elixir PDF + typesetting | **No external dependencies** |

Tincture's niche: **native Elixir, no external tools, real typesetting.** This is the pitch.
