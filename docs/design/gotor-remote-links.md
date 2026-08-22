# GoToR — links between separate PDF files

Status: designed, unimplemented. Target 0.3.2. Issue
[#1](https://github.com/thatsme/tincture/issues/1).

## The case

A `/GoToR` action is a link from one PDF to a *different* PDF file, optionally
at a given page. It is how a set of documents that ship together — a main
document and a folder of attachments — refer to each other.

The requester's tree looks like this:

```
Main-pdf.pdf
Attached documents/
    Secondary-pdf-1.pdf
    Secondary-pdf-2.pdf
    Secondary-pdf-3.pdf
```

The secondaries are rendered first, the main document last, and the page count
of every document is known at the time the main one is written. Today the whole
set is produced with Chromium and then post-processed with PikePDF, because
Chromium cannot emit relative links between PDFs at all: the `<a>` tags carry a
custom scheme, and a second pass rewrites them into `/GoToR` actions. The goal
is to delete both the browser and the rewriting pass.

Nothing about that flow needs Tincture to read anything. The caller knows the
tree and knows the page counts, which is the whole reason this is a reasonable
feature for a write-only library.

## The bytes

```
/A << /S /GoToR /F (Attached documents/Secondary-pdf-1.pdf) /D [12 /Fit] >>
```

- `/F` is a **file specification in string form**, resolved by the reader
  relative to the referring document.
- `/D` is a destination array. For a remote target the page is a **0-based
  index**, not an indirect reference — the referring document has no object
  numbers for a file it has never read.
- `/NewWindow` is optional and tri-state; see below.

## API

```elixir
@type link_target ::
        {:url, String.t()}
        | {:page, pos_integer()}
        | {:file, String.t()}
        | {:file, String.t(), pos_integer()}
```

`{:file, path}` links to the document; `{:file, path, page}` links to a page
within it. Both `link/7` and `text_link/6` take it, since both funnel into
`PDF.add_link/4`, and both gain a `:new_window` option.

### Page numbers stay 1-based

`{:file, path, 13}` means the thirteenth page and serialises as `/D [12 /Fit]`.

The subtraction lives at the serialisation boundary, in `link_target_entry`,
and nowhere else. Exposing the 0-based value would make "page" mean two
different things depending on the target type, and the resulting off-by-one
would land in a document the author no longer has, pointing at the wrong page
rather than failing visibly.

### `/NewWindow` is a genuine tri-state

`new_window: true` and `new_window: false` both write the key.
Omitting the option omits the key entirely, which is a different instruction
from writing `false`: it leaves the choice to the reader's own preference.
Defaulting to `false` would silently override that preference for every caller
who never thought about it.

## Reserved, not implemented

```elixir
{:file, String.t(), {:named, String.t()}}
```

A tagged tuple in the third position cannot collide with a `pos_integer`, so
named destinations can land later as a pure addition rather than a breaking
change. The shape is reserved now; nothing implements it.

**The reason to care about named destinations is not that someone asked for
them — it is that page indices are brittle.** A `/D [12 /Fit]` is a promise
about the internal structure of another file. Regenerate that secondary with
one extra page near the front and every inbound link is silently off by one,
in a document the author of the link no longer controls. Nothing detects it:
the link still resolves, the file still opens, the reader lands on the wrong
page. A named destination survives repagination because the target document
carries the name.

This is a limitation of the feature as shipped, and belongs in the user-facing
documentation rather than being left for someone to discover. Page indices are
the only supported form in 0.3.2.

## Validation, and why it is stricter here

The two existing targets validate loosely on purpose. `{:page, n}` defers
entirely to export, because linking forward to a page not yet added is the
common case — a table of contents is written before the pages it points at —
and the reference is resolved once every page exists. `{:url, _}` only checks
that the string is non-empty.

A file target resolves nothing, ever. So everything checkable is checked at
normalisation time, in `normalize_link_target/2`:

| Input | Behaviour |
|---|---|
| `page` not a positive integer | reject |
| absolute path | reject — a leading `/` means absolute in a PDF file specification and will not resolve on a reader's machine |
| non-ASCII path | reject — the string form of `/F` cannot express it portably |
| `\` in the path | converted to `/`, and documented |

Backslash conversion is the one silent transformation, and it earns its place:
a path that works on the author's machine and fails on the reader's is exactly
the failure mode worth designing out. Everything else fails loudly, because the
risk in this feature is silence — a link pointing at the wrong page produces a
document that looks correct and is not.

Non-ASCII paths are rejected rather than encoded. The `/Type /Filespec`
dictionary with `/UF` is where the specification has moved and is what would
express them, but it adds value only for those paths. Revisit when one is
actually needed.

## What a remote link inherits

A remote link is still a link, so everything 0.3.0 and 0.3.1 established applies
unchanged:

- **`/OBJR` association.** An annotation created inside `tag(:link, ...)` is
  attached to the enclosing structure element by
  `PDF.associate_annotation/2` (`lib/tincture/pdf.ex:735`). A remote link gets
  this for free, and needs it: PDF/UA does not care where a link points.
- **`/Contents`.** `export/2` refuses a tagged link with no alternate
  description — `:link_without_description` in
  `lib/tincture/pdf/accessibility.ex:124`. A remote link is *more* in need of
  one, not less: "Secondary-pdf-1.pdf" tells a reader nothing, and the target
  is a document they cannot see.

Neither is new work. Both are asserted in the tests anyway, because "it should
follow from existing machinery" is precisely what was believed about link
annotations before 0.3.0.

## PDF/A — settled

**`GoToR` is permitted in PDF/A-2b.** Confirmed by reading veraPDF's validation
profile rather than the standard text or anyone's memory:

`PDF_A/2b/6.5 Action/6.5.1 General/verapdf-profile-6-5-1-t01.xml`

```xml
<id specification="ISO_19005_2" clause="6.5.1" testNumber="1"/>
<test>S == "GoTo" || S == "GoToR" || S == "GoToE" || S == "Thread"
   || S == "URI" || S == "Named" || S == "SubmitForm"</test>
```

The rule is an **allowlist**, and `GoToR` is in it. The forbidden set is
`Launch`, `Sound`, `Movie`, `ResetForm`, `ImportData`, `Hide`, `SetOCGState`,
`Rendition`, `Trans`, `GoTo3DView` and `JavaScript`.

So `PDF.Archival` gains no rule, and this question is closed. A remote
reference does make a document non-self-contained, which sits awkwardly with
the intent of an archival format — but the standard permits it, and the place
to record disagreement with a standard is not a validator rule of one's own.

A validated document must contain a `GoToR` action, or the rule confirming this
never fires against Tincture's output. That is the 0.3.0 lesson, and it applies
directly: a rule with nothing to match counts as passed.

## What this does not do

- **Named destinations.** Shape reserved, nothing implemented.
- **`/Type /Filespec` and `/UF`.** String form only.
- **Embedded files (`/EmbeddedFiles`).** A different feature: embedding a
  document inside another, rather than pointing at one beside it.
- **Reading page counts from existing PDFs.** Tincture is write-only. The
  caller knows the counts.
- **A fit-mode option.** `/Fit` for remote destinations; internal links keep
  `/XYZ null null null` (`lib/tincture/pdf/serialize.ex:1430`). The asymmetry
  is deliberate — the referring document's zoom is not obviously the right
  thing to carry into a file the reader has not opened — and one caller does
  not justify an option.

## The thing that cannot be checked

An internal `{:page, n}` pointing at a page that does not exist raises at
export. A `{:file, path, n}` pointing at a page that does not exist **can never
be detected**, because Tincture never reads the target. `n > 0` is the only
validation that will ever be possible.

This is the strongest argument for stating the brittleness plainly in the
documentation, and for reserving the named-destination shape now.

## Verification

Bytes are not the deliverable; a link a viewer follows is.

1. A hand-written spike, opened in Acrobat and Chromium, from the document's
   own directory and from a copy relocated elsewhere. Relative resolution
   against the referring file is the property that matters, not all viewers
   honour it, and that misbehaviour is what PikePDF is currently working
   around.
2. Exact bytes, including that page 13 yields `/D [12 /Fit]`.
3. The same target through `link/7` and `text_link/6` producing the same
   action.
4. Every rejection, with its message.
5. `/NewWindow` true, false, and absent — the third is the case that rots.
6. A tagged remote link carrying `/Contents` and reachable via `/OBJR`.
7. veraPDF at PDF/A-2b and PDF/UA-1 with a remote link present, in CI, with the
   report read rather than the tick trusted.
8. A two-document example. All eight existing examples write a single file;
   this feature is about a pair, so it is the first that will not.
