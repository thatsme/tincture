# Roadmap

What Tincture would need to be a defensible choice for enterprise document
generation, and roughly in what order.

Everything listed as missing here was checked against the source, not assumed.
Where something is partially present that is said explicitly, because "we have
forms" and "we have the forms you need" are different claims.

## Where it stands today

Solid: text and vector drawing, TrueType/OpenType embedding with subsetting on
by default, the typography engine (TeX hyphenation, Knuth-Plass line breaking,
GPOS kerning, GSUB ligatures), page templates with pagination, tables, JPEG and
PNG images with alpha, interactive forms with every field type, AES-256
encryption, tagged PDF for accessibility, PDF/A archival output, digital
signatures, telemetry. No required runtime dependencies. 1,224 tests, 88% coverage, clean Credo and Dialyzer, CI
on four Elixir versions.

That covers invoices, statements, reports, letters and contracts — documents a
person reads. What follows is what it does not yet cover.

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

What remains:

- **Tagging the remaining layout helpers.** `Layout.Table.render/6` now emits
  its own structure. `Layout.Template` and `Layout.Box` do not.
- **PAC.** Only veraPDF has been used. PAC applies some checks veraPDF does not.
- `/Tabs /S` on pages, so tab order follows structure rather than annotation
  order.
- Automatic alt text prompting: nothing forces a `:figure` to carry `:alt`,
  and a figure without it is invisible to a reader.

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
  (PAdES B-LT, B-LTA) needs a timestamp authority, which means an HTTP client
  and therefore a dependency decision.
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

**Status: absent.** No `/ExtGState`, no `/Shading`, no `/Pattern`.

PNG alpha is supported via `/SMask` on images, but there is no way to set
opacity on drawn content, no blend modes, and no gradients. Any design-led
document — a report cover, a marketing page — will want at least gradients and
constant alpha.

Comparatively small and self-contained: `/ExtGState` for `/CA` and `/ca`,
shading types 2 and 3 for axial and radial gradients.

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

Separately, `export/1` builds the entire document in memory. A streaming
export would bound memory for large documents — a thousand-page statement run
currently holds everything at once.

## 9. Operability

**Status: absent.**

- ~~**Telemetry.**~~ **Done.** Three spans — document, page and font embed —
  with duration, byte sizes and document shape. `:telemetry` is optional, so
  the zero-required-dependency claim still holds. See `Tincture.Telemetry`.
- **Benchmarks against alternatives.** The benchmark suite guards against
  regression but does not compare with ChromicPDF or elixir-pdf, so there is
  no answer to "how fast is it".
- **Memory profile.** No measured figure for a large document.

Small, and disproportionately useful for adoption.

## 10. Reading PDFs

**Status: absent — Tincture is write-only.**

Merging documents, stamping an existing file, filling a form template someone
else produced, extracting text: all common enterprise needs, none possible.

This is arguably a separate library. Listed because evaluators will ask, and
"no" is a better answer than silence.

---

## Suggested order

1. ~~Telemetry~~ — done. **Benchmarks against alternatives** remain.
2. **Transparency and shading** — small, self-contained, visible.
3. ~~Tagged PDF~~ — done and validated against veraPDF.
4. ~~PDF/A~~ — done and validated at 2a, alongside PDF/UA-1.
5. ~~Digital signatures~~ — done. **Timestamping and incremental updates** remain.
6. **Object and xref streams** — file size.
7. **Forms completed** — appearance streams overlap with 5.
8. **Colour** — needed for print production specifically.
9. **Complex scripts** — largest effort, narrowest audience unless targeting
   those markets.
10. **Reading** — probably a sibling library.

## Contributing

Any of these is a reasonable place to start, and the ones with a clear
specification (shading, `/ExtGState`, object streams) are the most tractable
without deep PDF background. Open an issue before starting something large so
we can agree the shape.
