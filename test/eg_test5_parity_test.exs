defmodule ExGuten.EgTest5ParityTest do
  use ExUnit.Case

  alias ExGuten.Typography.RichText

  test "eg5-style rotated paragraph blocks with mixed alignments export rotation matrices" do
    rich =
      RichText.from_plain(
        "Rotation parity text demonstrates wrapped lines for alignment checks.",
        font: "Times-Roman",
        size: 12
      )

    pdf =
      ExGuten.new()
      |> ExGuten.text_paragraph(60, 760, rich, 160, align: :left, rotate: 0, line_height: 14)
      |> ExGuten.text_paragraph(220, 680, rich, 160, align: :center, rotate: 45, line_height: 14)
      |> ExGuten.text_paragraph(380, 600, rich, 160, align: :right, rotate: 90, line_height: 14)
      |> ExGuten.text_paragraph(60, 520, rich, 160,
        align: :justified,
        rotate: 180,
        line_height: 14
      )

    rotated_ops =
      Enum.filter(pdf.operations, fn
        {:text_at_rotated, _, _, _, _, _} -> true
        _ -> false
      end)

    assert length(rotated_ops) > 8
    assert Enum.any?(rotated_ops, &match?({:text_at_rotated, _, _, 0, _, _}, &1))
    assert Enum.any?(rotated_ops, &match?({:text_at_rotated, _, _, 45, _, _}, &1))
    assert Enum.any?(rotated_ops, &match?({:text_at_rotated, _, _, 90, _, _}, &1))
    assert Enum.any?(rotated_ops, &match?({:text_at_rotated, _, _, 180, _, _}, &1))

    pdf_binary = ExGuten.export(pdf)

    assert pdf_binary =~ "0.7071067812 0.7071067812 -0.7071067812 0.7071067812"
    assert pdf_binary =~ "0.0 1.0 -1.0 0.0"
    assert pdf_binary =~ "-1.0 0.0 -0.0 -1.0"
  end
end
