defmodule ExGuten.EgTest3ParityTest do
  use ExUnit.Case

  alias ExGuten.Typography.RichText
  alias ExGuten.Typography.RichText.Run

  test "eg3-style justification and mixed-font paragraph blocks render expected positioning" do
    justified = RichText.from_plain("one two three four", font: "Courier", size: 10)
    centered = RichText.from_plain("alpha beta", font: "Courier", size: 10)
    righted = RichText.from_plain("alpha beta", font: "Courier", size: 10)

    mixed =
      RichText.from_runs([
        %Run{text: "This is ", font: "Times-Roman", size: 12},
        %Run{text: "AWAY", font: "Times-Italic", size: 12},
        %Run{text: " code", font: "Courier", size: 12}
      ])

    pdf =
      ExGuten.new()
      |> ExGuten.page_size(:a4)
      |> ExGuten.text_paragraph(50, 700, justified, 60, align: :justified, line_height: 12)
      |> ExGuten.text_paragraph(200, 640, centered, 80, align: :center, line_height: 12)
      |> ExGuten.text_paragraph(300, 620, righted, 80, align: :right, line_height: 12)
      |> ExGuten.text_paragraph(50, 580, mixed, 300, align: :left, line_height: 14)

    assert {:text_at, 50.0, 700.0, "one", {"Courier", 10}} in pdf.operations
    assert {:text_at, 92.0, 700.0, "two", {"Courier", 10}} in pdf.operations

    assert {:text_at, 210.0, 640.0, "alpha", {"Courier", 10}} in pdf.operations
    assert {:text_at, 320.0, 620.0, "alpha", {"Courier", 10}} in pdf.operations

    assert Enum.any?(
             pdf.operations,
             &match?({:text_at, _, 580.0, "AWAY", {"Times-Italic", 12}}, &1)
           )

    assert Enum.any?(pdf.operations, &match?({:text_at, _, 580.0, "code", {"Courier", 12}}, &1))

    pdf_binary = ExGuten.export(pdf)

    assert pdf_binary =~ "/BaseFont /Times-Roman"
    assert pdf_binary =~ "/BaseFont /Times-Italic"
    assert pdf_binary =~ "/BaseFont /Courier"
    assert pdf_binary =~ "(AWAY) Tj"
    assert pdf_binary =~ "(code) Tj"
  end
end
