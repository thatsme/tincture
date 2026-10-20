# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.6] — 2026-10-20

**No output changes.** Every document exports to the same bytes as with
0.3.5. Three new warnings announce what 0.4.0 refuses in forms. Each warns and
carries on.

### Deprecated

Each of these warns now and raises in 0.4.0:

- **A form field with no `:tooltip` in a tagged document.** Export warns once
  for each such field; a radio group is one field. The tooltip is written as
  `/TU`, the name a screen reader announces for the field. *Migration:* pass
  `tooltip: "..."` to every field function in a tagged document.
- **A form field created outside every `tag/4` scope in a tagged document.**
  Export warns once for each such field. 0.4.0 places every field in the
  structure tree, under the element that is open when the field is created,
  and a field with none open has no place there. *Migration:* create the field
  inside a `tag/4` scope, for example `:section` or `:div`.
- **A text field, choice field or push button whose value, options or label
  uses a character WinAnsi cannot encode, with a standard-14 font.** The field
  call warns, naming the first such character. 0.4.0 draws the value into the
  field's appearance itself, and a standard-14 font is written with WinAnsi
  encoding. Line breaks in a multiline text value are not affected; in a
  single-line value, an option or a label, a line break warns like any other
  character. *Migration:* keep the value WinAnsi-encodable; from 0.4.0,
  register an embedded font for the field.

### Documentation

- **`examples/signed.exs` prints how to verify the signature.** It now names
  `scripts/extract_signature.exs` and the `openssl cms -verify` command, as
  `examples/README.md` does, in place of `openssl asn1parse`.

## [0.3.5] — 2026-10-20

**Documentation only. No behaviour changes, and no output changes.** 0.3.4's
documentation made claims that were not true of the code; this release
corrects them.

### Documentation

- **Signature verification is described as it is done.** 0.3.4's README and
  ROADMAP said signatures pass `openssl cms -verify` in the test suite. They
  were verified there by an independent Elixir verifier, and for SHA-256 only:
  SHA-384 and SHA-512 signatures were checked for being well-formed, not
  verified. The test suite now verifies all three digests, and checks that
  altering the document breaks each. CI now also verifies `signed.pdf` with
  `openssl cms -verify` on every commit, and checks that a tampered copy fails.
  That checks the signature's integrity only, since the example's certificate
  is self-signed and chain trust is not checked. `Tincture.PDF.CMS`'s docs
  made the same claim, and are corrected the same way.
- **`set_pdf_a/2` no longer says a declared level is not enforced.** It is:
  `export/2` refuses a document that breaks a PDF/A rule Tincture can see,
  unless given `enforce: false`, as `export/2` and `Tincture.PDF.Archival`
  already said. The docs now list what is refused.
- **`export/2`'s `:enforce` option no longer says it applies only to PDF/A.**
  It also governs the PDF/UA checks on a tagged document, which `export/2`
  has refused since 0.3.0 when they fail.
- **`signature_field/7` no longer says Tincture does not apply signatures.**
  `sign/3` has applied them since 0.2.0. The docs now point to it, and say that
  a signature field shows nothing in a static render and is refused in a
  document that declares PDF/A.
- **Digital signatures are no longer listed under 0.1.0.** They first shipped
  in 0.2.0; the 0.1.0 entry now says so.
- **`add_page/1` and `set_page/2` document the 0.3.4 warning.** Changing page
  while a content tag or an `artifact/2` block is open warns, and raises from
  0.4.0. Their docs did not say so.
