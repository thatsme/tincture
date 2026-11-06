# Examples

Runnable scripts, each producing a document in [`output/`](output/) — except
[`remote_links.exs`](remote_links.exs), which produces two, in a directory of
their own, because it is about a link from one file to another. The PDFs are
committed, so you can see what the library produces without running anything.

    mix examples          # run them all
    mix run examples/invoice.exs

Each script embeds a real TrueType font, taken from
[`fonts/`](fonts/) — Liberation Serif and Liberation Sans, under the SIL Open
Font License. They are vendored so the output is identical on every machine: an
embedded font goes into the file byte for byte, so without them running these
scripts elsewhere rewrote every PDF without a single source change.

[`support/fonts.exs`](support/fonts.exs) prefers those, falls back to system
fonts if the directory is missing, and falls back again to the standard 14 if
nothing is found — in which case the document still renders but stops
demonstrating embedding. That last path is what a container without fonts gets,
so CI exercises it:

    TINCTURE_EXAMPLES_NO_FONTS=1 mix examples

---

## [`gradient.exs`](gradient.exs) → [`output/gradient.pdf`](output/gradient.pdf)

A report cover, and the one example that is about how a page *looks* rather than
what it contains: a three-stop vertical gradient behind the title, a radial glow
under the mark, a horizontal gradient rule, and a `DRAFT` watermark at 8%
opacity.

Gradients are paint rather than shapes — `linear_gradient/7` and
`radial_gradient/7` fill the rectangle they are given and ignore the current
fill colour. Alpha is graphics state, so every use here is fenced in
`save_state/1` and `restore_state/1`; without the fence it would apply to
everything drawn afterwards.

## [`invoice.exs`](invoice.exs) → [`output/invoice.pdf`](output/invoice.pdf)

A commercial invoice: filled header band, vector logo, a line-item table with
computed column widths, totals, justified payment terms through the typography
engine, a clickable payment link, and a footer.

Shows:

- **Embedded fonts throughout**, including the justified paragraph. That
  paragraph is the reason this example exists — laying out text in an embedded
  font used to raise `unknown font`, because measurement went through a pure
  function that could only see the standard 14. See `Tincture.Font.Context`.
- **Subsetting**, roughly 75% off each font.
- **Knuth-Plass line breaking** with hyphenation, widow and orphan penalties —
  the same global optimisation TeX uses, rather than greedy first-fit.
- **Paint modes.** `rectangle/6` takes `:fill`, which is newer than it sounds:
  the shape helpers used to stroke unconditionally, and a path-painting
  operator ends the path, so a filled rectangle was impossible.

## [`form.exs`](form.exs) → [`output/form.pdf`](output/form.pdf)

A supplier account application exercising every field type: text (single-line
and multiline), choice, checkbox, radio group, signature and push buttons.

Shows:

- **Radio groups**, the one field that is not a single object. The
  specification models a group as a parent field holding the value with a kid
  widget per button, and a button's export value *is* the name of its "on"
  appearance state.
- **Generated appearance streams.** Every field carries a real `/AP`, so the
  checkboxes, buttons and the dropdowns' values are visible in this static
  render; the signature field, which has no `:label`, has an empty
  appearance. Text and choice values are laid out by Tincture;
  `/NeedAppearances` is not written, so no field depends on an interactive
  viewer to be drawn.
- **Actions**: submit, reset and open-URL.
- Static text in embedded fonts alongside field values in standard ones. A
  text or choice field may also use a registered TrueType or OpenType font; a
  field someone can type into then needs the whole font embedded, with
  `full_font: true` or a font registered with `subset: :none`, and a font
  whose licence allows editable embedding. A push button's caption and a
  signature's label may use a registered font as well; checkboxes and radio
  buttons, which draw no text, use the standard 14.
- **Viewer limitations**, each stated on the function it concerns. PDFium
  (Chrome, Edge) draws characters a field's font cannot encode with an
  unembedded font of its own, even when the field's embedded font has them
  (`text_field/7`). Acrobat Reader shows a dropdown's non-WinAnsi options
  garbled while its list is open (`choice_field/7`), and covers an unsigned
  signature field with its field highlight on screen (`signature_field/7`).

## [`accessible.exs`](accessible.exs) → [`output/accessible.pdf`](output/accessible.pdf)

