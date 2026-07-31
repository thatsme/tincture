# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-07-31

### Added

- **Transparency and shading.** `Tincture.set_alpha/2` sets constant alpha for
  fill and stroke; `Tincture.linear_gradient/7` and
  `Tincture.radial_gradient/7` fill a rectangle with an axial or radial
  gradient. Two stops interpolate directly, more are stitched, so a multi-stop
  gradient costs nothing extra to ask for.

  Until now the drawing API could not vary a colour across a region or draw
  anything at less than full opacity — PNG alpha arrived through `/SMask` on an
  image, and nothing else. A design-led document, which is to say a cover or a
  marketing page, wanted both.

  A gradient is paint rather than a shape: it ignores the current fill colour,
  and it clips to its own rectangle and restores the graphics state, so it
  cannot leave a clip behind. Alpha *is* state and applies until restored,
  which is the one thing worth remembering about it.

  Both `/ExtGState` and `/Shading` are written inline into the page's resource
  dictionary. Neither carries a stream, so neither needs an object number, and
  not allocating one means a document that uses no gradient is byte-for-byte
  what it was before — every existing fixture lock still passes untouched.

  See [`examples/gradient.exs`](examples/gradient.exs).

### Fixed

- **Standard font metrics parsed to nothing on a CRLF checkout.** The base-14
  width and kerning tables are read out of `priv/standard_fonts/eg_font_*.erl`
  with regexes anchored `;$` under `/m`, and Erlang's `:re` treats LF alone as a
  line ending — so a `\r` before every newline matched no width line at all.
  Every one of the fourteen fonts then loaded an empty table, every string
  measured 0.0 wide, and 44 tests failed in justification, line breaking, box
  fitting and the PDF fixture hashes, none of them anywhere near the cause.

  Git for Windows sets `core.autocrlf=true` by default and the repository
  shipped no `.gitattributes`, so this hit any Windows clone. CI runs on Linux
  and never saw it. The published package is unaffected — its tarball carries
  LF — so this cost contributors rather than users.

  Three changes, because one was not enough: `.gitattributes` pins the tree to
  LF so the conversion cannot happen; the regexes accept an optional `\r` so a
  mangled checkout still parses; and an empty width table now raises where it
  previously returned silently, since a shipped metric file always declares
  widths. A parse failure names itself now instead of surfacing as arithmetic.

- **Examples crashed on a machine with no font installed.** `Examples.Fonts`
  returns `{pdf, embedded?}` and resolves a name to a standard font when nothing
  could be embedded, but `invoice.exs` and `form.exs` discarded that flag and
  then drew with `"Body"` — a name the document does not know unless
  registration succeeded. Both raised `unknown font: Body`.

  Not a Windows problem, though that is where it showed: the candidate list held
  only macOS and Linux paths, so Windows always took the no-font branch. A slim
  container takes it too — most base images install no fonts — so this equally
  broke `elixir:*-slim` and minimal CI runners. Windows font candidates are now
  included, derived from `WINDIR` rather than assuming `C:`.

  `archival.exs` failed differently and for a real reason: PDF/A forbids
  unembedded fonts, so with no font available the document breaks the claim it
  carries and `export/2` correctly refuses it. It said it would still produce
  the document, which stopped being true when that enforcement was added. It now
  exports with `enforce: false`, which is what the option is for.

  CI never ran `mix examples`, which is why none of this was caught. It does
  now, both with a font present and with the helper forced to find none.

## [0.1.0] — 2026-07-26

First release under the Tincture name.

