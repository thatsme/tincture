# Roadmap

What Tincture would need to be a defensible choice for enterprise document
generation, and roughly in what order.

Nothing here is assumed. Where something is missing it was checked against the
source; where something is claimed done it was checked against a validator.
Partial support is said to be partial, because "we have forms" and "we have the
forms you need" are different claims.

## At a glance

**Done and independently verified**

| | |
|---|---|
| Accessibility — PDF/UA-1 | veraPDF, 106/106 rules ([1](#1-accessibility--tagged-pdf-pdfua)) |
| Archival — PDF/A-2b, 2u, 2a | veraPDF, up to 153/153 rules ([2](#2-archival--pdfa)) |
| Digital signatures | `openssl cms -verify` ([3](#3-digital-signatures)) |
| Telemetry | ([9](#9-operability)) |

**Next, roughly in order**

1. ~~**Transparency and shading**~~ — **done.** Constant alpha and axial and
   radial gradients. See [5](#5-transparency-and-shading); blend modes and
   patterns remain.
2. **Accessibility completed** — tagging for `Layout.Template` and
   `Layout.Box`, `/Tabs /S`, and an audit against PAC as well as veraPDF.
   Additive, and the last of the PDF/UA story.
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
dependencies. 1,320 tests, 89.6%
coverage, clean Credo and Dialyzer, CI on four Elixir versions.

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
separate package" is an architectural answer, not a refusal. Il nucleo resta
piccolo per costruzione, non per disciplina.

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

**Status: verified compliant.** `examples/output/accessible.pdf` passes
veraPDF 1.30.2 against the PDF/UA-1 profile — 106 of 106 rules, 1701 of 1701
checks, `isCompliant="true"`.

Reproduce it with:

    verapdf --flavour ua1 examples/output/accessible.pdf

Compliance belongs to a *document*, not a library: Tincture gives you the tools
to produce a conforming file, and whether yours conforms depends on how you tag
it. What the library guarantees is that correct usage is not blocked by a defect
in the output — which is what validation established, by finding three.

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
  `text_link/6`, required in a tagged document, with no default — a description
  generated from the link text passes a checker and helps nobody.

What remains:

- ~~**The corpus audit.**~~ **Done**, and it found two more defects. 18 of 37
  structure types are exercised by the validated documents; the other 19 have
  never been through a validator. The README lists them, and a test fails when
  the set drifts. Closing the gap is ongoing work — the audit was the part that
  had never been done.
- ~~**`:note` has no `/ID`, and fails clause 7.9.**~~ **Done** in 0.3.1. The
  identifier is generated and resolves through a new `/IDTree` on the structure
  tree root, which no veraPDF profile checks — an `/ID` with no tree is
  unusable rather than merely unverified.
- **Form fields cannot be made PDF/UA conformant.** Clause 7.18.4 requires a
  widget annotation to be nested in a `Form` structure element, and there is no
  such tag. The `/OBJR` machinery links now use is the same machinery this
  needs, so the seam exists; the vocabulary and the association do not.
- **PAC — a one-off audit, not a gate.** Only veraPDF has been used, and it
  cannot be the whole story: it checks that the structure is *well-formed*, not
  that it is *right*. Announcing a decorative rule as a paragraph passes veraPDF
  and fails a reader.

  PAC is the tool that catches that class, and it is a free Windows desktop
  application from axes4 with no CLI and no Linux build. So it cannot join the
  automated set the way veraPDF has: it is a manual pass on a Windows machine,
  worth doing deliberately at intervals rather than planned as a regression
  test. What comes back from it should become assertions here, where they can
  run in CI.
- **More of what a library can see.** Three rules are checked: a `:figure`
  without `:alt`, a link outside a `:link` element, and a link with no
  `/Contents`. Heading-level order and table header association are the
  candidates left; whether an alternative text is *accurate* is not one a
  library can settle.

## 2. Archival — PDF/A

**Status: verified compliant.** `examples/output/archival.pdf` passes veraPDF
1.30.2 at PDF/A-2b, PDF/A-2u and **PDF/A-2a** — and PDF/UA-1 at the same time,
since 2a is the accessible archival level and subsumes the tagging requirement.

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
- **PDF/A-1.** Part 1 is stricter than part 2 and additionally requires a
  `/CIDSet` for every subset font, which Tincture deliberately does not emit —
  see the note under item 1. It also forbids transparency.
- **CMYK output intents.** The built-in intent is sRGB. Print production
  targeting a CMYK condition needs its own profile, which means accepting one
  from the caller.

## 3. Digital signatures

**Status: done, and verified against OpenSSL.** `Tincture.sign/3` produces a
detached PKCS#7 signature covering the whole file, in a `/ByteRange` a verifier
can reproduce. `examples/output/signed.pdf` verifies with:

    openssl cms -verify -binary -inform DER -in <extracted> -content <byte range>

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
  limitation to know. Browser-embedded viewers do not follow these links.
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

## A note on the verified items

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
specification (shading, `/ExtGState`, object streams) are the most tractable
without deep PDF background. Open an issue before starting something large so
we can agree the shape.
