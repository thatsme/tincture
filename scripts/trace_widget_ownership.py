"""Trace, from a PDF's bytes, that every widget is owned by a Form element.

    python -I scripts/trace_widget_ownership.py FILE.pdf [FILE.pdf ...]

PDF/UA-1 requires every widget annotation of a tagged document to be nested
in a Form structure element (ISO 14289-1 clause 7.18.4). The connection runs
both ways, and a validator reads neither as a whole, so this follows it in the
file's own bytes, not through the test suite's parser. For every widget:

  1. the Form structure element whose /K names it, by object number;
  2. that element's /K, which must be a single /OBJR whose /Obj is the widget;
  3. the widget's /StructParent key;
  4. the /ParentTree entry for that key;
  5. that the entry is the Form element of step 1;
  6. the Form element's /P, and that element's structure type.

It also prints the widget's /Rect and the first text the /P element draws (the
first string shown inside its marked content), so the structure order can be
read against the page and each Form against the label it sits under.

Prints one Markdown table per file, in structure order. Exits 1 if any step
fails or leads elsewhere, or if a file's Form elements and widgets differ in
number. Standard library only; written for the files Tincture produces (one
classic cross-reference table, uncompressed objects, Flate content streams).
"""

import re
import sys
import zlib

OBJ = re.compile(rb"(?m)^(\d+) 0 obj\r?\n(<<.*?>>)\r?\n(stream\r?\n|endobj)", re.S)


def load(data):
    """Every object's dictionary, and the decoded data of each stream."""
    dictionaries, streams = {}, {}
    for match in OBJ.finditer(data):
        number = int(match.group(1))
        dictionaries[number] = match.group(2).decode("latin-1")
        if match.group(3).startswith(b"stream"):
            start = match.end()
            end = data.index(b"endstream", start)
            raw = data[start:end].rstrip(b"\r\n")
            if "/FlateDecode" in dictionaries[number]:
                try:
                    raw = zlib.decompress(raw)
                except zlib.error:
                    pass
            streams[number] = raw.decode("latin-1")
    return dictionaries, streams


def ref(body, key):
    match = re.search(r"/%s (\d+) 0 R" % key, body)
    return int(match.group(1)) if match else None


def integer(body, key):
    match = re.search(r"/%s (\d+)(?! \d+ R)(?![\d])" % key, body)
    return int(match.group(1)) if match else None


def kids(body):
    match = re.search(r"/K \[(.*?)\](?= /| >>)", body)
    return match.group(1).strip() if match else None


def parent_tree(dictionaries):
    root = next(b for b in dictionaries.values() if "/Type /StructTreeRoot" in b)
    nums = re.search(r"/Nums \[(.*)\]", dictionaries[ref(root, "ParentTree")], re.S).group(1)
    return {int(k): v for k, v in re.findall(r"(\d+) (\[[^\]]*\]|\d+ 0 R)", nums)}