- **Every other statement that something is verified now names its evidence,
  or no longer claims to be verified.** Each was checked against a CI step, a
  test, or veraPDF 1.30.2's profiles:
  - Viewer behaviour for links between documents (SumatraPDF, Edge, Firefox,
    macOS Preview) is described as observed by hand at 0.3.2 and 0.3.3, not as
    verified.
  - The encryption docs no longer list readers that support the output; no
    reader is run against it. They say what is checked: the test suite
    decrypts the output with an independent implementation of the
    specification's algorithms. They no longer name `qpdf --decrypt`, which
    nothing runs.
  - Statements about what veraPDF checks cite the rule: PDF/UA-1 7.1-3 for
    untagged content, 7.18.5-1 and 7.18.5-2 for links, and 7.3-1 for figures.
  - The ROADMAP said an absent `/CIDSet` passes PDF/A-1 validation. It does
    not: PDF/A-1 requires one (PDFA-1B 6.3.5-3). Only PDF/A-2 makes it
    optional.
  - The README's test and coverage figures name the release they were measured
    at. The count of Credo findings exempted inline, given as 70, is no longer
    quoted.
  - `Tincture.PDF.Archival` no longer says every rule was confirmed against
    veraPDF, or that checkboxes and radio buttons are fine for PDF/A. Tincture
    does not refuse them, but no validated document carries one.
  - `Tincture.PDF.Sign` said altering any byte breaks a signature. Bytes inside
    the `/Contents` string are excluded from what is signed.
  - The ROADMAP no longer lists telemetry as checked by an independent tool, or
    says that everything done was checked against a validator.
  - `RELEASE.md` no longer says `mix check` is every gate CI runs; the
    absolute-path check is listed beside it. It gives the right reason
    `signed.pdf` changes on every run: a new key, not the signing time.

### Infrastructure

- **CI verifies `signed.pdf` with `openssl cms -verify`, and fails if the
  committed example documents differ from the ones it validates.**

## [0.3.4] — 2026-10-19

**No document that exports with 0.3.3 fails to export with this release, and
none renders differently.** Every new check warns and carries on; the
behaviours that warn are listed under Deprecated, and become errors in 0.4.0.

### Added

- **`:bbox` on `tag(:figure, …)`.** `{left, bottom, right, top}` in points,
  the rectangle enclosing the figure's visible content, written as given in
  place of the computed one.

### Changed

- **`stroke/1`, `fill/1`, `fill_even_odd/1`, `clip/1` and `clip_even_odd/1`
  with no open path no longer write an operator.** The operator was invalid
  there and ignored by viewers, so the page looks the same and the file is now
  valid. The call warns; see Deprecated.

### Deprecated

Each of these warns now and raises in 0.4.0:

- **`stroke/1`, `fill/1`, `fill_even_odd/1`, `clip/1` or `clip_even_odd/1`
  with no open path.** Pass the shape's own `paint` argument instead, or start
  a path with `move_to/3`.
- **`add_page/1` or `set_page/2` while a content tag or an `artifact/2` block
  is open.** Its marked content would begin on one page and end on another.
  Close the tag before changing page.
- **A `:figure` that draws nothing and has no `:bbox`.** It has no bounding box
  to write.
- **A `:bbox` that is not four numbers, has `left >= right` or
  `bottom >= top`, lies outside the page, or is given on a tag other than
  `:figure`.** It is ignored, as `tag/4` has always ignored options it does
  not use, and the box is computed instead.

### Fixed

- **Tagged figures carry a bounding box, and inline elements placed at block
  level declare it.** A `:figure` now gets the `/BBox` of what it draws, text
  included, and a `:link`, `:note`, `:figure` or other inline element placed
  directly in a `:document`, `:section` or similar grouping element gets
  `/Placement /Block`, so screen readers and reflow lay them out correctly.

- **A shape piped into `stroke/1` or `fill/1` was painted wrongly.** `line/6`,
  `rectangle/6` and `circle/5` already paint with `:stroke` by default, so a
  following `stroke/1` wrote a painting operator with no path (invalid PDF
  syntax that viewers ignore), and a following `fill/1` filled nothing, leaving
  only the outline. The examples did the former and no longer do; code that
  used either pattern should pass the shape's own `paint` argument (`:fill`,
  `:stroke` or `:fill_and_stroke`) instead.

- **The package no longer ships a stray partial file,**
  `priv/hyphen/original_tex/.!62084!nohyphbx.tex`, a truncated copy of
  `nohyphbx.tex` that nothing read.

