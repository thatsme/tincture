r"""Check form field appearances in two PDF engines: PDFium (Chrome, Edge),
through pypdfium2, and pdf.js (Firefox), through scripts/viewer_pdfjs.

    python -I scripts/viewer_check.py OUT_DIR FILE.pdf [FILE.pdf ...]

pdf.js runs under Node: the command is `node`, or VIEWER_NODE if set (for
example a `docker run ... node:24 node` prefix where Node is not installed),
and its packages must be installed with `npm ci` in scripts/viewer_pdfjs.

For each file, each check is printed as PASS or FAIL; the exit status is 1
if any fails.

1. Structure: no /NeedAppearances, and every text and choice widget has an
   /AP whose /N is a stream.
2. Drawn from the file's own appearances, in each engine: page 1 rendered is
   identical to the same page rendered from a copy with every text and choice
   value (/V, /DV) removed. An engine that regenerated appearances from the
   values would draw the copy's fields empty.
3. A fill keeps the form's font, in each engine: the first editable
   single-line text field whose /DA font is a standard-14 font in /DR is
   filled with text WinAnsi encodes, the document is saved, and the saved /AP
   of that field must draw it with that /DR font, under the same name, in
   WinAnsi bytes. PDFium is filled the way a person types (FORM_ReplaceSelection
   through the form-fill environment), pdf.js through its annotation storage.
4. pdf.js only: the regenerated appearance uses the field's own font. The
   first editable single-line text field whose /DA font is an embedded Type0
   font is filled with Greek; its saved /AP must draw with that /DR font
   object. PDFium is not held to this: for characters a field's font cannot
   encode, and for Greek even in an embedded font that has them, it adds an
   unembedded font of its own. That is a known viewer limitation.
5. PDFium only: a fill keeps a bordered field's border. The first editable
   single-line text field that declares its border (/MK /BC, /BS /W) is
   filled, and the saved /AP must still paint a path outside its /Tx marked
   content. At least one file in the run must have such a field.

Renders and filled files are written to OUT_DIR.
"""
import ctypes
import io
import json
import os
import posixpath
import re
import shlex
import subprocess
import sys

import pikepdf
import pypdfium2 as pdfium
import pypdfium2.raw as c
from PIL import Image, ImageChops
from pypdfium2.version import PDFIUM_INFO, PYPDFIUM_INFO

WINANSI_FILL = "Größe"
WINANSI_BYTES = b"Gr\xf6\xdfe"
GREEK_FILL = "Ελλάδα β"  # differs from the review document's "Ελλάδα"
STANDARD_14 = {
    "/Helvetica", "/Helvetica-Bold", "/Helvetica-Oblique", "/Helvetica-BoldOblique",
    "/Times-Roman", "/Times-Bold", "/Times-Italic", "/Times-BoldItalic",
    "/Courier", "/Courier-Bold", "/Courier-Oblique", "/Courier-BoldOblique",
    "/Symbol", "/ZapfDingbats",
}
FLAG_READ_ONLY, FLAG_MULTILINE, FLAG_PASSWORD = 1, 4096, 8192
PDFJS = posixpath.join("scripts", "viewer_pdfjs", "pdfjs.mjs")

failures = []


def report(ok, name, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}{('  ' + detail) if detail else ''}")
    if not ok:
        failures.append(name)