def literal(text):
    """A PDF literal string's characters, escapes resolved."""
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            out.append({"n": "\n", "r": "\r", "t": "\t", "(": "(", ")": ")", "\\": "\\"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def to_unicode(cmap):
    """A ToUnicode CMap's code-to-text table, from its bfchar and bfrange."""
    table = {}

    def text(hex_digits):
        return bytes.fromhex(hex_digits).decode("utf-16-be", "replace")

    for block in re.findall(r"beginbfchar(.*?)endbfchar", cmap, re.S):
        for code, value in re.findall(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
            table[int(code, 16)] = text(value)
    for block in re.findall(r"beginbfrange(.*?)endbfrange", cmap, re.S):
        for low, high, value in re.findall(
            r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block
        ):
            start = int(value, 16)
            for offset, code in enumerate(range(int(low, 16), int(high, 16) + 1)):
                table[code] = chr(start + offset)
    return table


def hex_text(hex_digits, font_body, streams):
    """A hex string shown in a Type0 font, read through the font's ToUnicode."""
    cmap = streams.get(ref(font_body, "ToUnicode"), "")
    table = to_unicode(cmap)
    codes = [int(hex_digits[i : i + 4], 16) for i in range(0, len(hex_digits) - 3, 4)]
    return "".join(table.get(code, "?") for code in codes)


def page_fonts(dictionaries, page):
    """The page's font resources, name to object number."""
    fonts = re.search(r"/Font << (.*?) >>", dictionaries[page])
    if not fonts:
        return {}
    return {name: int(n) for name, n in re.findall(r"/(\S+) (\d+) 0 R", fonts.group(1))}


def first_text(dictionaries, streams, element):
    """The first string the element's own marked content shows, if any."""
    body = dictionaries[element]
    k = kids(body) or ""
    mcid = re.match(r"(\d+)\b(?! 0 R)", k)
    page = ref(body, "Pg")
    if not mcid or page is None:
        return ""
    contents = ref(dictionaries[page], "Contents")
    content = streams.get(contents, "")
    match = re.search(r"<</MCID %s>> BDC(.*?)EMC" % mcid.group(1), content, re.S)
    if not match:
        return ""
    marked = match.group(1)
    shown = re.search(r"(?:\(((?:\\.|[^\\)])*)\)|<([0-9A-Fa-f]+)>) Tj", marked)
    if shown and shown.group(1) is not None:
        return literal(shown.group(1))
    if shown:
        # The font in effect is the last one selected before the string.
        before = content[: match.start(1) + shown.start()]
        selected = re.findall(r"/(\S+) [\d.]+ Tf", before)
        font = page_fonts(dictionaries, page).get(selected[-1]) if selected else None
        return hex_text(shown.group(2), dictionaries.get(font, ""), streams)
    if " Do" in marked:
        return "(a form XObject)"
    return "(nothing drawn)"


def field_name(dictionaries, body):
    name = re.search(r"/T \(([^)]*)\)", body)
    if name:
        return name.group(1)
    parent = ref(body, "Parent")
    parent_name = re.search(r"/T \(([^)]*)\)", dictionaries.get(parent, ""))
    state = re.search(r"/AP << /N << /(\S+) ", body)
    return "%s/%s" % (parent_name.group(1) if parent_name else "?", state.group(1) if state else "?")


def trace(path):
    dictionaries, streams = load(open(path, "rb").read())
    widgets = {n: b for n, b in dictionaries.items() if "/Subtype /Widget" in b}
    forms = {
        n: b for n, b in dictionaries.items() if "/Type /StructElem" in b and "/S /Form " in b
    }
    tree = parent_tree(dictionaries)

    owners = {}
    for number, body in forms.items():
        for obj in re.findall(r"/OBJR /Obj (\d+) 0 R", body):
            owners.setdefault(int(obj), []).append(number)

    rows, failed = [], False
    for widget, body in widgets.items():
        problems = []
        owned_by = owners.get(widget, [])
        form = owned_by[0] if len(owned_by) == 1 else None
        if len(owned_by) != 1:
            problems.append("owned by %d Form elements" % len(owned_by))

        single = bool(form) and kids(forms[form]) == "<< /Type /OBJR /Obj %d 0 R >>" % widget
        if form and not single:
            problems.append("/K is not a single /OBJR naming the widget")

        key = integer(body, "StructParent")
        if key is None:
            problems.append("no /StructParent")
        entry = tree.get(key) if key is not None else None
        entry_obj = int(entry.split()[0]) if entry and not entry.startswith("[") else None
        same = form is not None and entry_obj == form
        if key is not None and not same:
            problems.append("/ParentTree %s is %s, not Form %s" % (key, entry, form))

        parent = ref(forms[form], "P") if form else None
        parent_type = re.search(r"/S /(\w+)", dictionaries.get(parent, "")) if parent else None
        label = first_text(dictionaries, streams, parent) if parent else ""
        rect = re.search(r"/Rect \[([^\]]*)\]", body)

        failed = failed or bool(problems)
        rows.append(
            (
                form if form is not None else 10**9,
                [
                    field_name(dictionaries, body),
                    str(widget),
                    str(form),
                    "yes" if single else "NO",
                    str(key),
                    str(entry),
                    "yes" if same else "NO",
                    "%s (%s)" % (parent, parent_type.group(1) if parent_type else "?"),
                    rect.group(1) if rect else "?",
                    label[:40],
                    "; ".join(problems) or "ok",
                ],
            )
        )

    header = [
        "field",
        "widget",
        "1 Form",
        "2 /K = one /OBJR",
        "3 key",
        "4 /ParentTree[key]",
        "5 same Form",
        "6 /P",
        "/Rect",
        "/P's first text",
        "result",
    ]
    count_ok = len(forms) == len(widgets)
    print("%s: %d widgets, %d Form elements%s" % (
        path, len(widgets), len(forms), "" if count_ok else " - COUNTS DIFFER"))
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    for _order, row in sorted(rows, key=lambda r: r[0]):
        print("| " + " | ".join(row) + " |")
    print()
    return not failed and count_ok and len(widgets) > 0


def main(paths):
    sys.stdout.reconfigure(encoding="utf-8")
    results = [trace(path) for path in paths]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