### Documentation

- **Every conformance statement names its tool, version and where it ran.**
  The README, ROADMAP and examples now say "passes veraPDF 1.30.2 in CI on
  every commit", with the rule and check counts each document had at 0.3.4,
  rather than a bare "compliant". PAC, a second and independent PDF/UA checker,
  is listed alongside veraPDF: an audit on 2026-10-19 of the five PDF/UA
  examples found what is fixed above, and now reports 0 errors and 0 warnings
  on each. What it still notes, and that it was run by hand once, is recorded
  in the ROADMAP.

## [0.3.3] — 2026-10-18

### Changed

- **`bidi: :basic` resolves neutral tokens in linear time.** Each space or break
  used to scan the whole line on both sides for the nearest strong direction,
  which is quadratic in the tokens on a line. One pass in each direction now
  gives the same result. Only very long lines see a difference; output is
  unchanged.

- **ToUnicode range compaction no longer copies its accumulators per run.**
  Output is unchanged byte for byte.

### Fixed

- **A link to another file with no page now carries the required `/D`.**
  `{:file, path}` wrote a `/GoToR` action without the destination ISO 32000-1
  Table 200 marks as required. It now writes `/D [0 /XYZ null null null]`,
  opening the target at its first page with position and zoom left to the
  reader. Links of the form `{:file, path, page}` are unchanged.

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

- **README and ROADMAP corrected against the code.** Transparency and
  gradients, implemented in 0.2.0, are no longer listed as missing or as open
  work. The examples list has nine scripts, including `remote_links.exs`. The
  ROADMAP's structure-type count was inverted and now reads 19 of 37
  exercised, and its PDF/UA-1 summary states that coverage. Its accessibility
  item lists only the PAC audit as remaining, and the `/CIDSet` note under
  PDF/A-1 states its reason rather than pointing at a note that did not exist.
  Test, coverage and Credo figures are re-measured.

- **macOS Preview does not follow links into another file.** Clicking one shows
  a permission alert and the target does not open (observed on macOS 26.6.2).
  Preview is the default PDF viewer on macOS, so the `link/7` docs, ROADMAP and
  `examples/README.md` now say so, alongside the browser-embedded viewers
  already listed, and that a desktop reader which follows cross-file links is
  needed.

### Infrastructure

- **Credo `--strict` passes again under the stricter structural thresholds.**
  The 70 findings already in `lib/` are exempted one by one with an inline
  comment naming the check, so the debt is a list rather than a relaxed
  threshold; new code is held to the full bar. `test/` and `scripts/` are
  exempt from the structural checks only.
- **veraPDF is pinned to 1.30.2 in CI.** The unversioned installer URL follows
  the latest release, so a veraPDF release could change what CI validates
  against with no change in this repository.
- **The corpus audit covers every document CI validates.** The two linked
  documents were validated in CI but not counted by
  `corpus_coverage_test.exs`. Neither emits a structure type the corpus
  lacked, so the coverage figures are unchanged.

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

  See [`examples/gradient.exs`](https://github.com/thatsme/tincture/blob/main/examples/gradient.exs).

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
- **Digital signatures** (first shipped in 0.2.0; listed here in error until
  0.3.5). `Tincture.sign/3` produces a detached PKCS#7 signature covering the
  whole file, verified against OpenSSL rather than only against itself.
  `Tincture.PDF.CMS` builds the CMS `SignedData` structure in DER, since OTP
  ships no encoder for it; `:crypto` and `:public_key` are OTP applications,
  so there are still no third-party dependencies.

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

[Unreleased]: https://github.com/thatsme/tincture/compare/v0.3.6...HEAD
[0.3.6]: https://github.com/thatsme/tincture/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/thatsme/tincture/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/thatsme/tincture/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/thatsme/tincture/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/thatsme/tincture/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/thatsme/tincture/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/thatsme/tincture/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/thatsme/tincture/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/thatsme/tincture/releases/tag/v0.1.0