A quarterly report carrying logical structure: headings to navigate by, a table
whose header cells declare what they govern, alternative text for the chart, and
an explicit reading order.

Nothing in it changes what the page looks like — that is the point. Tagging is
invisible until something needs to *read* the document rather than display it.

Shows:

- **`Tincture.tag/4`**, nesting containers (`:document`, `:section`, `:table`,
  `:tr`) around content elements (`:h1`, `:p`, `:th`, `:td`, `:figure`).
- **`/Scope` on header cells**, which is what lets a reader announce
  "South West, Revenue, 742,300" rather than a bare number.
- **Alternative text** on a figure drawn as vector shapes, which carry no text
  at all — the alt text is the only description that exists.
- **`Tincture.set_language/2`**, without which a screen reader guesses the
  pronunciation.
- **Bookmarks**, one per heading with `add_bookmark/3`, so the document's
  outline offers the same navigation the headings do.

The table comes from `Layout.Table`, which tags itself — rows, cells, header
scope and artifact borders — when the document is being tagged. The row rules
are marked with `Tincture.artifact/2`, so a reader skips them instead of
announcing them as content.

**Validated.** Passes veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit;
at 0.4.1: 106 of 106 rules, 1698 of 1698 checks. PAC 2026.1 audit, 2026-10-19, on the
file at `4a75f1e`: PDF/UA 0 errors, 0 warnings.

    verapdf --flavour ua1 examples/output/accessible.pdf

Of the other examples, `compliant.exs`, `archival.exs`, `archival_form.exs`,
`tagged_form.exs`, `signed_archival.exs` and `remote_links.exs` are tagged and
validated below. The
rest are not tagged, claim no conformance, and are not validated.

## [`compliant.exs`](compliant.exs) → [`output/compliant.pdf`](output/compliant.pdf)

The same subject as `accessible.exs` from the other direction: where that is a
report that happens to be tagged, this is a **template**, with each PDF/UA
requirement called out at the point it is satisfied. Copy it and fill it in.

Covers the requirements the other example does not — lists (`:list`,
`:list_item`, `:label`, `:list_body`, so a reader announces "list, four items"
and can skip it) — alongside headings in order, an artifact rule, a tagged
table, and a figure with alternative text.

Every heading also gets a bookmark, so the outline matches the structure.

The script prints a checklist of each requirement and where it came from.

**Validated.** Passes veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit;
at 0.4.1: 106 of 106 rules, 2864 of 2864 checks. PAC 2026.1 audit, 2026-10-19, on the
file at `4a75f1e`: PDF/UA 0 errors, 0 warnings, with two Quality warnings on
its footnote — the `Note` is not referenced by a `Link` and has no `Lbl` —
which are best practice rather than PDF/UA-1 requirements.

    verapdf --flavour ua1 examples/output/compliant.pdf

## [`archival.exs`](archival.exs) → [`output/archival.pdf`](output/archival.pdf)

A calibration certificate that has to outlive the software that made it,
claiming **PDF/A-2a** — the accessible archival level, which subsumes 2u (text
extractable) and 2b (visual reproduction preserved) and additionally requires
tagging. So one document conforms to both PDF/A and PDF/UA at once.

Shows:

- **`Tincture.set_pdf_a/2`**, which adds the sRGB output intent, the XMP
  conformance claim and the file identifier.
- **The built-in ICC profile.** PDF/A forbids device colour with no stated
  meaning — `1 0 0 rg` alone means "as red as this device gets" — so an output
  intent has to say which red. `Tincture.PDF.ICC` builds one rather than
  depending on a profile being installed.
- **Why the standard 14 fonts are unusable here**: PDF/A requires every font to
  be embedded, and those are referenced by name for the reader to resolve,
  which is the outside dependency the format exists to remove.
- **Bookmarks** for each heading, as in the other tagged examples.

Output is deterministic — the file identifier comes from the content and the
ICC profile carries no creation date — so an archived file can be checked
against a rebuild.

**Validated.** Passes veraPDF 1.30.2 in CI on every commit at four
flavours; at 0.4.1:

| Profile | Rules | Checks |
|---|---|---|
| PDF/A-2b | 144 of 144 | 3088 of 3088 |
| PDF/A-2u | 146 of 146 | 3700 of 3700 |
| PDF/A-2a | 153 of 153 | 4009 of 4009 |
| PDF/UA-1 | 106 of 106 | 2255 of 2255 |

