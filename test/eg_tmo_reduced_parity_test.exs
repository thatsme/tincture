defmodule Tincture.EgTmoReducedParityTest do
  use ExUnit.Case

  alias Tincture.Layout.Table
  alias Tincture.Layout.Template
  alias Tincture.Typography.RichText

  test "reduced tmo-style composition renders template body flow plus summary table" do
    body =
      RichText.from_plain(
        "This reduced TMO fixture validates template flow across regions and table composition. " <>
          "It intentionally uses enough words to produce multiple wrapped lines in the body area.",
        font: "Times-Roman",
        size: 11
      )

    template =
      Template.new(page_size: :letter, margins: {40, 40, 40, 40}, columns: 2, gutter: 18)
      |> Template.with_header("TMO Reduced Fixture", font: "Helvetica-Bold", size: 16)
      |> Template.with_footer("Confidential", font: "Helvetica", size: 9)

    {pdf, template_result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Template.render(template, body, align: :justified, line_height: 13)

    {pdf, table_result} =
      Table.render(pdf, 60, 180, [180, 120], [["Metric", "Value"], ["Status", "Draft"]],
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4
      )

    pdf_binary = Tincture.export(pdf)

    assert template_result.overflow? == false
    assert table_result.rows == 2
    assert table_result.columns == 2

    assert pdf_binary =~ "(TMO Reduced Fixture) Tj"
    assert pdf_binary =~ "(Confidential) Tj"
    assert pdf_binary =~ "(Metric) Tj"
    assert pdf_binary =~ "(Status) Tj"
    assert pdf_binary =~ "/BaseFont /Helvetica-Bold"
    assert pdf_binary =~ "/BaseFont /Times-Roman"
  end
end
