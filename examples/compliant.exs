Code.require_file("support/fonts.exs", __DIR__)

# A PDF/UA-1 compliant document, built as a checklist.
#
# examples/accessible.exs is a realistic report that happens to be tagged. This
# one is a template: every requirement is called out where it is satisfied, so
# it can be copied and filled in. Each numbered comment corresponds to a clause
# veraPDF checks.
#
# Verify with:
#
#     verapdf --flavour ua1 examples/output/compliant.pdf

alias Tincture.Typography.RichText

page_w = 595
page_h = 842
margin = 56
content_w = page_w - margin * 2

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule_grey = {0.85, 0.86, 0.88}

# (1) A title. PDF/UA requires the catalog to carry XMP metadata, and a reader
#     to display the title rather than the file name. Tincture emits the XMP
#     stream and /ViewerPreferences /DisplayDocTitle from this.
{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Accessible document template",
    author: "Northgate Instruments Ltd",
    subject: "A worked example of a PDF/UA-1 conforming document",
    keywords: "accessibility, PDF/UA, template"
  )
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

# (2) The document's natural language. Without it a screen reader guesses the
#     pronunciation, and clause 7.2 fails.
pdf = Tincture.set_language(pdf, "en-GB")

# A heading, drawn and tagged together. Heading levels must not skip: H1 then
# H2, never H1 then H3.
heading = fn pdf, level, y, text, size ->
  Tincture.tag(pdf, level, fn pdf ->
    pdf
    |> Tincture.set_fill_color(if(level == :h1, do: ink, else: accent))
    |> Tincture.set_font(if(level == :h1, do: body, else: sans), size)
    |> Tincture.text_at(margin, y, text)
  end)
end

paragraph = fn pdf, y, text, width ->
  Tincture.tag(pdf, :p, fn pdf ->
    pdf
    |> Tincture.set_fill_color(ink)
    |> Tincture.set_font(body, 10.5)
    |> Tincture.text_paragraph(
      margin,
      y,
      RichText.from_plain(text, font: body, size: 10.5),
      width,
      align: :left,
      line_break: :optimal,
      line_height: 15
    )
  end)
end

# (3) Decoration must say that it is decoration. Content that is neither tagged
#     nor marked as an artifact fails clause 7.1 and is announced as noise.
horizontal_rule = fn pdf, y ->
  Tincture.artifact(pdf, fn pdf ->
    pdf
    |> Tincture.set_stroke_color(rule_grey)
    |> Tincture.set_line_width(0.75)
    |> Tincture.line(margin, y, page_w - margin, y)
    |> Tincture.stroke()
  end)
end

intro =
  "Everything on this page is reachable by a screen reader in a defined order. " <>
    "The headings below can be navigated directly, the list is announced as a " <>
    "list with a count, the table's cells know which headers govern them, and " <>
    "the chart carries a description of what it shows."

list_items = [
  "Tag every piece of content, or mark it as an artifact.",
  "Give figures alternative text describing what they convey.",
  "Give table header cells a scope, so cells can be related to them.",
  "Set the document language and title."
]

# Positions below the table are derived from its height rather than guessed:
# an :auto table is as tall as its content, and hardcoding what follows it is
# how content ends up overlapping.
table_top = page_h - 424
table_row_height = 26
table_bottom = table_top - table_row_height * 5

table_rows = [
  ["Requirement", "Clause", "Satisfied by"],
  ["Document language", "7.2", "set_language/2"],
  ["Logical structure", "7.1", "tag/4"],
  ["Alternative text", "7.3", ":alt on a figure"],
  ["Table headers", "7.5", ":scope on a header cell"]
]