PAC 2026.1 audit, 2026-10-19, on the file at `4a75f1e`: PDF/UA 0 errors,
0 warnings. PAC does not check PDF/A.

    verapdf --flavour 2b  examples/output/archival.pdf
    verapdf --flavour 2u  examples/output/archival.pdf
    verapdf --flavour 2a  examples/output/archival.pdf
    verapdf --flavour ua1 examples/output/archival.pdf

## [`archival_form.exs`](archival_form.exs) → [`output/archival_form.pdf`](output/archival_form.pdf)

An instrument loan record: an interactive form in an archival document,
claiming **PDF/A-2a**, which subsumes 2u and 2b and requires tagging, so it is
a PDF/UA-1 document too. It carries one of each field PDF/A allows —
single-line and multiline text, a read-only text field, a combo box, a list
box, a checkbox, a radio group and an unsigned signature field — and no push
button, which a PDF/A document cannot carry.

Shows:

- **A tagged form.** Every widget is owned by a `Form` structure element of
  its own, inside the `:p` that draws the field's label, and every field has
  a `:tooltip`, as in `tagged_form.exs` below. The heading has a bookmark.

- **Fields in an archival document.** Every field carries its own appearance,
  so it displays the same in every viewer and in print, and PDF/A requires
  exactly that of every annotation.
- **Fonts a field draws with are embedded.** The editable fields use a font
  embedded whole (`full_font: true`), so a viewer can draw whatever someone
  types; the read-only field uses a second font, subset to what it draws.
  `export/2` refuses a field that draws text in one of the standard 14.
- **Fields that draw no text name no font.** In a document that declares
  PDF/A, a checkbox, a radio group and an unlabelled signature field carry no
  default appearance (`/DA`), and the form names only the fonts its fields
  draw with, all embedded.
- **A form XObject** for the letterhead, drawn once and placed once.

The script prints a checklist of each requirement and where it came from.

**Validated.** New in 0.4.0. Passes veraPDF 1.30.2 in CI on every commit at
four flavours; at 0.4.1:

| Profile | Rules | Checks |
|---|---|---|
| PDF/A-2b | 144 of 144 | 6800 of 6800 |
| PDF/A-2u | 146 of 146 | 7192 of 7192 |
| PDF/A-2a | 153 of 153 | 7391 of 7391 |
| PDF/UA-1 | 106 of 106 | 1401 of 1401 |

    verapdf --flavour 2b  examples/output/archival_form.pdf
    verapdf --flavour 2u  examples/output/archival_form.pdf
    verapdf --flavour 2a  examples/output/archival_form.pdf
    verapdf --flavour ua1 examples/output/archival_form.pdf

PAC 2026.1 audit, 2026-11-05, on the file at `8bc00fb`: PDF/UA, WCAG,
Quality and the AI-assisted check passed. PAC does not check PDF/A.

**Filled in and saved, it may no longer be PDF/A.** PDF/A describes the file
Tincture writes, not the file after a viewer has filled it in: a viewer that
saves a filled form may remove the PDF/A identification and add objects of
its own. Measured on 2026-11-02, on this example as it was then (PDF/A-2u,
untagged), filled in and saved with Save As in Acrobat Reader
2026.002.22031: Reader kept Tincture's bytes and appended its changes, and
the saved file fails veraPDF 1.30.2 at 2b and 2u on one rule, 6.6.4-1,
because the metadata Reader rewrote has no PDF/A identification. Reader also
added two whole copies of the field font and two fonts it did not embed.
Tincture cannot prevent either. Archive the file as written, or validate the
saved one before relying on it.

## [`tagged_form.exs`](tagged_form.exs) → [`output/tagged_form.pdf`](output/tagged_form.pdf)

A workshop registration form in a tagged document, claiming **PDF/UA-1**. It
carries one of each field type — single-line and multiline text, a combo box,
a list box, a checkbox, a three-button radio group, a push button that opens a
URL, and an unsigned signature field with a label.

Shows:

- **Every widget owned by a `Form` structure element.** In a tagged
  document, each field call appends one `Form` element per widget to the
  element open at the call — one per button for a radio group — and the
  widget points back at it through `/StructParent`, as ISO 14289-1 clause
  7.18.4 requires.
