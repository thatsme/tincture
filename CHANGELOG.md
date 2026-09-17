# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **`bidi: :basic` resolves neutral tokens in linear time.** Each space or break
  used to scan the whole line on both sides for the nearest strong direction,
  which is quadratic in the tokens on a line. One pass in each direction now
  gives the same result. Only very long lines see a difference; output is
  unchanged.

- **ToUnicode range compaction no longer copies its accumulators per run.**
  Output is unchanged byte for byte.

### Documentation

- **Every public function in a documented module now has a doc.** Nineteen
  had a spec and nothing else, among them `Layout.Template`, `Layout.Table.render/6`,
  `Layout.Box`, `Typography.layout_paragraph/3`, `Typography.Hyphen.hyphenate/3`,
  and the option-taking arities of `link` and `text_link`. The `:shaping` and
  `:kerning` options of the fallback text functions are documented for the
  first time.

- **Internal functions are hidden from the generated docs.** Thirty-nine
  functions called only from inside the library — the per-table font parsers,
  the CFF and OpenType helpers, `PDF.FontEmbed`, the `Tincture.PDF` state
  functions the `Tincture` module wraps, and `PDF.Serialize.export/1` — are now
  `@doc false`. They are still public and callable; code that uses them is
  unaffected.

- **`Layout.Table` no longer claims cells wrap.** A cell is drawn as one line
  of text and every row has the same height.

## [0.3.2] — 2026-08-22

### Added

- **Links into another PDF file.** `{:file, path}` opens the target document,
  `{:file, path, page_number}` opens it at a page, on both `link/7` and
  `text_link/6`. This is a `/GoToR` action: `path` is a file specification
  resolved by the reader against the document that carries the link, so a set
  of documents that ship together can refer to each other and still resolve
  after being moved or zipped.

      Tincture.link(pdf, 72, 700, 200, 14,
        {:file, "Attached documents/Appendix-A.pdf", 3},
        contents: "Appendix A, page 3: calibration procedure"
      )

  Page numbers count from 1 everywhere, including into a remote file. The
  1-based to 0-based conversion happens once, at serialisation: page 13 writes
  `/D [12 /Fit]`. Confirmed in a viewer before the code was written — a
  hand-written `/D [12 /Fit]` opens the thirteenth page in SumatraPDF — because
  an off-by-one here lands in a document the author no longer controls,
  pointing at the wrong page rather than failing visibly.

  Everything checkable is checked when the link is created, since a file target
  resolves nothing and nothing downstream can catch a mistake. Absolute paths
  are refused, because they name a location on the machine that wrote the file.
  Non-ASCII paths are refused, because the string form cannot carry them
  portably. Backslashes become forward slashes, which is the one silent
  transformation and earns it: a path that works on the author's machine and
  fails on the reader's is the failure mode worth designing out.

  Two limitations, stated here because they decide whether the feature suits
  you. **The page number is a promise about a file Tincture never reads** —
  nothing checks it, and if the target gains a page near the front, every link
  into it is silently off by one. Named destinations would survive that; the
  `{:file, path, {:named, name}}` shape is reserved and not implemented, so it
  can land later as a pure addition. **Tincture also cannot detect a missing or
  renamed target**, and what a viewer does with a file specification that
  resolves to nothing has not been observed here.

  Viewer support is not universal. Desktop readers follow these links; browser-
  embedded viewers generally do not, refusing local-file navigation as policy.
  Measured while building this: SumatraPDF follows them, Microsoft Edge renders
  the link and does nothing on click, Firefox's viewer does not act on them.

- **`:new_window` on `link/7` and `text_link/6`.** A genuine tri-state: `true`
  and `false` both write `/NewWindow`, and omitting the option omits the key.
  That is a different instruction, not a shorthand for `false` — it leaves the
  choice to the reader's viewer instead of overriding a preference they may
  have set. With the key absent, SumatraPDF opened a new tab of its own accord.

- **A two-document example.** `examples/remote_links.exs` writes a report and a
  linked appendix beside it, the first example that produces more than one
  file. Both are tagged and both pass PDF/UA-1: a main document that is
  accessible and an appendix that is not makes a set half-readable, with no way
  for a reader to tell before opening it.

### Changed

- **`archival.pdf` carries a remote link.** ISO 19005-2 clause 6.5.1 lists the
  actions PDF/A permits and `GoToR` is on it — the rule is an allowlist,
  confirmed from veraPDF's own profile XML and then against real bytes. That
  only means something if a validated document actually contains one, so now
  one does. `PDF.Archival` gains no rule; the standard permits this.

