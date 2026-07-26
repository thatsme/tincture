defmodule Tincture.EgTmoFullParityTest do
  use ExUnit.Case

  alias Tincture.Layout.Table
  alias Tincture.Layout.Template
  alias Tincture.Layout.Template.DocumentResult
  alias Tincture.Typography.RichText

  test "full tmo-style multi-page composition renders document flow and table sections" do
    body_text = Enum.map_join(1..60, " ", fn idx -> "section#{idx}" end)
    body = RichText.from_plain(body_text, font: "Times-Roman", size: 11)

    template =
      Template.new(
        page_size: :letter,
        margins: {40, 40, 40, 40},
        columns: 2,
        gutter: 18,
        header_height: 320,
        footer_height: 320
      )
      |> Template.with_header("TMO Full Fixture {page}/{total}", font: "Helvetica-Bold", size: 14)
      |> Template.with_footer("Confidential p.{page}", font: "Helvetica", size: 9)

    {pdf, doc_result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Template.render_document(template, body,
        page_number_start: 1,
        page_total: 2,
        max_pages: 2,
        align: :justified,
        line_height: 13
      )

    assert %DocumentResult{pages_used: 2, overflow?: false, spill_text: ""} = doc_result

    {pdf, table_result} =
      Table.render(pdf, 60, 180, [170, 130], [["Metric", "Value"], ["Status", "Draft"]],
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4
      )

    assert table_result.rows == 2
    assert table_result.columns == 2

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "/Count 2"
    assert pdf_binary =~ "(TMO Full Fixture 1/2) Tj"
    assert pdf_binary =~ "(TMO Full Fixture 2/2) Tj"
    assert pdf_binary =~ "(Confidential p.1) Tj"
    assert pdf_binary =~ "(Confidential p.2) Tj"
    assert pdf_binary =~ "(Metric) Tj"
    assert pdf_binary =~ "(Status) Tj"
  end
end
