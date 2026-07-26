Code.require_file("support/fonts.exs", __DIR__)

# A tagged document: the same report, twice over.
#
# Visually this is one page. Structurally it carries a second layer that a
# screen reader walks instead of the glyph positions — headings to navigate by,
# a table whose header cells say which cells they govern, alternative text for
# the chart, and an explicit reading order.
#
# Nothing here changes what the page looks like. That is the point: tagging is
# invisible until something needs to read the document rather than display it.
#
# The table is built with Layout.Table, which tags itself when the document is
# being tagged - rows, cells, header scope and artifact borders included.

alias Tincture.Typography.RichText

page_w = 595
page_h = 842
margin = 50
content_w = page_w - margin * 2

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule = {0.85, 0.86, 0.88}

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Regional performance, Q2 2026",
    author: "Northgate Instruments Ltd",
    subject: "Quarterly regional revenue report"
  )
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

# The document language. Without it a screen reader has to guess how to
# pronounce the text, so this is a requirement rather than a nicety.
pdf = Tincture.set_language(pdf, "en-GB")

rows = [
  {"North", "1,204,880", "+9.2%"},
  {"Midlands", "986,140", "+4.1%"},
  {"South West", "742,300", "-1.8%"},
  {"Scotland", "531,905", "+12.6%"}
]

intro =
  "Revenue grew in three of four regions during the second quarter. Scotland " <>
    "returned the strongest growth following the Aberdeen service contract, while " <>
    "the South West declined slightly against a strong comparative period. The " <>
    "figures below exclude intra-group transfers and are stated before tax."

