# Renders a PDF page and prints the colour at given points, to check that what
# a content stream says is what a renderer draws.
#
#     python scripts/render_check.py FILE X,Y [X,Y ...]
#
# X and Y are in PDF points, from the bottom left of the first page, as in the
# content stream. Each point prints as "x,y r g b". The page is rendered at 72
# dpi, so one point is one pixel.
#
# It needs PyMuPDF (the `pymupdf` package, MuPDF underneath). It is a local
# check run by hand for a report, not part of CI.

import sys

import pymupdf


def main(argv):
    if len(argv) < 3:
        print(__doc__ or "usage: render_check.py FILE X,Y [X,Y ...]", file=sys.stderr)
        return 2

    path, points = argv[1], argv[2:]
    page = pymupdf.open(path)[0]
    pixmap = page.get_pixmap(dpi=72)
    height = pixmap.height

    for point in points:
        x, y = (int(float(value)) for value in point.split(","))
        r, g, b = pixmap.pixel(x, height - 1 - y)[:3]
        print(f"{x},{y} {r} {g} {b}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
