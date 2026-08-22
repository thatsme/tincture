Code.require_file("support/fonts.exs", __DIR__)

# A pair of documents that link to each other's pages.
#
# Every other example writes one file. This one writes a tree, because the
# feature is about a relationship between files rather than anything inside
# one of them:
#
#     linked/
#         Main-report.pdf
#         Attached documents/
#             Appendix-A.pdf
#
# A /GoToR action names the target with a path relative to the document that
# carries the link, so the pair can be moved, zipped or handed over as a set
# and the links still resolve.
#
# Two things this cannot do, both stated in the documentation and repeated
# here because they decide whether the feature suits you:
#
#   * The page number is a promise about a file Tincture never reads. Nothing
#     checks it. Regenerate the appendix with an extra page near the front and
#     every link into it is off by one, silently.
#   * Desktop readers follow these links. Browser-embedded viewers generally
#     do not - they refuse local-file navigation as policy. Verified while
#     building this: SumatraPDF follows them, Edge renders the link and does
#     nothing, Firefox's viewer does not act on them.

alias Tincture.Typography.RichText

page_w = 595
page_h = 842
margin = 56

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}

appendix_pages = 12
appendix_path = "Attached documents/Appendix-A.pdf"

# Sections the main document links into, by page. The caller knows these
# because the caller generates the appendix - Tincture never reads it back.
sections = [
  {3, "Calibration procedure"},
  {7, "Measurement uncertainty"},
  {11, "Traceability statement"}
]

{base, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

section_for = fn n ->
  Enum.find_value(sections, fn {page, title} -> if page == n, do: title end)
end

# ---------------------------------------------------------------------------
# The appendix, written first. The main document needs its page numbers, and
# in a real pipeline that is the usual order: secondaries first, then the
# document that refers to them.
# ---------------------------------------------------------------------------

# Tagged, like the document that points at it. A main report that is
# accessible and an appendix that is not makes the set half-readable, and the
# reader has no way to know before opening it.
appendix =
  base
  |> Tincture.set_language("en-GB")
  |> Tincture.set_metadata(
    title: "Appendix A — supporting detail",
    author: "Northgate Instruments Ltd",
    subject: "Appendix to the instrument calibration report"
  )
  |> Tincture.tag(:document, fn pdf ->
    Enum.reduce(1..appendix_pages, pdf, fn n, acc ->
      acc = if n == 1, do: acc, else: Tincture.add_page(acc)
      title = section_for.(n)

      acc =
        Tincture.artifact(acc, fn acc ->
          acc
          |> Tincture.set_fill_color(muted)
          |> Tincture.set_font(sans, 8)
          |> Tincture.text_at(
            margin,
            page_h - margin,
            "APPENDIX A — page #{n} of #{appendix_pages}"
          )
        end)

      acc =
        if title do
          Tincture.tag(acc, :h1, fn acc ->
            acc
            |> Tincture.set_fill_color(accent)
            |> Tincture.set_font(sans, 16)
            |> Tincture.text_at(margin, page_h - margin - 44, String.upcase(title))
          end)
        else
          acc
        end

      Tincture.tag(acc, :p, fn acc ->
        acc
        |> Tincture.set_fill_color(ink)
        |> Tincture.set_font(body, 10.5)
        |> Tincture.text_paragraph(
          margin,
          page_h - margin - if(title, do: 80, else: 44),
          RichText.from_plain(
            "This page exists so the main document has somewhere to point. " <>
              "A remote destination is a page index, so what matters is that " <>
              "this is page #{n} and that it stays page #{n}.",
            font: body,
            size: 10.5
          ),
          page_w - margin * 2,
          align: :justified
        )
      end)
    end)
  end)

appendix_out = Examples.Fonts.output_path("linked/#{appendix_path}")
File.write!(appendix_out, Tincture.export(appendix))

# ---------------------------------------------------------------------------
# The main document, which links into the appendix by page.
# ---------------------------------------------------------------------------

main =
  base
  |> Tincture.set_language("en-GB")
  |> Tincture.set_metadata(
    title: "Instrument calibration report",
    author: "Northgate Instruments Ltd",
    subject: "Calibration report with a linked appendix"
  )
  |> Tincture.tag(:document, fn pdf ->
    pdf =
      pdf
      |> Tincture.tag(:h1, fn pdf ->
        pdf
        |> Tincture.set_fill_color(ink)
        |> Tincture.set_font(sans, 20)
        |> Tincture.text_at(margin, page_h - margin, "Calibration report")
      end)
      |> Tincture.tag(:p, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(body, 10.5)
        |> Tincture.text_at(
          margin,
          page_h - margin - 34,
          "Supporting detail is in Appendix A, which travels with this report."
        )
      end)

    # One link per section. Each is created inside tag(:link, ...) and carries
    # :contents, because a remote link is still a link: PDF/UA needs it
    # reachable from the structure tree and needs something to announce. The
    # description says where the link goes - "Appendix-A.pdf" would not.
    pdf =
      sections
      |> Enum.with_index()
      |> Enum.reduce(pdf, fn {{page, title}, index}, acc ->
        y = page_h - margin - 90 - index * 30

        Tincture.tag(acc, :link, fn acc ->
          acc
          |> Tincture.set_fill_color(accent)
          |> Tincture.set_font(sans, 11)
          |> Tincture.text_link(
            margin,
            y,
            "#{title} — Appendix A, page #{page}",
            {:file, appendix_path, page},
            contents: "Appendix A, page #{page}: #{title}"
          )
        end)
      end)

    # No page named, so the reader opens the appendix at its beginning.
    pdf =
      Tincture.tag(pdf, :link, fn pdf ->
        pdf
        |> Tincture.set_fill_color(accent)
        |> Tincture.set_font(sans, 11)
        |> Tincture.text_link(
          margin,
          page_h - margin - 200,
          "Open Appendix A from the beginning",
          {:file, appendix_path},
          contents: "Appendix A, opened at its first page"
        )
      end)

    Tincture.tag(pdf, :p, fn pdf ->
      pdf
      |> Tincture.set_fill_color(muted)
      |> Tincture.set_font(body, 8)
      |> Tincture.text_at(
        margin,
        margin,
        "Links resolve relative to this file. Keep the pair together."
      )
    end)
  end)

main_binary = Tincture.export(main)
main_out = Examples.Fonts.output_path("linked/Main-report.pdf")
File.write!(main_out, main_binary)

root = Path.dirname(main_out)

IO.puts("""
wrote #{Path.relative_to_cwd(root)}/
  Main-report.pdf                     #{byte_size(main_binary)} bytes
  #{appendix_path}   #{File.stat!(appendix_out).size} bytes

What the main document carries:

  remote action           GoToR         #{if main_binary =~ "/S /GoToR", do: "ok", else: "MISSING"}
  relative file spec      /F            #{if main_binary =~ "/F (Attached documents/", do: "ok", else: "MISSING"}
  page 3 as index 2       /D [2 /Fit]   #{if main_binary =~ "/D [2 /Fit]", do: "ok", else: "MISSING"}
  whole-file link         no /D         #{if main_binary =~ "/GoToR /F (Attached documents/Appendix-A.pdf) >>", do: "ok", else: "MISSING"}
  reachable from tree     /OBJR         #{if main_binary =~ "/OBJR", do: "ok", else: "MISSING"}
  described for a reader  :contents     #{if main_binary =~ "/Contents (Appendix A", do: "ok", else: "MISSING"}

Open Main-report.pdf in a desktop reader and click a link. Browser-embedded
viewers will render the links and do nothing, which is their policy on
local-file navigation rather than a fault in the document.
""")
