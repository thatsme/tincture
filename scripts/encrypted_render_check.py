r"""Check that an encrypted document draws exactly as its unencrypted twin in
PDFium (Chrome, Edge), through pypdfium2.

    python -I scripts/encrypted_render_check.py PLAIN.pdf ENCRYPTED.pdf [PASSWORD]

Both files come from scripts/viewer_encrypted.exs: one document, written once
without encryption and once with it. Each page of both is rendered at scale 2
with form fields drawn, and the encrypted file is opened with PASSWORD (default
"p"). Every page must give identical pixels, and the encrypted file must have
the same number of pages. A stream PDFium cannot decrypt - an image, a form
XObject, a field's appearance - draws as nothing, or as noise, and the pixels
differ.

Prints PASS or FAIL per page; the exit status is 1 if any page fails.
"""

import sys

import pypdfium2 as pdfium
from pypdfium2.version import PDFIUM_INFO, PYPDFIUM_INFO


def pages(path, password=None):
    doc = pdfium.PdfDocument(path, password=password)
    doc.init_forms()
    return [doc[i].render(scale=2, may_draw_forms=True).to_pil().convert("RGB") for i in range(len(doc))]


def main(argv):
    plain_path, encrypted_path = argv[1], argv[2]
    password = argv[3] if len(argv) > 3 else "p"
    print(f"pypdfium2 {PYPDFIUM_INFO}, PDFium {PDFIUM_INFO}")

    plain = pages(plain_path)
    encrypted = pages(encrypted_path, password)
    failed = False

    if len(plain) != len(encrypted):
        print(f"FAIL  {len(plain)} pages unencrypted, {len(encrypted)} encrypted")
        return 1

    for number, (a, b) in enumerate(zip(plain, encrypted), start=1):
        if a.size != b.size:
            print(f"FAIL  page {number}: {a.size} unencrypted, {b.size} encrypted")
            failed = True
            continue

        left, right = a.tobytes(), b.tobytes()
        differing = sum(1 for i in range(0, len(left), 3) if left[i:i + 3] != right[i:i + 3])

        if differing == 0:
            print(f"PASS  page {number}: the encrypted file draws exactly as the unencrypted one "
                  f"({a.size[0]} x {a.size[1]})")
        else:
            print(f"FAIL  page {number}: {differing} of {a.size[0] * a.size[1]} pixels differ "
                  f"between the unencrypted and the encrypted file")
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