def node(*args):
    command = shlex.split(os.environ.get("VIEWER_NODE", "node")) + [PDFJS, *args]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        raise RuntimeError(f"pdf.js {args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def variable_text_widgets(pdf):
    for page in pdf.pages:
        for annot in page.get("/Annots", []):
            if annot.get("/Subtype") == "/Widget" and annot.get("/FT") in ("/Tx", "/Ch"):
                yield annot


def check_structure(path, label):
    with pikepdf.open(path) as pdf:
        acro = pdf.Root.get("/AcroForm", {})
        report("/NeedAppearances" not in acro, f"{label}: no /NeedAppearances")
        widgets = list(variable_text_widgets(pdf))
        missing = [str(w.get("/T")) for w in widgets
                   if not isinstance(w.get("/AP", {}).get("/N"), pikepdf.Stream)]
        report(widgets and not missing, f"{label}: /AP /N stream on every text and choice widget",
               f"{len(widgets)} widgets" + (f", missing: {missing}" if missing else ""))


def without_values(path, out_dir, label):
    copy = posixpath.join(out_dir, f"{label}-novalues.pdf")
    with pikepdf.open(path) as pdf:
        for widget in variable_text_widgets(pdf):
            for key in ("/V", "/DV"):
                if key in widget:
                    del widget[key]
        pdf.save(copy)
    return copy


def render_pdfium(source, png):
    doc = pdfium.PdfDocument(source)
    doc.init_forms()
    doc[0].render(scale=2, may_draw_forms=True).to_pil().convert("RGB").save(png)
    doc.close()


def render_pdfjs(source, png):
    node("render", source, png)


def check_drawn_from_file(engine, render, path, copy, label, out_dir):
    original = posixpath.join(out_dir, f"{label}-{engine}.png")
    stripped = posixpath.join(out_dir, f"{label}-{engine}-novalues.png")
    render(path, original)
    render(copy, stripped)
    a, b = Image.open(original).convert("RGB"), Image.open(stripped).convert("RGB")
    box = ImageChops.difference(a, b).getbbox() if a.size == b.size else (0, 0) + a.size
    report(box is None, f"{label}: {engine} draws the page from the file's appearances, not regenerated",
           "" if box is None else f"differs within {box}")


def fill_target(path, wanted):
    """The first editable single-line text field whose /DA font is `wanted`
    (:standard or :type0): (name, /DA alias, /DR font object)."""
    with pikepdf.open(path) as pdf:
        fonts = pdf.Root.AcroForm.DR.Font
        for widget in variable_text_widgets(pdf):
            flags = int(widget.get("/Ff", 0))
            if widget.FT != "/Tx" or flags & (FLAG_READ_ONLY | FLAG_MULTILINE | FLAG_PASSWORD):
                continue
            alias = "/" + bytes(widget.DA).decode("latin-1").split()[0].lstrip("/")
            if alias not in fonts:
                continue
            font = fonts[alias]
            kind = "type0" if font.get("/Subtype") == "/Type0" else (
                "standard" if font.get("/BaseFont") in STANDARD_14 else None)
            if kind == wanted:
                return str(widget.T), alias
    return None


def wide(text):
    data = (text + "\0").encode("utf-16-le")
    buffer = ctypes.create_string_buffer(data, len(data))
    return ctypes.cast(buffer, c.FPDF_WIDESTRING), buffer


def field_name(form, annot):
    size = c.FPDFAnnot_GetFormFieldName(form, annot, None, 0)
    buffer = ctypes.create_string_buffer(size)
    c.FPDFAnnot_GetFormFieldName(form, annot, ctypes.cast(buffer, ctypes.POINTER(c.FPDF_WCHAR)), size)
    return buffer.raw[: size - 2].decode("utf-16-le")


def fill_pdfium(path, saved, values):
    doc = pdfium.PdfDocument(path)
    doc.init_forms()
    form, page = doc.formenv.raw, doc[0]
    for index in range(c.FPDFPage_GetAnnotCount(page.raw)):
        annot = c.FPDFPage_GetAnnot(page.raw, index)
        if c.FPDFAnnot_GetSubtype(annot) == c.FPDF_ANNOT_WIDGET:
            name = field_name(form, annot)
            if name in values:
                c.FORM_SetFocusedAnnot(form, annot)
                c.FORM_SelectAllText(form, page.raw)
                text, keep = wide(values[name])
                c.FORM_ReplaceSelection(form, page.raw, text)
                c.FORM_ForceToKillFocus(form)
        c.FPDFPage_CloseAnnot(annot)
    doc.save(saved)
    page.close()
    doc.close()


def ascii_escaped(text):
    """\\uXXXX for anything outside ASCII, so arguments survive every shell."""
    return "".join(ch if ord(ch) < 128 else f"\\u{ord(ch):04x}" for ch in text)


def fill_pdfjs(path, saved, values):
    node("fill", path, saved, *(f"{k}={ascii_escaped(v)}" for k, v in values.items()))


def saved_appearance(saved, name):
    """The fonts the saved /AP of `name` draws with, as {alias: font object
    in its resources}, its /DR, and its content."""
    with pikepdf.open(saved) as pdf:
        widget = next(w for w in variable_text_widgets(pdf) if str(w.T) == name)
        if not isinstance(widget.get("/AP", {}).get("/N"), pikepdf.Stream):
            return None
        stream = widget.AP.N
        content = stream.read_bytes()
        used = {"/" + u.decode() for u in re.findall(rb"/([^\s/\[\]<>()]+)\s+[\d.]+\s+Tf", content)}
        resources = stream.get("/Resources", {}).get("/Font", {})
        dr = pdf.Root.AcroForm.DR.Font
        fonts = {alias: (resources.get(alias), dr.get(alias)) for alias in used}
        same = {alias: _same_font(mine, theirs) for alias, (mine, theirs) in fonts.items()}
        return {"used": used, "same": same, "content": content}


def _same_font(mine, theirs):
    if mine is None or theirs is None:
        return False
    if mine.is_indirect and theirs.is_indirect:
        return mine.objgen == theirs.objgen
    return mine.get("/BaseFont") == theirs.get("/BaseFont") and \
        mine.get("/Encoding") == theirs.get("/Encoding")


def check_fill(engine, fill, path, label, out_dir, kind, text):
    target = fill_target(path, kind)
    if target is None:
        if kind == "standard":
            report(False, f"{label}: {engine} fill", "no editable single-line standard-14 text field")
        return
    name, alias = target
    saved = posixpath.join(out_dir, f"{label}-{engine}-filled-{kind}.pdf")
    fill(path, saved, {name: text})
    found = saved_appearance(saved, name)

    if found is None:
        report(False, f"{label}: {engine} fill of {text!r} into {name!r} keeps the field's own font",
               "no /AP after the fill")
        return

    # The new text must be in the saved appearance, so an engine that kept the
    # old appearance does not pass: WinAnsi bytes for a standard font, the
    # UTF-16 codes Identity-H uses for an embedded one, raw or as hex.
    encoded = WINANSI_BYTES if kind == "standard" else text.encode("utf-16-be")
    redrawn = drawn(found["content"], encoded)
    ok = found["used"] == {alias} and all(found["same"].values()) and redrawn
    report(ok, f"{label}: {engine} fill of {text!r} into {name!r} draws with the field's own /DR font {alias}",
           f"fonts used: {sorted(found['used'])}" + ("" if redrawn else "; the new text is not in the /AP"))


def drawn(content, encoded):
    hexed = encoded.hex().encode()
    return encoded in content or hexed in content.lower()


def bordered_target(path):
    """The first editable single-line text field that declares its border:
    (name, /BS /W), or None."""
    with pikepdf.open(path) as pdf:
        for widget in variable_text_widgets(pdf):
            flags = int(widget.get("/Ff", 0))
            if widget.FT != "/Tx" or flags & (FLAG_READ_ONLY | FLAG_MULTILINE | FLAG_PASSWORD):
                continue
            width = float(widget.get("/BS", {}).get("/W", 0))
            if "/BC" in widget.get("/MK", {}) and width > 0:
                return str(widget.T), width
    return None


def check_border_fill(path, label, out_dir):
    """Whether the file had a bordered field to check."""
    target = bordered_target(path)
    if target is None:
        return False
    name, width = target
    saved = posixpath.join(out_dir, f"{label}-PDFium-filled-bordered.pdf")
    fill_pdfium(path, saved, {name: WINANSI_FILL})
    with pikepdf.open(saved) as pdf:
        widget = next(w for w in variable_text_widgets(pdf) if str(w.T) == name)
        normal = widget.get("/AP", {}).get("/N")
        content = normal.read_bytes() if isinstance(normal, pikepdf.Stream) else b""
    # The marked content a viewer replaces, taken out; what remains is drawn
    # around it, and must paint a path. PDFium paints the border as a frame,
    # two rectangles filled even-odd, rather than stroking it.
    outside = re.sub(rb"/Tx\s+BMC.*?EMC", b"", content, flags=re.S)
    painted = re.search(rb"(^|\s)(S|s|f\*?|F|B\*?|b\*?)(\s|$)", outside) is not None
    report(painted, f"{label}: PDFium fill of {name!r} (border {width:g}) keeps a border in its /AP",
           "" if painted else f"no path painted outside /Tx in the saved /AP ({len(content)} bytes)")
    return True


def main():
    out_dir, *paths = sys.argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"pypdfium2 {PYPDFIUM_INFO}, PDFium {PDFIUM_INFO}, pikepdf {pikepdf.__version__}, "
          f"pdf.js {node('version')}")

    bordered = False
    for path in paths:
        label = os.path.splitext(os.path.basename(path))[0]
        check_structure(path, label)
        copy = without_values(path, out_dir, label)

        for engine, render, fill in (("PDFium", render_pdfium, fill_pdfium),
                                     ("pdf.js", render_pdfjs, fill_pdfjs)):
            check_drawn_from_file(engine, render, path, copy, label, out_dir)
            check_fill(engine, fill, path, label, out_dir, "standard", WINANSI_FILL)

        check_fill("pdf.js", fill_pdfjs, path, label, out_dir, "type0", GREEK_FILL)
        bordered = check_border_fill(path, label, out_dir) or bordered

    report(bordered, "a bordered field was checked", "" if bordered else "no file has one")

    if failures:
        print(f"{len(failures)} check(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
