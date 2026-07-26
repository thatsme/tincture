defmodule Tincture.Layout.BoxTest do
  use ExUnit.Case

  alias Tincture.Layout.Box
  alias Tincture.Layout.Box.FlowResult
  alias Tincture.Typography.LayoutResult
  alias Tincture.Typography.RichText
  alias Tincture.Typography.RichText.Run

  test "flow_text/7 renders visible lines and returns spill metadata" do
    rich = RichText.from_plain("one two three four", font: "Courier", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Box.flow_text(50, 700, 30, 28, rich, line_height: 14)

    assert %LayoutResult{overflow?: true, spill_text: "three\nfour"} = result
    assert Enum.map(result.lines, & &1.text) == ["one", "two"]
    assert Enum.map(result.spill_lines, & &1.text) == ["three", "four"]

    assert [
             {:text_at, 50.0, 700.0, "one", {"Courier", 10}},
             {:text_at, 50.0, 686.0, "two", {"Courier", 10}}
           ] = pdf.operations
  end

  test "flow_text/7 supports rotate and justified rendering for visible box lines" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Box.flow_text(10, 100, 60, 12, rich, line_height: 12, align: :justified, rotate: 45)

    assert result.overflow? == true
    assert Enum.map(result.lines, & &1.text) == ["one two"]
    assert Enum.map(result.spill_lines, & &1.text) == ["three"]

    assert [
             {:text_at_rotated, 10.0, 100.0, 45, "one", {"Courier", 10}},
             {:text_at_rotated, 52.0, 100.0, 45, "two", {"Courier", 10}}
           ] = pdf.operations
  end

  test "flow_text/7 with too-small height renders nothing and spills all text" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Box.flow_text(10, 100, 60, 8, rich, line_height: 12)

    assert result.overflow? == true
    assert result.lines == []
    assert Enum.map(result.spill_lines, & &1.text) == ["one two"]
    assert result.spill_text == "one two"
    assert pdf.operations == []
  end

  test "flow_text/7 rejects non-positive line_height" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    assert_raise ArgumentError, "line_height must be a positive number", fn ->
      Tincture.new()
      |> Box.flow_text(10, 100, 60, 20, rich, line_height: 0)
    end
  end

  test "flow_across_boxes/4 continues text across boxes and reports final spill" do
    rich = RichText.from_plain("one two three four five six", font: "Courier", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Box.flow_across_boxes(
        rich,
        [
          {10, 100, 30, 28},
          {60, 100, 30, 28}
        ],
        line_height: 14
      )

    assert %FlowResult{
             boxes_used: 2,
             overflow?: true,
             spill_text: "five\nsix",
             box_results: [%LayoutResult{}, %LayoutResult{}]
           } = result

    assert [
             {:text_at, 10.0, 100.0, "one", {"Courier", 10}},
             {:text_at, 10.0, 86.0, "two", {"Courier", 10}},
             {:text_at, 60.0, 100.0, "three", {"Courier", 10}},
             {:text_at, 60.0, 86.0, "four", {"Courier", 10}}
           ] = pdf.operations
  end

  test "flow_across_boxes/4 supports rotated justified flow across multiple boxes" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    {pdf, result} =
      Tincture.new()
      |> Box.flow_across_boxes(
        rich,
        [
          {10, 100, 60, 12},
          {10, 80, 60, 12}
        ],
        line_height: 12,
        align: :justified,
        rotate: 45
      )

    assert %FlowResult{boxes_used: 2, overflow?: false, spill_text: ""} = result

    assert [
             {:text_at_rotated, 10.0, 100.0, 45, "one", {"Courier", 10}},
             {:text_at_rotated, 52.0, 100.0, 45, "two", {"Courier", 10}},
             {:text_at_rotated, 10.0, 80.0, 45, "three", {"Courier", 10}}
           ] = pdf.operations
  end

  test "flow_across_boxes/4 preserves mixed run styles across spill boundaries" do
    rich =
      RichText.from_runs([
        %Run{text: "one ", font: "Courier", size: 10},
        %Run{text: "two", font: "Helvetica", size: 10}
      ])

    {pdf, result} =
      Tincture.new()
      |> Box.flow_across_boxes(
        rich,
        [
          {10, 100, 24, 12},
          {60, 100, 60, 12}
        ],
        line_height: 12
      )

    assert %FlowResult{overflow?: false} = result

    assert [
             {:text_at, 10.0, 100.0, "one", {"Courier", 10}},
             {:text_at, 60.0, 100.0, "two", {"Helvetica", 10}}
           ] = pdf.operations
  end
end