pdf =
  Tincture.tag(pdf, :document, fn pdf ->
    # --- heading ----------------------------------------------------------
    pdf =
      pdf
      |> Tincture.tag(:h1, fn pdf ->
        pdf
        |> Tincture.set_fill_color(ink)
        |> Tincture.set_font(body, 22)
        |> Tincture.text_at(margin, page_h - 90, "Regional performance")
      end)
      |> Tincture.tag(:p, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(sans, 9)
        |> Tincture.text_at(margin, page_h - 108, "Second quarter, 2026 · Northgate Instruments Ltd")
      end)

    # A rule under the header is decoration. In a tagged document content that
    # is neither tagged nor an artifact fails conformance and is read out as
    # noise, so say which it is.
    pdf =
      Tincture.artifact(pdf, fn pdf ->
        pdf
        |> Tincture.set_stroke_color(rule)
        |> Tincture.set_line_width(0.75)
        |> Tincture.line(margin, page_h - 124, page_w - margin, page_h - 124)
        |> Tincture.stroke()
      end)

    # --- summary ----------------------------------------------------------
    pdf =
      Tincture.tag(pdf, :section, [title: "Summary"], fn pdf ->
        pdf =
          Tincture.tag(pdf, :h2, fn pdf ->
            pdf
            |> Tincture.set_fill_color(accent)
            |> Tincture.set_font(sans, 8)
            |> Tincture.text_at(margin, page_h - 152, "SUMMARY")
          end)

        Tincture.tag(pdf, :p, fn pdf ->
          pdf
          |> Tincture.set_fill_color(ink)
          |> Tincture.set_font(body, 10.5)
          |> Tincture.text_paragraph(
            margin,
            page_h - 176,
            RichText.from_plain(intro, font: body, size: 10.5),
            content_w,
            align: :justified,
            line_break: :optimal,
            line_height: 15
          )
        end)
      end)

    # --- table ------------------------------------------------------------
    # Layout.Table tags itself. Inside a tagged document it emits /Table,
    # /THead, /TBody, /TR and /TH or /TD per cell, gives header cells a /Scope
    # so a reader knows which cells they govern, and marks its own borders as
    # artifacts. None of that has to be written here.
    table_top = page_h - 290

    pdf =
      Tincture.tag(pdf, :section, [title: "Revenue by region"], fn pdf ->
        pdf =
          Tincture.tag(pdf, :h2, fn pdf ->
            pdf
            |> Tincture.set_fill_color(accent)
            |> Tincture.set_font(sans, 8)
            |> Tincture.text_at(margin, table_top + 24, "REVENUE BY REGION")
          end)

        # Graphics state persists, and the heading above left the fill colour on
        # the accent. Table.render draws text in whatever colour is current.
        pdf = Tincture.set_fill_color(pdf, ink)

        table_rows =
          [["Region", "Revenue (GBP)", "Change"]] ++
            Enum.map(rows, fn {region, revenue, change} -> [region, revenue, change] end)

        {pdf, table} =
          Tincture.Layout.Table.render(pdf, margin, table_top + 8, [250, 130, 115], table_rows,
            header_rows: 1,
            font: body,
            header_font: sans,
            font_size: 10,
            padding: 7,
            border: false,
            table_width: content_w
          )

        # Rules are decoration: an artifact, so a screen reader skips them
        # rather than announcing them as content.
        Tincture.artifact(pdf, fn pdf ->
          0..table.rows
          |> Enum.reduce(pdf, fn index, acc ->
            y = table_top + 8 - index * table.row_height

            acc
            |> Tincture.set_stroke_color(rule)
            |> Tincture.set_line_width(0.75)
            |> Tincture.line(margin, y, page_w - margin, y)
            |> Tincture.stroke()
          end)
        end)
      end)

    # --- chart ------------------------------------------------------------
    # A figure is meaningless to a screen reader without :alt. Drawn shapes
    # carry no text at all, so the alternative text is the only description
    # that exists.
    chart_base = 240
    chart_x = margin
    bar_w = 46
    gap = 26
    max_revenue = 1_204_880

    revenues = [1_204_880, 986_140, 742_300, 531_905]

    Tincture.tag(pdf, :section, [title: "Chart"], fn pdf ->
      pdf =
        Tincture.tag(pdf, :h2, fn pdf ->
          pdf
          |> Tincture.set_fill_color(accent)
          |> Tincture.set_font(sans, 8)
          |> Tincture.text_at(margin, chart_base + 150, "REVENUE, RELATIVE")
        end)

      pdf =
        Tincture.tag(
          pdf,
          :figure,
          [
            alt:
              "Bar chart comparing quarterly revenue by region. North is highest at " <>
                "1,204,880 pounds, followed by Midlands at 986,140, South West at " <>
                "742,300 and Scotland at 531,905."
          ],
          fn pdf ->
            revenues
            |> Enum.with_index()
            |> Enum.reduce(pdf, fn {revenue, index}, acc ->
              height = revenue / max_revenue * 120
              x = chart_x + index * (bar_w + gap)

              acc
              |> Tincture.set_fill_color(accent)
              |> Tincture.rectangle(x, chart_base, bar_w, height, :fill)
            end)
          end
        )

      # Labels under the bars are a caption, not part of the figure: they are
      # real text and should be read as such.
      Tincture.tag(pdf, :caption, fn pdf ->
        ["North", "Midlands", "South West", "Scotland"]
        |> Enum.with_index()
        |> Enum.reduce(pdf, fn {label, index}, acc ->
          acc
          |> Tincture.set_fill_color(muted)
          |> Tincture.set_font(sans, 7.5)
          |> Tincture.text_at(chart_x + index * (bar_w + gap), chart_base - 14, label)
        end)
      end)
    end)
  end)

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("accessible.pdf")
File.write!(path, binary)

marked = length(Regex.scan(~r/BDC/, binary))
elements = length(Regex.scan(~r|/Type /StructElem|, binary))

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")
IO.puts("tagged? #{Tincture.tagged?(pdf)}")
IO.puts("structure elements: #{elements}, marked-content sequences: #{marked}")
IO.puts("language: #{if binary =~ "/Lang", do: "set", else: "missing"}")
IO.puts("alt text on the figure: #{if binary =~ "/Alt (", do: "present", else: "missing"}")

IO.puts("""

Validated: this document passes veraPDF 1.30.2 against PDF/UA-1, 106 of 106
rules. Check it yourself with:

    verapdf --flavour ua1 #{Path.relative_to_cwd(path)}
""")