- **CI validates the linked pair too.** Eight claims now rather than six.

## [0.3.1] — 2026-08-22

### Fixed

- **A `:note` carries an `/ID`, resolvable through `/IDTree`.** ISO 14289-1
  clause 7.9 requires a Note element to have an `/ID`, and requires it to be
  unique. Tincture wrote neither, so a tagged document containing a `:note`
  failed PDF/UA — measured with veraPDF 1.30.2 against 0.3.0, not inferred from
  the clause.

  The identifier is generated: sequential, zero-padded, derived from position
  in the structure tree, so output stays byte-reproducible. An `:id` option on
  `tag/4` overrides it for a caller who needs a stable external reference, and
  a collision raises rather than shipping a document that breaks test 2.

  Generating it is the right call here and the opposite of the `:contents`
  decision in 0.3.0, which is deliberate: `/Contents` is human-meaningful text
  a machine cannot invent, so auto-filling it would manufacture conformance
  while telling a screen-reader user nothing. An `/ID` carries no meaning.
  Requiring authors to invent unique strings would produce collisions and
  nothing else.

  `/StructTreeRoot` now also emits an `/IDTree`. ISO 32000-1 makes that name
  tree the mechanism by which an `/ID` is dereferenced, so an `/ID` without one
  is unusable rather than merely unverified — and no veraPDF profile carries a
  rule about the tree at all, so nothing would have reported it. Its `/Names`
  array is ordered by byte comparison, which a conforming consumer is entitled
  to binary-search; the identifiers are zero-padded so that lexical and
  numeric order agree past `note0009`.

  The tree is emitted only when something registers an identifier, so a
  document with no `:note` serialises exactly as it did under 0.3.0.

  `compliant.pdf` now carries a tagged note, so clause 7.9 is exercised on
  every release rather than passing for want of anything to match.

## [0.3.0] — 2026-08-22

### Added

- **`Layout.Box` and `Layout.Template` tag themselves.** `Layout.Table` already
  did; these were the two layout helpers that produced untagged content in a
  tagged document, which a reader announces as stray noise. Both take `:tag`,
  defaulting to `:auto` — marking up only when the caller is already tagging,
  since a structure tree holding one element and nothing else reads worse than
  none at all.

  `Layout.Box` also takes `:tag_as`, and the value that matters is `:artifact`.
  A watermark, a running strapline or a repeated sidebar label is text a reader
  should *skip*; marking it `/P` means it is read out on every page. Structure
  that is well-formed but wrong is exactly what a conformance checker cannot
  catch — veraPDF verifies the tree is valid, not that it describes the page.

  `Layout.Template` marks its header and footer as artifacts for the same
  reason: running furniture repeats on every page and says nothing about the
  content.

- **`/Tabs /S` on tagged pages.** Tab order now follows the structure tree
  rather than the order annotations happened to be added in, which is what a
  keyboard user gets as soon as a page carries both links and form fields.
  Untagged pages do not carry it — there is no structure to follow, and
  emitting it always would have rewritten every existing document for nothing.

- **veraPDF runs in CI, and its reports are uploaded.** Every conformance
  claim in the README rested on a validator that had never run in the pipeline
  — through 0.2.0 it was a manual step on whichever machine last had it
  installed. The examples job now installs veraPDF, validates the five claims
  the README makes, fails the build on any of them, and uploads the
  machine-readable reports as an artifact. A conformance claim a stranger
  cannot check is one they have to take on trust.

- **What the validated corpus actually exercises, written down.** veraPDF
  scores rules, not features, and a rule with nothing to match counts as
  passed — which is how tagged links scored 106 of 106 for two releases while
  being unreachable from the structure tree.

  The README now lists it: of the 37 structure types Tincture can emit, the
  validated documents emit 18. The other 19 have never been through a
  validator. Two of those are known broken rather than merely unexercised —
  `:note` fails clause 7.9 for want of an `/ID` (fixed in 0.3.1), and form
  fields cannot be made conformant at all, since clause 7.18.4 wants a widget
  nested in a `Form` element and Tincture has no such tag.

  A test pins the set, so it fails when a type becomes covered and when a new
  uncovered one arrives. The list is meant to shrink.

- **`:contents` on `link/7` and `text_link/6`,** the link's alternate
  description. A link's rectangle describes nothing on its own, so a reader
  that reaches the annotation has only `/Contents` to announce. Say where the
  link goes — `"ISO 14289-1 at iso.org"`, not `"link"`.

  It is required in a tagged document and there is no default, deliberately.
  The obvious convenience would be to reuse `text_link`'s visible text, and
  most call sites would become conformant for free — but a description that
  mechanically repeats the link text satisfies the validator while telling a
  screen reader user nothing, and `"click here"` is exactly where that does
  harm. Generating it would be manufacturing conformance.

  `text_link/6` accepts `contents: :text` where the text genuinely is the
  description. Still a deliberate act, just a short one.

