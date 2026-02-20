defmodule ExGuten.EgTest4ParityTest do
  use ExUnit.Case

  @base_14_fonts [
    "Courier",
    "Courier-Bold",
    "Courier-Oblique",
    "Courier-BoldOblique",
    "Helvetica",
    "Helvetica-Bold",
    "Helvetica-Oblique",
    "Helvetica-BoldOblique",
    "Times-Roman",
    "Times-Bold",
    "Times-Italic",
    "Times-BoldItalic",
    "Symbol",
    "ZapfDingbats"
  ]

  test "eg4-style font showcase serializes all base-14 fonts" do
    pdf =
      @base_14_fonts
      |> Enum.with_index()
      |> Enum.reduce(ExGuten.new(), fn {font_name, idx}, acc ->
        y = 800 - idx * 24

        acc
        |> ExGuten.set_font(font_name, 12)
        |> ExGuten.text_at(20, y, "#{font_name}: abc ABC 123")
      end)

    pdf_binary = ExGuten.export(pdf)

    Enum.each(@base_14_fonts, fn font_name ->
      assert pdf_binary =~ "/BaseFont /#{font_name}"
    end)

    assert length(Regex.scan(~r|/Subtype /Type1 /BaseFont /|, pdf_binary)) == 14
  end
end
