# Roadmap

What Tincture would need to be a defensible choice for enterprise document
generation, and roughly in what order.

Nothing here is assumed. Where something is missing it was checked against the
source. Where a conformance item is claimed done, the document that exercises
it passes a validator in CI; where a feature is claimed done, it has tests.
Which constructs the validated documents do not exercise is listed in the
[README](README.md#what-the-validated-documents-actually-exercise).
Partial support is said to be partial, because "we have forms" and "we have the
forms you need" are different claims.

## At a glance

**Done, and checked by an independent tool** (except telemetry, which is
covered by the test suite only)

| | |
|---|---|
| Accessibility — PDF/UA-1 | passes veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit; at 0.3.6: 106 of 106 rules on each of five documents. PAC 2026.1 audit, 2026-10-19, on the files at `4a75f1e`: PDF/UA 0 errors, 0 warnings. On a corpus that exercises 19 of 37 structure types ([1](#1-accessibility--tagged-pdf-pdfua), [coverage](README.md#what-the-validated-documents-actually-exercise)) |
| Archival — PDF/A-2b, 2u, 2a | passes veraPDF 1.30.2 in CI on every commit; at 0.3.6: up to 153 of 153 rules ([2](#2-archival--pdfa)) |
| Digital signatures | SHA-256, SHA-384 and SHA-512 verified by an independent verifier in the test suite; `signed.pdf` passes `openssl cms -verify` in CI on every commit, for integrity only, since its certificate is self-signed ([3](#3-digital-signatures)) |
| Telemetry | covered by the test suite; no independent tool applies ([9](#9-operability)) |

**Next, roughly in order**

1. ~~**Transparency and shading**~~ — **done.** Constant alpha and axial and
   radial gradients. See [5](#5-transparency-and-shading); blend modes and
   patterns remain.
2. ~~**Accessibility completed**~~ — **done.** Tagging for `Layout.Template`
   and `Layout.Box`, `/Tabs /S`, and an audit with PAC as well as veraPDF. See
   [1](#1-accessibility--tagged-pdf-pdfua) for what the audit found and what
   remains.
3. **Forms completed** — appearance streams for text and choice fields, which
   would also let signed and archival documents carry form fields. The same
   machinery gives signature widgets an appearance, without which a signed
   document cannot also be PDF/A.

   This one is worth more than its own entry. An `/AP` stream is a form
   XObject: a nested content stream with its own resources, holding text laid
   out and clipped. That primitive is what patterns, soft masks on drawn
   content, and signature appearances all need — so items 5 and 6 get
   substantially cheaper once it exists, and neither should be attempted first.
4. **Object and cross-reference streams** — file size; content streams are
   written uncompressed today. Grouped with incremental updates, since both
   rewrite the file's byte layout and both collide with signing. Incremental
   updates are also what a second signature, or any later stamping, depends on.
5. **Colour beyond RGB, and patterns** — spot inks and ICC spaces for print
   production, plus a gradient as the fill of an arbitrary path. Both
   prerequisites are then in place: `/ExtGState` gives overprint a home, and
   item 3 gives patterns their XObject.
6. **Signature timestamping** — proof of *when*. Ships as `tincture_tsa`, since
   it needs an HTTP client. Depends on item 3 for the signature appearance a
   PAdES-over-PDF/A document cannot do without.
7. **Complex scripts** — the largest effort, and the narrowest audience unless
   you are targeting those markets.
8. **Reading PDFs** — a sibling library. See [10](#10-reading-pdfs).

The ordering is risk-ascending by design: additive work first, the byte layout
of the serialiser last. Where an item makes a later one cheaper, that is said
rather than left to be rediscovered.

## Where it stands today

Solid: text and vector drawing with alpha and gradients, TrueType/OpenType
embedding with subsetting on
by default, the typography engine (TeX hyphenation, Knuth-Plass line breaking,
GPOS kerning, GSUB ligatures), page templates with pagination, tables, JPEG and
PNG images with alpha, interactive forms with every field type, AES-256
encryption, tagged PDF for accessibility, PDF/A archival output, digital
signatures, links within and between documents, telemetry. No required runtime
dependencies. At 0.3.6: 1,455 tests; coverage: CI fails below 80%, and
measured 89.8% in CI at 0.3.6, a figure that varies by a tenth between identical runs;
Credo `--strict` clean with pre-existing findings in `lib/` exempted inline one
by one and `test/` and `scripts/` exempt from the structural checks, clean
Dialyzer, CI on four Elixir versions.

That covers invoices, statements, reports, letters and contracts — documents a
person reads, keeps, and has to be able to rely on. What follows is what it does
not yet cover.

---

## How this is packaged

**The split rule is dependency footprint, not feature size.** Anything that
would drag a new dependency into the core goes in a satellite package. Anything
pure stays here.

The core — object model, fonts, typography, layout — has zero dependencies, and
that is the promise rather than an accident of the current feature set. It is
also what makes a feature request answerable: "not in core, that would be a
separate package" is an architectural answer, not a refusal. The core stays
small by construction, not by discipline.

| | Needs | Where |
|---|---|---|
| **`tincture`** | nothing | core, forever |
| `tincture_svg` | an XML parser (saxy) | satellite |
| `tincture_markdown` | earmark | satellite |
| `tincture_tsa` | an HTTP client, for RFC 3161 | satellite |
| `tincture_phoenix` | Plug, for `send_pdf/3` and controller helpers | satellite |

`tincture_tsa` is the case that shows why the rule earns its keep: PAdES
long-term validation needs a timestamp authority, and without the split the core
would grow a Finch or a Req to support it. Compression is the mirror image and
stays in core — `:zlib` is OTP, so it costs nothing.

**Do not create satellites speculatively.** Each one appears when its first real
dependency does, and not before. The cost is honest: N packages instead of one,
each carrying a compatibility range against the core. That is a real job, not a
formality.

For a borderline case there is a cheaper middle — an optional dependency with a
`Code.ensure_loaded?/1` guard, which is how `:telemetry` is already carried. One
package, no version matrix, at the price of compile-time conditionals and a
`mix.exs` listing things most users will not install. Fine for one or two
integrations, ugly at five.

### The extension point is the actual work

Satellites must be buildable on the public API. If one needs a private function,
the core has to be bumped for every satellite — which is the version matrix with
none of the benefit, and it is a difficult thing to walk back once published.

The instinct is to define a behaviour for this. It is the wrong instinct, and
worth writing down why, because it will recur.

A behaviour exists so the core can dispatch into code it does not know about.
Every satellite on the list above is a **caller**, not an implementer:

```elixir
Tincture.SVG.place(pdf, svg, x, y)   # takes a document, calls public API,
                                     # returns a document
```

Tincture never invokes it. Nothing dispatches. A `@callback draw/3` would
therefore describe a relationship that does not exist — and its second argument
could only be `term()`, which is the tell: a placeholder with a typespec on it
rather than a design.

A behaviour is right for the *reverse* direction, where the core calls out and a
package implements: an image codec registry so someone can add WebP, a font
source, an ICC profile provider. None of the planned satellites are that. When
one is, define it then.

So the real obligation is narrower and more useful: **the public API has to be
sufficient to build a satellite against.** The way to find out is to build one:

> Write `tincture_svg` as a spike on a branch, against the public API only, and
> do not publish it. If it reaches for a private function, that names exactly
> which seam to cut and what shape it should be. If it does not, the answer was
> "no extension point needed", learned for free.

Publishing a guessed behaviour costs more than that spike, because it invites
someone to implement the wrong thing. Marking one "experimental" does not help:
that reads as binding to everyone except its author.

Two things already bear on this. `Layout.Template.parse_xml/1` uses `:xmerl`,
which is OTP — so XML in core costs nothing, and `tincture_svg` is a judgement
about wanting a streaming parser rather than a dependency the rule forces out.
And the Markdown showcase (`lib/tincture/showcase/markdown_doc.ex`) hand-rolls a
small regex markdown parser; it is `@moduledoc false`, so it commits to nothing
publicly, and it should stay that way — that parser is the seed of
`tincture_markdown`, not of a core API.

---

## 1. Accessibility — tagged PDF (PDF/UA)

**Status:** `examples/output/accessible.pdf` passes veraPDF 1.30.2 (PDF/UA-1
profile) in CI on every commit; at 0.3.6: 106 of 106 rules, 1698 of 1698
checks. PAC
2026.1 audit, 2026-10-19, on the files at `4a75f1e`: PDF/UA 0 errors, 0
warnings — for this document and the four other PDF/UA examples.

Reproduce it with:

    verapdf --flavour ua1 examples/output/accessible.pdf

Compliance belongs to a *document*, not a library: Tincture gives you the tools
to produce a conforming file, and whether yours conforms depends on how you tag
it. What validation establishes is narrower: for the constructs the validated
documents emit, correct usage is not blocked by a defect in the output. It
found three such defects. It says nothing about constructs those documents do
not emit, and form fields are a known case where correct usage is blocked
(below).

`Tincture.tag/4` produces the structure tree, marked content around the
operators that draw each element, the parent tree linking them, `/MarkInfo`,
`/Lang`, alternative text and `/Scope` on header cells. That is the layer a
screen reader reads, and it is what Section 508, EN 301 549 and equivalent
rules are asking for.

- ~~**Tagging the remaining layout helpers.**~~ **Done.** `Layout.Box` tags
  flowed text, `Layout.Template` marks its header and footer as artifacts, and
  `Layout.Table` already emitted its own structure. All three take `:tag`,
  defaulting to `:auto` — they mark up only when the caller is already tagging,
  since a tree holding one element and nothing else reads worse than none.
- ~~`/Tabs /S` on pages.~~ **Done**, on tagged pages: tab order follows the
  structure tree rather than the order annotations happen to have been added
  in. Untagged pages do not carry it, having no structure to follow.
- ~~**Automatic alt text prompting.**~~ **Done**, and stronger than prompting.
  A `:figure` without `:alt` is a violation, `Tincture.pdf_ua_violations/1`
  lists them, and `export/2` refuses — the same treatment a false PDF/A claim
  gets, for the same reason. A reader that finds a figure it cannot describe is
  worse off than one that finds no tag at all. `enforce: false` still escapes.

- ~~**Link annotations reachable from the structure tree.**~~ **Done.** A
  `/Link` element now references its annotation through `/OBJR`, the annotation
  carries `/StructParent`, and `/ParentTree` resolves both. Every tagged
  document before 0.3.0 was missing this.
- ~~**Link alternative text.**~~ **Done.** `:contents` on `link/7` and
  `text_link/6`, required in a tagged document, with no default. veraPDF's rule
  (PDF/UA-1 7.18.5-2) checks only that a description is present, so one
  generated from the link text would pass it and help nobody.

What remains:

- ~~**The corpus audit.**~~ **Done**, and it found two more defects. 19 of 37
  structure types are exercised by the validated documents; the other 18 have
  never been through a validator. The README lists them, and a test fails when
  the set drifts. Closing the gap is ongoing work — the audit was the part that
  had never been done.
- ~~**`:note` has no `/ID`, and fails clause 7.9.**~~ **Done** in 0.3.1. The
  identifier is generated and resolves through a new `/IDTree` on the structure
  tree root. No rule in any of veraPDF 1.30.2's profiles mentions `/IDTree`, so
  no validator run checks it; the test suite does. An `/ID` with no tree is
  unusable rather than merely unverified.
- **Form fields cannot be made PDF/UA conformant.** Clause 7.18.4 requires a
  widget annotation to be nested in a `Form` structure element, and there is no
  such tag. The `/OBJR` machinery links now use is the same machinery this
  needs, so the seam exists; the vocabulary and the association do not.
- ~~**PAC audit.**~~ **Done** on 2026-10-19, with PAC 2026.1, on the five PDF/UA
  examples as committed at `4a75f1e`: PDF/UA 0 errors, 0 warnings on all five.
  veraPDF checks that the structure is *well-formed*; PAC also looks at whether
  it is *usable*, and it found what veraPDF had passed:

  - invalid content streams in the examples — a painting operator with no path
    to paint, which viewers ignore;
  - tagged figures with no bounding box (`/BBox`);
  - inline elements — links, notes, figures — placed directly in a section or
    the document with no `/Placement /Block`, so a reader could not tell they
    are laid out as blocks;
  - examples with headings and no outline to navigate them by;
  - and, in following up, a tag left open across a page change, which splits
    its marked content between two pages.

  All are fixed in 0.3.4, and each now has an assertion that runs in CI. The
  last warns rather than refuses, and becomes an error in 0.4.0 (see below).

  What remains from the audit:

  - Two Quality warnings on `compliant.pdf`: its footnote `Note` is not
    referenced by a `Link`, and contains no `Lbl`. Both are best practice for
    footnotes rather than PDF/UA-1 requirements, and are a known gap.
  - PAC's AI-assisted hints, which are advisory and not repeatable, and so are
    not treated as findings.

  PAC is a free Windows desktop application from axes4 with no command line
  and no Linux build, so it cannot join the automated set the way veraPDF has.
  It has been run once, by hand. A PAC result describes the files it was run
  on; the release checklist keeps it from silently coming to describe others.
- **A tag left open across a page change.** Calling `add_page/1` or
  `set_page/2` while a content tag or an `artifact/2` block is open writes a
  marked-content sequence that begins on one page and ends on another, which a
  content stream cannot hold. Since 0.3.4 it warns, naming the open tag; it
  becomes an error in 0.4.0. A figure closed on another page than it opened on
  gets no `/BBox`, as ISO 32000-1 requires one only for a figure that appears
  in its entirety on a single page.
- **More of what a library can see.** Figure bounding boxes and the placement
  of inline elements at block level are now written automatically, so neither
  is left to the caller. Three rules are checked as violations: a `:figure`
  without `:alt`, a link outside a `:link` element, and a link with no
  `/Contents`. Heading-level order and table header association are the
  candidates left; whether an alternative text is *accurate* is not one a
  library can settle.

## 2. Archival — PDF/A

**Status:** `examples/output/archival.pdf` passes veraPDF 1.30.2 in CI on
every commit; at 0.3.6: PDF/A-2b (144 of 144 rules, 3088 of 3088 checks), PDF/A-2u
(146 of 146 rules, 3700 of 3700 checks) and **PDF/A-2a** (153 of 153 rules,
4009 of 4009 checks) — and the PDF/UA-1 profile at the same time (106 of 106
rules, 2255 of 2255 checks), since 2a is the accessible archival level and
subsumes the tagging requirement. PAC 2026.1 audit, 2026-10-19, on the file at
`4a75f1e`: PDF/UA 0 errors, 0 warnings. PAC does not check PDF/A.

    verapdf --flavour 2a  examples/output/archival.pdf
    verapdf --flavour ua1 examples/output/archival.pdf

`Tincture.set_pdf_a/2` adds what archival validity needs: an sRGB output
intent, XMP carrying the conformance claim, and a file identifier. The ICC
profile is built by `Tincture.PDF.ICC` from published sRGB constants rather
than read from the system or shipped from elsewhere, so a document is
reproducible on any machine.

Output is deterministic: the file identifier is derived from the content and
the profile carries no creation date, so an archived file can be checked
against a rebuild.

What remains:

- ~~**Enforcement.**~~ **Done.** `export/2` refuses to write a conformance
  claim into a document that breaks one, naming every violation. See
  `Tincture.PDF.Archival`. It remains a partial check by construction —
  Tincture sees the document it built, not the file a validator sees — so
  passing it means "nothing Tincture knows of is wrong", not "this is PDF/A".
- **PDF/A-1.** Part 1 is stricter than part 2. It requires an accurate
  `/CIDSet` for every subset CIDFont (veraPDF 1.30.2, PDFA-1B 6.3.5-3), which
  Tincture deliberately does not emit: subsetting can fall back to the whole
  font while the name keeps its subset tag, so an accurate one cannot be
  produced. Part 2 makes `/CIDSet` optional and rejects only an inaccurate one
  (PDFA-2B 6.2.11.4.2-2), which is why omitting it is right there. See the
  0.1.0 entry in [CHANGELOG.md](CHANGELOG.md). Part 1 also forbids
  transparency.
- **CMYK output intents.** The built-in intent is sRGB. Print production
  targeting a CMYK condition needs its own profile, which means accepting one
  from the caller.

## 3. Digital signatures

**Status: done.** `Tincture.sign/3` produces a detached PKCS#7 signature
covering the whole file, in a `/ByteRange` a verifier can reproduce.

Two checks, neither sharing code with the signer:

- the test suite verifies SHA-256, SHA-384 and SHA-512 signatures with an
  independent verifier, and checks that altering the document breaks each;
- CI verifies `examples/output/signed.pdf` with `openssl cms -verify` on every
  commit, and checks that a tampered copy fails. The example's certificate is
  self-signed, so this checks the signature's integrity, not chain trust.

The CI check runs:

    elixir scripts/extract_signature.exs examples/output/signed.pdf tmp/sig
    openssl cms -verify -binary -inform DER -in tmp/sig/signature.der \
      -content tmp/sig/content.bin -noverify -out /dev/null

OTP ships no CMS encoder, so `Tincture.PDF.CMS` builds the `SignedData`
structure in DER directly — still no third-party dependencies, since `:crypto`
and `:public_key` are OTP applications.

Signing breaks the pure-transformation model that holds everywhere else:
a signature covers the finished bytes including where objects landed, so
`export/2` reserves space, measures the real offsets, signs, and patches the
result back without moving anything. See `Tincture.PDF.Sign`.

What remains:

- **Timestamps (RFC 3161).** A signature proves the document has not changed,
  and who signed it as far as the certificate is trusted. It does not prove
  *when*: the time is the signing machine's own claim. Long-term validation
  (PAdES B-LT, B-LTA) needs a timestamp authority, which means an HTTP client —
  so this lands as `tincture_tsa` rather than in the core. See
  [How this is packaged](#how-this-is-packaged). What the core owes it is an
  extension point good enough to build on without reaching for internals.
- **Incremental updates**, without which a document can carry only one
  signature and cannot be counter-signed or amended after signing.
- **Signature appearances.** The widget carries no appearance stream, so a
  signed field is invisible in a static render and a signed document is
  currently rejected by the PDF/A check for that reason. Signed archival
  documents (PAdES over PDF/A) need this.
- **PAdES subfilters.** `/adbe.pkcs7.detached` is the widely supported form;
  `/ETSI.CAdES.detached` is what the European regulation names.

## 4. Colour beyond RGB

**Status: `:device_gray`, `:device_rgb` and `:device_cmyk` only.** No
`/Separation`, no `/DeviceN`, no ICC-based spaces.

Print production needs spot colours and calibrated colour. A brand colour that
must match across a print run cannot be expressed as device CMYK.

Needs: `/Separation` for spot inks, `/DeviceN` for multi-ink, `ICCBased` for
calibrated spaces, and an overprint control (`/ExtGState`, item 5).

## 5. Transparency and shading

**Status: done for alpha and gradients.** `Tincture.set_alpha/2` emits
`/ExtGState` with `/ca` and `/CA`; `linear_gradient/7` and `radial_gradient/7`
emit shading types 2 and 3, with any number of stops.

Both are written inline into the page resource dictionary rather than as
indirect objects, so adding a gradient renumbers nothing and leaves a document
that uses none byte-identical.

What remains:

- **Blend modes.** `/BM` is not set, so everything composites normally.
- **Patterns.** No `/Pattern`, so a gradient cannot yet be used as the fill of
  an arbitrary path — only of a rectangle.
- **Soft masks on drawn content.** `/SMask` still applies to images only.

## 6. Forms, completed

**Status: the field set is complete; appearances are half done.** Text,
checkbox, choice, radio group, push button and signature fields all exist, with
reset, URL and submit actions.

Button-like fields (checkbox, radio, push button) carry generated `/AP`
appearance streams, so they render anywhere — printing, thumbnails,
server-side rasterising — not only in an interactive viewer.

Fields whose appearance is their typed value (text, choice) still rely on
`/NeedAppearances true`. Every mainstream viewer honours it, but a *flattened*
form — one converted to static content — needs those generated too, which means
laying out and clipping the value at export time.

Also missing: JavaScript actions for client-side validation, and per-field
appearance customisation (`/MK` border and background colours).

Field values can only use the standard 14 fonts, because `/DA` resolves against
the AcroForm resource dictionary. Referencing an embedded font there is
possible in principle and is not implemented.

## 7. Complex scripts

**Status: `bidi: :basic` and GSUB ligature substitution only.**

Arabic and the Indic scripts need contextual shaping — glyph selection that
depends on neighbouring characters — plus mark positioning and cursive
attachment. That means implementing the relevant parts of GSUB (types 5–8) and
GPOS (types 3–6), which is a significant body of work and the reason HarfBuzz
exists.

Vertical writing for CJK is a separate gap: no `/WMode`, no vertical metrics
from `vhea`/`vmtx`.

Worth being honest that this is the largest single item on the list, and that
"supports Unicode" is not the same as "typesets Arabic correctly".

## 8. File size and streaming

**Status: absent.** No object streams, no cross-reference streams, no
linearisation.

Every object is written uncompressed into a classic xref table. Object streams
and xref streams (PDF 1.5, 2001) would meaningfully shrink documents with many
small objects. Linearisation ("fast web view") lets a viewer render page one
before the whole file arrives, which matters when documents are served over
HTTP.

All of this stays in core: `:zlib` ships with OTP, so compression costs no
dependency.

Separately, `export/1` builds the entire document in memory. A streaming
export would bound memory for large documents — a thousand-page statement run
currently holds everything at once.

## 9. Operability

- ~~**Telemetry.**~~ **Done.** Three spans — document, page and font embed —
  with duration, byte sizes and document shape. `:telemetry` is optional, so
  the zero-required-dependency claim still holds. See `Tincture.Telemetry`.
- ~~**Links between documents.**~~ **Done** in 0.3.2, closing
  [#1](https://github.com/thatsme/tincture/issues/1). `{:file, path}` and
  `{:file, path, page}` emit a `/GoToR` action resolved relative to the
  document carrying the link, so a set of files that ship together can refer
  to each other. Named destinations are reserved and unimplemented; the page
  index is a promise about a file Tincture never reads, which is the
  limitation to know. Viewer behaviour was observed by hand, not checked in
  CI: at 0.3.2, browser-embedded viewers did not follow these links, and at
  0.3.3 neither did macOS Preview, the default PDF viewer on macOS, which on
  macOS 26.6.2 showed a permission alert and did not open the target. A set of
  documents that relies on these links needs a desktop reader that follows
  them; SumatraPDF is the one observed.
- **Memory profile.** No measured figure for a large document. Worth having
  before the streaming export in [8](#8-file-size-and-streaming), which cannot
  be sized without knowing what a thousand-page run currently holds.

## 10. Reading PDFs

**Status: absent — Tincture is write-only.**

Merging documents, stamping an existing file, filling a form template someone
else produced, extracting text: all common enterprise needs, none possible.

A separate library, though not for the usual reason: reading needs no new
dependency, so the split rule does not force it out. It is a different problem —
parsing arbitrary files someone else produced, defensively — and pulling it into
the core would double the surface a writer has to keep correct.

Listed because evaluators will ask, and "no" is a better answer than silence.

---

## A note on the checked items

Compliance belongs to a *document*, not a library. Tincture provides the tools
to produce a conforming file; whether yours conforms depends on how you use
them. What validation established is narrower and more useful: that correct
usage is not blocked by a defect in the output.

It was worth doing. Running veraPDF and OpenSSL against the examples found five
real defects that 1,200 tests had not — among them every content stream
declaring a `/Length` one byte too large, and table header `/Scope` written
where no reader would look for it. Each is recorded in
[CHANGELOG.md](CHANGELOG.md).

Two of those were things that looked like constraints and turned out to be bugs:
links appeared to be forbidden in archival documents, and checkboxes likewise,
until it emerged that Tincture was omitting an annotation flag in one case and
over-setting `/NeedAppearances` in the other. A rule that bans working features
is a bug in the rule.

## Contributing

Any of these is a reasonable place to start, and the ones with a clear
specification, such as object streams, are the most tractable without deep PDF
background. Open an issue before starting something large so
we can agree the shape.
