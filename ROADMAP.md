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
PNG images with alpha, hyperlinks, interactive forms, AES-256 encryption. No
runtime dependencies. 1,053 tests, 88% coverage, clean Credo and Dialyzer, CI
on four Elixir versions.

That covers invoices, statements, reports, letters and contracts — documents a
person reads. What follows is what it does not yet cover.

---

## 1. Accessibility — tagged PDF (PDF/UA)

**Status: entirely absent.** No `/StructTreeRoot`, no marked content, no
`/Tabs`, no `/Lang`, no alt text.

This is the single largest gap for enterprise and public-sector work, and
usually the one that disqualifies a library outright rather than being
negotiable. Section 508 in the US, EN 301 549 in the EU and equivalent rules
elsewhere require documents a public body publishes to be accessible. An
untagged PDF is a picture of a document to a screen reader.

Needs: a structure tree, marked-content operators around text and figures,
alt text on images, explicit reading order, `/Lang`, and table structure
(`/TH`, `/TD`, header scope).

This is architectural. Marked content has to be emitted as the content stream
is built, so it cannot be bolted on afterwards.

## 2. Archival — PDF/A

**Status: absent.** No `/OutputIntent`, no ICC profiles, no XMP metadata.

PDF/A (ISO 19005) is what records-retention policies specify. It is mostly a
set of constraints rather than new capability: fonts must be embedded (already
true), an output intent with an ICC profile must be present, metadata must be
XMP rather than only the info dictionary, and encryption and external
references are forbidden.

PDF/A-2b is the usual target. PDF/A-2a additionally requires tagging, so it
depends on item 1.

## 3. Digital signatures

**Status: absent.** No `/Sig`, no `/ByteRange`.

Required wherever a document has to be provably unaltered — contracts,
invoices in jurisdictions with e-invoicing mandates, anything with a legal
counterparty.

Needs: a signature field and dictionary, a `/ByteRange` covering the file
either side of the signature, PKCS#7/CMS detached signatures, and ideally
PAdES with an RFC 3161 timestamp for long-term validity. `:public_key` and
`:crypto` provide the primitives, so this stays dependency-free.

The awkward part is that the signature covers bytes of the finished file, so
export has to reserve space, compute the digest, then patch — the first thing
here that cannot be a pure transformation.

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

**Status: partial.** Text fields, checkboxes and choice fields exist. Missing:
radio button groups, push buttons, signature fields, and generated appearance
streams.

Tincture currently sets `/NeedAppearances true` and lets the viewer render
field values. Every mainstream viewer honours this, but some do not, and a
flattened form — one converted to static content — needs real appearance
streams. That work overlaps with item 3, since a signature field is a form
field.

Also missing: JavaScript actions for client-side validation, and form
submission actions.

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

- **Telemetry.** No `:telemetry` events. Enterprises want render duration and
  document size per document, and page-level timing for slow-path diagnosis.
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

1. **Telemetry and benchmarks** — days, and immediately useful.
2. **Transparency and shading** — small, self-contained, visible.
3. **Tagged PDF** — the largest blocker for public-sector work, and
   architectural, so better done before more features build on the content
   stream.
4. **PDF/A** — mostly constraints, and partly depends on 3.
5. **Digital signatures** — self-contained but touches export.
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