- **Each field inside the `:p` that draws its label.** The `Form` element
  then sits under the element that describes it, and no paragraph holds a
  widget alone: a paragraph with nothing drawn in it is one an accessibility
  checker reports as missing. The push button's paragraph draws "Workshop
  terms", since its caption is part of the widget, not of the page.
- **A `:tooltip` on every field**, written as `/TU`, the name a screen reader
  announces. In a tagged document `export/2` refuses a field without one, and
  a field created outside every `tag/4` scope.
- **Headings that look like headings**, well above the body size, each with a
  bookmark.
- **Fonts for typing.** The fields use a font embedded whole, so a viewer can
  draw whatever someone types; the page text is subset from the same file.
- **A form XObject** for the letterhead, placed once inside a paragraph.

The script prints a checklist of each requirement and where it came from.

**Validated.** Passes veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit;
at 0.4.1: 106 of 106 rules, 1411 of 1411 checks. New in 0.4.0. A CI step
also traces, in the file's bytes, that every widget's `Form` element and
`/StructParent` point at each other (`scripts/trace_widget_ownership.py`).
PAC 2026.1 audit, 2026-11-05, on the file at `8bc00fb`: PDF/UA, WCAG and
Quality passed; PAC's AI-assisted check reported one heading as possibly a
paragraph, an advisory hint.

In Acrobat Reader, the field highlight covers an unsigned signature field on
screen, so its label shows in print; `signature_field/7` describes it.

    verapdf --flavour ua1 examples/output/tagged_form.pdf

## [`signed.exs`](signed.exs) → [`output/signed.pdf`](output/signed.pdf)

A supply agreement carrying a digital signature over the whole file. Mints a
throwaway self-signed certificate so it runs anywhere.

Shows:

- **`Tincture.sign/3`**, and why signing is different: the signature covers the
  finished bytes, so it cannot be computed until the file exists and then has to
  be written back into it without moving anything.
- **The `/ByteRange`**, printed by the script — the whole file except the
  `<...>` holding the signature itself.

Extract and check it yourself, from the repository root:

    elixir scripts/extract_signature.exs examples/output/signed.pdf tmp/sig
    openssl cms -verify -binary -inform DER -in tmp/sig/signature.der \
      -content tmp/sig/content.bin -noverify -out /dev/null

`-noverify` skips chain trust, which a self-signed certificate cannot pass; the
signature and the content digest are still checked. CI runs the same commands
on every commit.

A self-signed certificate proves the document has not changed; it says nothing
about *who* signed it that you did not already take on faith. And with no
timestamp authority, nothing proves *when*.

## [`signed_archival.exs`](signed_archival.exs) → [`output/signed_archival.pdf`](output/signed_archival.pdf)

A calibration acceptance that is archival, accessible and signed at once:
it claims **PDF/A-2a**, which subsumes 2u and 2b and requires tagging, so it
is a PDF/UA-1 document too, and it carries a digital signature over the whole
file. Like `signed.exs`, it mints a throwaway self-signed certificate.

Shows:

- **A signature in an archival document.** PDF/A-2 accepts a detached PKCS#7
  signature (`/SubFilter /adbe.pkcs7.detached`) whose byte range covers the
  whole file but the signature itself, with the signer's certificate and a
  single signer.
- **A visible, labelled signature field.** Its label, "Approved: M. Kaur",
  is drawn in its own appearance in an embedded font, as PDF/A requires of
  every font a page draws with.
- **The signature widget in the structure tree.** It is owned by a `Form`
  element inside the paragraph that draws its label, and its `:tooltip` is
  the name a screen reader announces.
- **Headings that look like headings**, each with a bookmark.

The script prints a checklist of each requirement and where it came from. CI
verifies the signature with openssl, as it does `signed.pdf`'s, and traces
the widget's ownership in the file's bytes.

**Validated.** New in 0.4.0. Passes veraPDF 1.30.2 in CI on every commit at
four flavours; at 0.4.1:

| Profile | Rules | Checks |
|---|---|---|
| PDF/A-2b | 144 of 144 | 1538 of 1538 |
| PDF/A-2u | 146 of 146 | 1842 of 1842 |
| PDF/A-2a | 153 of 153 | 1997 of 1997 |
| PDF/UA-1 | 106 of 106 | 946 of 946 |

    verapdf --flavour 2b  examples/output/signed_archival.pdf
    verapdf --flavour 2u  examples/output/signed_archival.pdf
    verapdf --flavour 2a  examples/output/signed_archival.pdf
    verapdf --flavour ua1 examples/output/signed_archival.pdf

veraPDF's three PDF/A-2 signature rules (ISO 19005-2 clause 6.4.3) each run
one check on it, and pass: the byte range covers the whole file but the
signature, the signature carries the signer's certificate, and there is a
single signer. PAC 2026.1 audit, 2026-11-05, on the file at `56bae06`:
PDF/UA, WCAG, Quality and the AI-assisted check passed. Acrobat Reader
2026.002.22031 lists the signature and reports that the document has not
been modified since it was signed; it reports the signer's identity as
unknown, as it must for a self-signed certificate.

Like `archival_form.pdf`, its PDF/A claim describes the file as written: a
viewer that saves it again may remove the PDF/A identification and add
objects of its own.

## [`remote_links.exs`](remote_links.exs) → [`output/linked/`](output/linked/)

The only example that writes more than one file:

```
output/linked/
    Main-report.pdf
    Attached documents/
        Appendix-A.pdf
```

A report with links into an appendix that travels beside it — three into named
pages, one to the appendix as a whole. `{:file, path, page}` emits a `/GoToR`
action whose path the reader resolves against the document carrying the link,
so the pair can be moved, zipped or handed over as a set and still resolve.

Both halves are tagged, each with a bookmark per heading, and both pass
veraPDF 1.30.2 (PDF/UA-1 profile) in CI on every commit; at 0.4.1:
`Main-report.pdf` 106 of 106 rules, 830 of 830 checks; `Appendix-A.pdf` 106 of 106 rules, 3761 of
3761 checks. PAC 2026.1 audit, 2026-10-19, on the files at `4a75f1e`: PDF/UA 0
errors, 0 warnings on both. A report that is accessible pointing at an
appendix that is not makes a set half-readable, with no way for a reader to
tell before opening it.

Two things to know before relying on this, both shown in the script:

- **The page number is a promise about a file Tincture never reads.** Nothing
  checks it. Regenerate the appendix with an extra page near the front and
  every link into it is silently off by one. Named destinations would survive
  that; they are reserved and unimplemented.
- **Some desktop readers follow these links; browser-embedded viewers
  generally do not**, refusing local-file navigation as policy. Observed by
  hand, not checked in CI: at 0.3.2, SumatraPDF followed them, Edge rendered
  the link and did nothing on click, and Firefox's viewer did not act on them;
  at 0.3.3, macOS Preview, the default PDF viewer on macOS, showed a permission
  alert on click and did not open the target (macOS 26.6.2). Open the pair in
  a desktop reader that follows cross-file links; SumatraPDF is the one
  observed.

## [`telemetry.exs`](telemetry.exs) → [`output/telemetry.pdf`](output/telemetry.pdf)

Three pages of justified text, with the telemetry events printed as they fire:

```
  font Body      0.38ms  370.7kB -> 83.7kB (77.4% smaller, subset: used_text)
  page 1         0.02ms    3.6kB of content, 75 ops
  page 2         0.16ms    7.3kB of content, 150 ops
  page 3         0.05ms   10.9kB of content, 225 ops
document         5.67ms  106.5kB
  pages 3 · fields 0 · fonts 2 · images 0
```

Shows the three spans — document, page and font — and how to read them. See
`Tincture.Telemetry`. `:telemetry` is an optional dependency; without it the
event calls compile away and the script says so.

## [`stamp.exs`](stamp.exs) → [`output/stamp.pdf`](output/stamp.pdf)

A purchase order with an approval stamp, drawn once with `form_xobject/5` and
placed four times with `place_form_xobject/5`: at full size, at half scale,
fitted to a width, and again on the second page. The file holds the stamp as
one object; each placement is a few bytes of positioning that refer to it.

The stamp sets its own colour, line width and transparency inside its
definition. A form XObject draws with whatever graphics state is in effect
where it is placed, except what it sets itself, so a stamp that set no colour
would take the colour of the page around it.

It makes no conformance claim: the document is untagged.