# (4) Everything hangs off a single /Document element, which gives the reader a
#     root and an unambiguous reading order.
pdf =
  Tincture.tag(pdf, :document, fn pdf ->
    pdf = heading.(pdf, :h1, page_h - 92, "Accessible document template", 21)

    pdf =
      pdf
      |> Tincture.tag(:p, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(sans, 9)
        |> Tincture.text_at(margin, page_h - 110, "Conforming to PDF/UA-1 (ISO 14289-1)")
      end)
      |> horizontal_rule.(page_h - 126)

    pdf =
      Tincture.tag(pdf, :section, [title: "Overview"], fn pdf ->
        pdf
        |> heading.(:h2, page_h - 156, "OVERVIEW", 8)
        |> paragraph.(page_h - 180, intro, content_w)
      end)

    # (5) A list is a container of list items, each with a label and a body.
    #     Marking it up this way is what lets a reader say "list, four items"
    #     and let someone skip past it.
    pdf =
      Tincture.tag(pdf, :section, [title: "Checklist"], fn pdf ->
        pdf = heading.(pdf, :h2, page_h - 264, "CHECKLIST", 8)

        Tincture.tag(pdf, :list, fn pdf ->
          list_items
          |> Enum.with_index()
          |> Enum.reduce(pdf, fn {item, index}, acc ->
            y = page_h - 290 - index * 20

            Tincture.tag(acc, :list_item, fn acc ->
              acc
              # The bullet is a label, not body text: a reader announces the
              # item rather than reading "bullet" aloud as content.
              |> Tincture.tag(:label, fn acc ->
                acc
                |> Tincture.set_fill_color(accent)
                |> Tincture.set_font(body, 10.5)
                |> Tincture.text_at(margin, y, "•")
              end)
              |> Tincture.tag(:list_body, fn acc ->
                acc
                |> Tincture.set_fill_color(ink)
                |> Tincture.set_font(body, 10.5)
                |> Tincture.text_at(margin + 16, y, item)
              end)
            end)
          end)
        end)
      end)

    # (6) Layout.Table tags itself: /Table, /THead, /TBody, /TR, /TH with a
    #     /Scope, /TD, and its own borders as artifacts.
    pdf =
      Tincture.tag(pdf, :section, [title: "Requirements"], fn pdf ->
        pdf = heading.(pdf, :h2, page_h - 404, "WHAT EACH RULE NEEDS", 8)

        pdf = Tincture.set_fill_color(pdf, ink)

        {pdf, _table} =
          Tincture.Layout.Table.render(pdf, margin, table_top, :auto, table_rows,
            header_rows: 1,
            font: body,
            header_font: sans,
            font_size: 9.5,
            padding: 7,
            row_height: table_row_height,
            table_width: content_w
          )

        pdf
      end)

    # (7) A figure drawn as vector shapes carries no text at all, so its
    #     alternative text is the only description that exists. A figure
    #     without one fails clause 7.3.
    Tincture.tag(pdf, :section, [title: "Figure"], fn pdf ->
      pdf = heading.(pdf, :h2, table_bottom - 34, "AN EXAMPLE FIGURE", 8)

      pdf =
        Tincture.tag(
          pdf,
          :figure,
          [
            alt:
              "A row of four bars of increasing height, illustrating that each " <>
                "requirement in the checklist builds on the previous one."
          ],
          fn pdf ->
            bars_base = table_bottom - 152

            1..4
            |> Enum.reduce(pdf, fn index, acc ->
              acc
              |> Tincture.set_fill_color(accent)
              |> Tincture.rectangle(margin + (index - 1) * 60, bars_base, 44, index * 22, :fill)
            end)
          end
        )

      # A caption is real text and belongs in the structure, not in the figure.
      Tincture.tag(pdf, :caption, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(sans, 8)
        |> Tincture.text_at(
          margin,
          table_bottom - 168,
          "Figure 1 — each requirement builds on the last."
        )
      end)
    end)
  end)

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("compliant.pdf")
File.write!(path, binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")

IO.puts("""

Checklist, and where each is satisfied:

  document language      Tincture.set_language/2            #{if binary =~ "/Lang", do: "ok", else: "MISSING"}
  title in XMP metadata  Tincture.set_metadata/2            #{if binary =~ "/Type /Metadata", do: "ok", else: "MISSING"}
  display title, not file  /ViewerPreferences               #{if binary =~ "/DisplayDocTitle true", do: "ok", else: "MISSING"}
  marked as tagged       /MarkInfo                          #{if binary =~ "/MarkInfo", do: "ok", else: "MISSING"}
  logical structure      Tincture.tag/4                     #{if binary =~ "/StructTreeRoot", do: "ok", else: "MISSING"}
  decoration as artifact Tincture.artifact/2                #{if binary =~ "/Artifact BMC", do: "ok", else: "MISSING"}
  figure alternative text  :alt                             #{if binary =~ "/Alt (", do: "ok", else: "MISSING"}
  table header scope     :scope                             #{if binary =~ "/O /Table /Scope", do: "ok", else: "MISSING"}
  list structure         :list / :list_item / :label        #{if binary =~ "/S /LBody", do: "ok", else: "MISSING"}

Verify independently:

    verapdf --flavour ua1 #{Path.relative_to_cwd(path)}
""")