Tincture is a fork of [ex_guten](https://github.com/hwatkins/ex_guten) by Hugh
Watkins (MIT), which is itself an Elixir port of Joe Armstrong's Erlang
[erlguten](https://github.com/CarlWright/NGerlguten). Most of the engine — the
TrueType/OpenType parser, the Knuth-Plass line breaker, the TeX hyphenation
port, the PDF object serialiser — is his work, carried forward here. See
[NOTICE](NOTICE) for the full attribution chain.

`0.1.0` rather than a higher number is deliberate. The engine is mature, but
the public API under this name is new and may still move before 1.0.

### Added

- **Tagged PDF, for accessibility.** `Tincture.tag/4` and
  `Tincture.set_language/2` produce logical structure: a `/StructTreeRoot`,
  marked content bracketing the operators that draw each element, a parent tree
  linking the two, `/MarkInfo`, `/Lang`, alternative text, and `/Scope` on table
  header cells. An untagged PDF is a picture of a document — nothing records
  which glyphs are a heading or what order to read them in — so this is the
  layer assistive technology actually reads.

  This produces the structure; it does not *certify* PDF/UA. Conformance is a
  validation exercise against a checker such as veraPDF or PAC, which enforces
  further rules a library cannot check on your behalf.
- **Verified PDF/UA-1 conformance.** `examples/output/accessible.pdf` passes
  veraPDF 1.30.2 against the PDF/UA-1 profile: 106 of 106 rules, 1701 of 1701
  checks. Validating it found three real defects, all fixed below.
- **PDF/A, verified.** `Tincture.set_pdf_a/2` produces archival output:
  `examples/output/archival.pdf` passes veraPDF 1.30.2 at PDF/A-2b, 2u and
  **2a**, and PDF/UA-1 simultaneously. Adds an sRGB output intent, XMP carrying
  the conformance claim, and a file identifier.
- **`Tincture.export/2` refuses a false PDF/A claim.** `set_pdf_a/2` writes a
  conformance assertion into the file, so a document that declares a level and
  breaks it lies about itself — and nothing discovers that until someone relies
  on it. Export now raises, naming every violation and the clause it breaks.
  `Tincture.pdf_a_violations/1` returns the list without exporting, and
  `export(pdf, enforce: false)` exports anyway, logging what it let through.

  Every rule was confirmed against veraPDF rather than read off a
  specification. Refused: unembedded fonts, encryption, text and choice fields,
  signature fields, push buttons, and level A without tagging. Allowed:
  checkboxes, radio buttons and links, all verified compliant.

  This is not a conformance check and does not claim to be — Tincture sees the
  document it built, not the file a validator sees.
- **Digital signatures.** `Tincture.sign/3` produces a detached PKCS#7
  signature covering the whole file, verified against OpenSSL rather than only
  against itself. `Tincture.PDF.CMS` builds the CMS `SignedData` structure in
  DER, since OTP ships no encoder for it; `:crypto` and `:public_key` are OTP
  applications, so there are still no third-party dependencies.

  Signing is the one thing in Tincture that is not a pure transformation: a
  signature covers the finished bytes, so `export/2` reserves space, measures
  the real offsets, signs, and patches the result back without moving anything.

  No timestamp authority yet, so a signature proves the document has not
  changed — not when it was signed.
- **`Tincture.PDF.ICC`** — a built-in sRGB ICC profile, generated from the
  published constants rather than read from the system or shipped from
  elsewhere, so archival output is reproducible on any machine. Uses the real
  sRGB tone curve including its linear segment, not the gamma 2.2 shortcut.
- **A file identifier on every document.** `/ID` was emitted only for encrypted
  documents; PDF/A requires one always. Derived from the content rather than the
  clock, so building the same document twice produces identical bytes and an
  archived file can be checked against a rebuild.
- **XMP metadata.** The catalog now carries a `/Metadata` stream — Dublin Core
  title, creator and description, plus `pdfuaid:part` for a tagged document.
  The info dictionary alone satisfies neither PDF/UA nor PDF/A.
- **`/ViewerPreferences << /DisplayDocTitle true >>`** on tagged documents, so a
  reader shows the document's title rather than its file name.
- **`Tincture.Layout.Table.render/6` tags itself.** Inside a tagged document it
  emits `/Table`, `/THead`, `/TBody`, `/TR` and a `/TH` or `/TD` per cell, gives
  header cells a `/Scope`, and marks its own borders as artifacts. It could not
  be tagged by hand, because it draws the whole grid in one call. Controlled by
  `:tag`, which defaults to `:auto` — tagging only when the caller is already
  tagging, since a structure tree containing nothing but a table reads worse
  than none at all.
- **`Tincture.artifact/2`**, marking decoration — rules, borders, page furniture
  — as content to skip. In a tagged document every operator must be either
  tagged or an artifact; anything that is neither is announced as stray noise.
- **Telemetry.** Three spans — `[:tincture, :export]`, `[:tincture, :page]` and
  `[:tincture, :font, :embed]` — covering document duration and size, per-page
  timing, and per-font embedding with source and embedded sizes so subsetting is
  measurable. `:telemetry` is an **optional** dependency: without it every event
  call compiles away, so Tincture still has no required runtime dependencies.
  See `Tincture.Telemetry`.
- **Hyperlinks and annotations** — external URLs and internal page targets, via
  `Tincture.link/6` and `Tincture.text_link/5`. Previously the library emitted
  no `/Annot` objects at all.
- **Interactive forms (AcroForm)** — text fields, checkboxes and choice fields,
  via `Tincture.text_field/7`, `Tincture.checkbox/6` and
  `Tincture.choice_field/7`. Supports field flags (multiline, password,
  read-only, required, dropdown, editable, sort), maximum length, tooltips and
  initial values.
- **The remaining form field types.** `Tincture.radio_group/4`,
  `Tincture.push_button/7` and `Tincture.signature_field/7` complete the field
  set. A radio group is the first field that is not a single object: the
  specification models it as a parent field holding the value with a kid widget
  per button, so the serialiser now emits multi-object fields.
- **Generated appearance streams for button-like fields.** Radio buttons,
  checkboxes and push buttons now carry real `/AP` streams. Previously they
  relied entirely on `/NeedAppearances`, which only *interactive* viewers
  honour — so a checkbox was invisible when printed, thumbnailed or rasterised
  server-side, and a push button, whose face is nothing but appearance, showed
  nothing at all. A radio button additionally cannot work without one, since
  its export value *is* the name of its "on" appearance state.
- **AES-256 encryption** — `Tincture.encrypt/2`, standard security handler
  revision 6 (`/V 5 /R 6`, PDF 2.0). User and owner passwords, permission
  flags, optional metadata encryption. Note that an owner password alone is
  advisory: the document is then encrypted under the empty user password and
  any reader can open it. Only a user password is real protection.
- `Tincture.Font.Context` — a measurement context pairing a document's embedded
  metrics with the static ones, so anything holding a document can measure any
  font that document can draw. The document-aware entry points build one
  themselves, so laying out an embedded font now needs nothing extra:

      Tincture.text_paragraph(pdf, 50, 700,
        RichText.from_plain(terms, font: "Body", size: 10), 400, align: :justified)

- `RichText.remeasure/2` and a `:context` option on `RichText.from_plain/2` and
  `from_runs/2`, for laying text out through `Tincture.Typography` directly.
- `RichText.unmeasured_fonts/1`, reporting which fonts are still estimates.
- `Tincture.Font.UnicodeRanges` — the complete OpenType `OS/2 ulUnicodeRange`
  bit table.
- **Showcase documents.** Five reference documents built with the public API,
  each with an end-to-end test and a render script under `scripts/`: an invoice,
  a bank statement, a Markdown-sourced document, a marketing poster and a
  multi-font report. Invoice and bank statement additionally carry locked
  SHA-256 fixtures; the other three are tested but not byte-locked.
- **`examples/`**, with the produced PDFs committed. An invoice, an interactive
  form exercising every field type, and a telemetry report. `mix examples` runs
  them all. Font paths are resolved per platform.
- **`examples/compliant.exs`**, a PDF/UA template with every requirement
  annotated where it is satisfied — including list structure — validated at
  106 of 106 rules and 2605 of 2605 checks.
- `mix check`, which runs every gate CI runs, in the same order.

### Changed

- **Font subsetting is now on by default** (`subset: :used_text`). Only the
  glyphs a document draws are embedded, which typically cuts an embedded font
  by 70–90%. Previously it defaulted to `:none` and was undocumented. Pass
  `subset: :none` for the old behaviour.
- **Link annotations omitted `/F`.** Every annotation needs one, and a link
  without it is a link that vanishes when the page is printed. Failed ISO
  19005-2 clause 6.3.2, which made external links impossible in an archival
  document. Now `/F 4` (Print), and links are PDF/A-valid.
- **`/NeedAppearances` was set whenever a document had any form field**, even
  ones that carry their own appearance streams. Only text and choice fields
  need it — a checkbox or radio button draws every state itself. It is now
  emitted only when something actually requires it, which makes checkbox and
  radio-button forms valid PDF/A where they previously were not.
- **Stream `/Length` was overstated by one byte** on content streams, form
  XObjects and CMaps. The EOL before `endstream` is a delimiter rather than
  stream data, so a stream whose own last byte is a newline needs one of each —
  otherwise its final byte is consumed as the delimiter. Every content stream
  ends in a newline, so every one was affected. Failed ISO 19005-2 clause
  6.1.7.1; found by validation.
- **`/CIDSet` is no longer emitted.** It must identify exactly the CIDs present
  in the embedded program, and subsetting falls back to the whole font on
  several paths while the name keeps its subset tag — so an accurate one cannot
  be produced at that point. veraPDF rejects an inaccurate CIDSet (ISO 14289-1
  clause 7.21.4.2) where an absent one is conformant; it is optional in PDF 1.7
  and deprecated in PDF 2.0. Required only for PDF/A-1, which is not yet a
  target.
- **Table `/Scope` moved into an attribute dictionary.** It was emitted as a
  direct key on the structure element, where a reader ignores it — leaving the
  table's structure undeterminable and failing ISO 14289-1 clause 7.5. It now
  reads `/A << /O /Table /Scope /Column >>`. Found by validation.
- **Form fields now reject a non-standard font.** A field's value is rendered
  by the viewer from its `/DA` string, which resolves against the AcroForm
  resource dictionary — and that can only carry the standard 14. Naming an
  embedded font there emitted a font dictionary no viewer could resolve, so the
  value silently did not render. Static text is unaffected.
- **Rich text no longer raises on an unknown font at construction.** It cannot:
  an embedded font is unresolvable until a document is known, and at that point
  indistinguishable from a typo. Tokens whose font could not be resolved carry
  an estimated width and `measured?: false`, and `Typography.layout_paragraph/3`
  refuses to lay those out — so a mistyped font name still fails loudly, with a
  better message, at the point where the answer is actually knowable rather
  than silently producing a plausible-looking but wrong paragraph.
- Decomposed the two modules that held most of the library. `Font.TTF` went
  from 4,530 lines with a single public function to a coordinator delegating to
  `TTF.Cmap`, `TTF.Glyf`, `TTF.Name`, `OpenType.GPOS`, `OpenType.GSUB`,
  `OpenType.Common`, `Font.CFF` and `Font.Binary`. `PDF.Serialize` went from
  3,491 lines to 516, with font embedding extracted to `PDF.FontEmbed` and PDF
  syntax primitives to `PDF.Object`.
- Documentation. The layout and typography API — 15 public functions across
  five modules — was `@moduledoc false` and invisible in generated docs.

### Fixed

- **Embedded fonts could not be laid out.** Font embedding and the typography
  engine — the library's two headline features — did not compose. Every layout
  entry point measured through `Font.text_width/3`, which resolves only the
  standard 14 fonts and AFM files on disk. An embedded TrueType font has no
  AFM; its metrics are parsed at registration and live on the document, so a
  pure function could never see them. `text_paragraph/6`, `Layout.Box.flow_text/7`,
  `Layout.Table.render/6` with `:auto` columns and `text_link/6` all raised
  `unknown font` for any embedded font. The metrics were parsed, correct, and
  sitting unused: the drawing path had its own private copy of the measurement
  code all along.
- **Subsetting silently fell back to embedding the whole font** for any text
  containing a space. A glyph with no outline is encoded as zero bytes, which
  the subsetter treated as malformed, aborting the subset. Since almost every
  string contains a space, subsetting was effectively never applied.
- **A malformed `name` table crashed the parse.** `:unicode.characters_to_binary/3`
  signals bad input by returning a tuple rather than raising, so a rescue never
  fired and the tuple reached a function expecting a binary. A truncated
  UTF-16BE font name — what a bad subsetter produces — raised
  `FunctionClauseError` instead of being skipped.
- **The `OS/2` Unicode range table was 91% missing.** Only 11 of ~123
  `ulUnicodeRange` bits were mapped, all below 32, so `div(bit, 32)` was always
  0 and the font's `ulUnicodeRange2/3/4` words were parsed and then ignored.
  Any CJK, Hangul, punctuation, currency or math codepoint was reported as
  unsupported.
- `Typography.Hyphen` called `File.stream!/3` with the argument order deprecated
  in Elixir 1.16 — on the `:en_gb` path, the default locale.
- The `t:Tincture.rich_text/0` type was declared as a plain map while every caller requires a
  `%RichText{}` struct.
- A divide-by-zero in `Benchmark.Document` when `:timer.tc` reports 0µs on a
  fast machine.

### Infrastructure

- CI now passes. Upstream's 13 workflow runs all failed at
  `mix format --check-formatted`, so its test suite had never executed in CI.
  Tincture runs format, warnings-as-errors, Credo, Dialyzer and coverage,
  with the test suite on Elixir 1.16, 1.17, 1.18 and 1.19.
- 1,011 tests, up from 444 (one of which failed).
- Coverage measured and gated at 80%; currently 88.3%.
- Credo at `--strict` with zero issues, down from 174.
- Dialyzer passing, with a documented ignore file for defensive clauses that
  keep functions total.

[Unreleased]: https://github.com/thatsme/tincture/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/thatsme/tincture/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/thatsme/tincture/releases/tag/v0.1.0
