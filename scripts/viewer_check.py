r"""Check form field appearances in PDFium, the engine of Chrome and Edge.

    python -I scripts/viewer_check.py OUT_DIR FILE.pdf [FILE.pdf ...]

For each file, three checks, each printed as PASS or FAIL; the exit status is
1 if any fails.

1. Structure: no /NeedAppearances, and every text and choice widget has an
   /AP whose /N is a stream.
2. Drawn from the file's own appearances: page 1 rendered by PDFium is
   identical to the same page rendered from a copy with every text and choice
   value (/V, /DV) removed. A viewer that regenerated appearances from the
   values would draw the copy's fields empty.
3. A fill keeps the form's font: the first editable single-line text field
   whose /DA font is a standard-14 font in /DR is filled the way a person
   types into it (FORM_ReplaceSelection through the form-fill environment),
   the document is saved, and the saved /AP of that field must draw its text
   with that /DR font, under the same name, in WinAnsi bytes.

What PDFium does with characters the field's font cannot encode - it adds an
unembedded font of its own - is a known viewer limitation, and is not checked.

Renders and the filled file are written to OUT_DIR.
"""
import ctypes
import io
import os
import re
import sys

import pikepdf
import pypdfium2 as pdfium
import pypdfium2.raw as c
from PIL import ImageChops
from pypdfium2.version import PDFIUM_INFO, PYPDFIUM_INFO

FILL = "Größe"
FILL_WINANSI = b"Gr\xf6\xdfe"
STANDARD_14 = {
    "/Helvetica", "/Helvetica-Bold", "/Helvetica-Oblique", "/Helvetica-BoldOblique",
    "/Times-Roman", "/Times-Bold", "/Times-Italic", "/Times-BoldItalic",
    "/Courier", "/Courier-Bold", "/Courier-Oblique", "/Courier-BoldOblique",
    "/Symbol", "/ZapfDingbats",
}
FLAG_READ_ONLY, FLAG_MULTILINE, FLAG_PASSWORD = 1, 4096, 8192

failures = []


def report(ok, name, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}{('  ' + detail) if detail else ''}")
    if not ok:
        failures.append(name)


def variable_text_widgets(pdf):
    for page in pdf.pages:
        for annot in page.get("/Annots", []):
            if annot.get("/Subtype") == "/Widget" and annot.get("/FT") in ("/Tx", "/Ch"):
                yield annot


def check_structure(path, label):
    with pikepdf.open(path) as pdf:
        acro = pdf.Root.get("/AcroForm", {})
        report("/NeedAppearances" not in acro, f"{label}: no /NeedAppearances")
        missing = [str(w.get("/T")) for w in variable_text_widgets(pdf)
                   if not isinstance(w.get("/AP", {}).get("/N"), pikepdf.Stream)]
        count = len(list(variable_text_widgets(pdf)))
        report(count > 0 and not missing, f"{label}: /AP /N stream on every text and choice widget",
               f"{count} widgets" + (f", missing: {missing}" if missing else ""))


def render(source):
    doc = pdfium.PdfDocument(source)
    doc.init_forms()
    image = doc[0].render(scale=2, may_draw_forms=True).to_pil().convert("RGB")
    doc.close()
    return image


def check_drawn_from_file(path, label, out_dir):
    with pikepdf.open(path) as pdf:
        for widget in variable_text_widgets(pdf):
            for key in ("/V", "/DV"):
                if key in widget:
                    del widget[key]
        buffer = io.BytesIO()
        pdf.save(buffer)
    original, stripped = render(path), render(buffer.getvalue())
    original.save(os.path.join(out_dir, f"{label}-render.png"))
    box = ImageChops.difference(original, stripped).getbbox()
    report(box is None, f"{label}: page drawn from the file's appearances, not regenerated",
           "" if box is None else f"differs within {box}")


def wide(text):
    data = (text + "\0").encode("utf-16-le")
    buffer = ctypes.create_string_buffer(data, len(data))
    return ctypes.cast(buffer, c.FPDF_WIDESTRING), buffer


def field_name(form, annot):
    size = c.FPDFAnnot_GetFormFieldName(form, annot, None, 0)
    buffer = ctypes.create_string_buffer(size)
    c.FPDFAnnot_GetFormFieldName(form, annot, ctypes.cast(buffer, ctypes.POINTER(c.FPDF_WCHAR)), size)
    return buffer.raw[: size - 2].decode("utf-16-le")


def fill_target(path):
    with pikepdf.open(path) as pdf:
        fonts = pdf.Root.AcroForm.DR.Font
        for widget in variable_text_widgets(pdf):
            flags = int(widget.get("/Ff", 0))
            if widget.FT != "/Tx" or flags & (FLAG_READ_ONLY | FLAG_MULTILINE | FLAG_PASSWORD):
                continue
            font = "/" + bytes(widget.DA).decode("latin-1").split()[0].lstrip("/")
            if font in fonts and fonts[font].get("/BaseFont") in STANDARD_14:
                return str(widget.T), font, str(fonts[font].BaseFont)
    return None


def check_fill(path, label, out_dir):
    target = fill_target(path)
    if target is None:
        report(False, f"{label}: fill", "no editable single-line standard-14 text field")
        return
    name, font, base_font = target

    doc = pdfium.PdfDocument(path)
    doc.init_forms()
    form, page = doc.formenv.raw, doc[0]
    filled = False
    for index in range(c.FPDFPage_GetAnnotCount(page.raw)):
        annot = c.FPDFPage_GetAnnot(page.raw, index)
        if c.FPDFAnnot_GetSubtype(annot) == c.FPDF_ANNOT_WIDGET and field_name(form, annot) == name:
            c.FORM_SetFocusedAnnot(form, annot)
            c.FORM_SelectAllText(form, page.raw)
            text, keep = wide(FILL)
            c.FORM_ReplaceSelection(form, page.raw, text)
            filled = bool(c.FORM_ForceToKillFocus(form))
        c.FPDFPage_CloseAnnot(annot)
    saved = os.path.join(out_dir, f"{label}-filled.pdf")
    doc.save(saved)
    page.close()
    doc.close()

    with pikepdf.open(saved) as pdf:
        widget = next(w for w in variable_text_widgets(pdf) if str(w.T) == name)
        stream = widget.AP.N
        content = stream.read_bytes()
        used = set(re.findall(rb"/([^\s/\[\]<>()]+)\s+[\d.]+\s+Tf", content))
        resources = stream.get("/Resources", {}).get("/Font", {})
        dr = pdf.Root.AcroForm.DR.Font
        wrong = [u.decode() for u in used
                 if "/" + u.decode() not in dr
                 or resources.get("/" + u.decode(), {}).get("/BaseFont") != dr["/" + u.decode()].get("/BaseFont")]
        report(filled and used == {font.lstrip("/").encode()} and not wrong and FILL_WINANSI in content,
               f"{label}: a PDFium fill of {FILL!r} into {name!r} draws with the /DR font {font} ({base_font})",
               f"fonts used: {sorted(u.decode() for u in used)}")


def main():
    out_dir, *paths = sys.argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"pypdfium2 {PYPDFIUM_INFO}, PDFium {PDFIUM_INFO}, pikepdf {pikepdf.__version__}")
    for path in paths:
        label = os.path.splitext(os.path.basename(path))[0]
        check_structure(path, label)
        check_drawn_from_file(path, label, out_dir)
        check_fill(path, label, out_dir)
    if failures:
        print(f"{len(failures)} check(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