- **`Tincture.pdf_ua_violations/1`.** Tagging is a claim: the catalog carries
  `/MarkInfo` and the XMP carries `pdfuaid:part`, and a reader that finds
  structure trusts it. This lists every PDF/UA violation Tincture can detect,
  without exporting — a `:figure` with no alternative text, a link annotation
  outside the structure tree, a link nested in an element other than `:link`.
  See `Tincture.PDF.Accessibility`.

  Only what is structural and therefore visible to a library. Whether an
  alternative text is *accurate*, or whether a reading order matches intent, is
  not something this can settle for you.

### Changed

- **`export/2` refuses a tagged document that breaks a PDF/UA rule Tincture can
  see.** The same treatment a false PDF/A claim already got: it raises, naming
  each violation and its clause, and `enforce: false` exports anyway with a
  warning.

  Three rules are checked, and all three previously wrote without complaint, so
  a document that exported under 0.2.0 may now raise:

  - a `:figure` with no alternative text. The reader announces an element it
    cannot describe, and the person using it learns only that something is
    there — worse than leaving the document untagged;
  - a link annotation outside the structure tree, or nested in an element
    other than `:link`;
  - a link annotation with no alternate description in `/Contents`.

  Wrap links in `tag(:link, ...)` and give them `contents:`, pass `alt:` to a
  `:figure`, or pass `enforce: false` to export regardless.

- **A tagged link annotation is written as an indirect object.** It used to be
  a dictionary inline in the page's `/Annots` array, which has no object number
  for `/OBJR` to name. Object numbering therefore shifts in any tagged document
  that contains a link — relevant only if you diff, checksum or byte-pin your
  output.

  An untagged link is still written inline, deliberately: a fix for tagged
  documents should not renumber objects for people it does not apply to.
  Untagged output is unchanged byte for byte, confirmed across all eight
  examples.

- **The examples embed a vendored font, so their output is reproducible.**
  An embedded font goes into the file byte for byte, so the committed PDFs
  under `examples/output/` depended on which fonts the generating machine had:
  running `mix examples` anywhere else rewrote all of them without a single
  source change, and the committed output could only be reproduced by whoever
  produced it.

  `examples/fonts/` now carries Liberation Serif and Liberation Sans 2.1.4,
  under the SIL Open Font License 1.1 — verified from each font's own `name`
  table, not taken on trust. Output is now identical on every machine, so a
  diff there means something changed. `signed.pdf` still differs on every run,
  because a signature carries the signing time.

  These are **not** in the Hex package: `files:` in `mix.exs` excludes
  `examples/` entirely, and Tincture still ships no font programs. Nothing here
  constrains what you embed in your own documents.

### Fixed

- **A `/Link` structure element now references its annotation.** Three things
  PDF/UA-1 requires, and that no tagged document Tincture has written — 0.1.0
  and 0.2.0 included — had:

  - the `/Link` element's `/K` now holds `<< /Type /OBJR /Obj n 0 R >>`, naming
    the annotation as a child of the element;
  - the link annotation now carries `/StructParent`;
  - `/ParentTree` now resolves both directions — an annotation key to its
    structure element, a page key to its array of marked-content parents.

  `/StructParent` and a page's `/StructParents` index the same number tree, so
  the keys come from one counter: pages take `0..n-1`, annotations continue
  from `n`. A link created inside `tag(:link, ...)` is associated
  automatically, so no call site changes.

  Measured against veraPDF 1.30.2, a tagged link failed three machine rules
  before this release — ISO 14289-1 clause 7.18.1 test 2, clause 7.18.5 test 1
  and clause 7.18.5 test 2. Structure references clear 7.18.5 test 1;
  `:contents` clears the other two. A tagged link now passes `--flavour ua1`.

  Worth knowing how this survived two releases. veraPDF checks all three, and
  always did. They never fired because `compliant.pdf` — the example behind the
  106/106 figure — contained no link annotations at all, and a rule with
  nothing to match counts as passed. The gap was in the validated corpus, not
  in the validator. `compliant.pdf` now carries a tagged link, so those three
  rules are exercised on every release.

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

[Unreleased]: https://github.com/thatsme/tincture/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/thatsme/tincture/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/thatsme/tincture/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/thatsme/tincture/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/thatsme/tincture/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/thatsme/tincture/releases/tag/v0.1.0
