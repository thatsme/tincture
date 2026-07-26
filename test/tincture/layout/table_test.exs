defmodule Tincture.Layout.TableTest do
  use ExUnit.Case

  alias Tincture.Layout.Table
  alias Tincture.Layout.Table.RenderResult

  test "render/6 draws table cells with borders and header font" do
    rows = [
      ["Name", "Qty"],
      ["Apples", "10"],
      ["Pears", "20"]
    ]

    {pdf, result} =
      Tincture.new()
      |> Table.render(10, 700, [80, 40], rows,
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4
      )

    assert %RenderResult{widths: [80.0, 40.0], rows: 3, columns: 2} = result
    assert result.height == result.row_height * 3

    rect_ops = Enum.filter(pdf.operations, &match?({:rectangle, _, _, _, _, _}, &1))
    assert length(rect_ops) == 6

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, 14.0, _, "Name", {"Helvetica-Bold", 10.0}}, &1)
           )

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, 14.0, _, "Apples", {"Helvetica", 10.0}}, &1)
           )
  end

  test "render/6 supports auto column widths scaled to table_width" do
    rows = [["A", "longer"]]

    {pdf, result} =
      Tincture.new()
      |> Table.render(10, 500, :auto, rows,
        table_width: 120,
        font: "Courier",
        font_size: 10,
        padding: 2,
        border: false
      )

    assert %RenderResult{rows: 1, columns: 2} = result
    assert_in_delta Enum.sum(result.widths), 120.0, 0.0001

    refute Enum.any?(pdf.operations, &match?({:rectangle, _, _, _, _, _}, &1))
    assert Enum.any?(pdf.operations, &match?({:text_at, 12.0, _, "A", {"Courier", 10.0}}, &1))
  end

  test "render/6 rejects mismatched explicit column widths" do
    rows = [["a", "b"]]

    assert_raise ArgumentError, "column width count must match row column count", fn ->
      Tincture.new()
      |> Table.render(10, 500, [100], rows)
    end
  end

  test "render/6 supports vertical alignment options" do
    rows = [["Header"], ["Body"]]

    {top_pdf, _} =
      Tincture.new()
      |> Table.render(10, 500, [120], rows,
        font: "Helvetica",
        font_size: 10,
        padding: 4,
        valign: :top
      )

    {mid_pdf, _} =
      Tincture.new()
      |> Table.render(10, 500, [120], rows,
        font: "Helvetica",
        font_size: 10,
        padding: 4,
        valign: :middle
      )

    {bot_pdf, _} =
      Tincture.new()
      |> Table.render(10, 500, [120], rows,
        font: "Helvetica",
        font_size: 10,
        padding: 4,
        valign: :bottom
      )

    {:text_at, _, top_y, "Header", _} =
      Enum.find(top_pdf.operations, &match?({:text_at, _, _, "Header", _}, &1))

    {:text_at, _, mid_y, "Header", _} =
      Enum.find(mid_pdf.operations, &match?({:text_at, _, _, "Header", _}, &1))

    {:text_at, _, bot_y, "Header", _} =
      Enum.find(bot_pdf.operations, &match?({:text_at, _, _, "Header", _}, &1))

    assert top_y > mid_y
    assert mid_y > bot_y
  end

  test "render/6 rejects invalid vertical alignment option" do
    assert_raise ArgumentError, "valign must be :top, :middle, or :bottom", fn ->
      Tincture.new()
      |> Table.render(10, 500, [100], [["x"]], valign: :invalid)
    end
  end
end
