defmodule Tincture.EgTest8ParityTest do
  use ExUnit.Case

  alias Tincture.Layout.Table

  test "eg8-style table rendering supports multiple tables and escaped cell text" do
    primary_rows = [
      ["Version", "Status"],
      ["0.1", "Ready"]
    ]

    escape_rows = [
      ["Escape Sequence", "Value"],
      ["\\b", "Backspace"],
      ["\\n", "New line"],
      ["\\t", "Tab"]
    ]

    {pdf, first_result} =
      Tincture.new()
      |> Table.render(50, 700, [140, 180], primary_rows,
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4
      )

    {pdf, second_result} =
      Table.render(pdf, 120, 500, :auto, escape_rows,
        table_width: 280,
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4
      )

    assert first_result.rows == 2
    assert first_result.columns == 2
    assert second_result.rows == 4
    assert second_result.columns == 2
    assert_in_delta Enum.sum(second_result.widths), 280.0, 0.0001

    rect_ops = Enum.filter(pdf.operations, &match?({:rectangle, _, _, _, _, _}, &1))
    assert length(rect_ops) == 12

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, _, _, "Version", {"Helvetica-Bold", 10.0}}, &1)
           )

    assert Enum.any?(pdf.operations, &match?({:text_at, _, _, "\\b", {"Helvetica", 10.0}}, &1))

    pdf_binary = Tincture.export(pdf)
    assert pdf_binary =~ "(\\\\b) Tj"
    assert pdf_binary =~ "(\\\\n) Tj"
    assert pdf_binary =~ "(\\\\t) Tj"
  end
end
