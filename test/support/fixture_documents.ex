defmodule Tincture.Test.FixtureDocuments do
  @moduledoc """
  The documents whose bytes `Tincture.PDFFixtureLockTest` locks.

  Built here rather than inline so that every other test reading "the fixture
  documents" reads exactly the bytes the locks cover, with no copy that can
  drift from them.
  """

  alias Tincture.Layout.Table
  alias Tincture.Showcase.BankStatement
  alias Tincture.Showcase.Invoice
  alias Tincture.Typography.RichText

  @names ~w(
    core_text
    optimal_typography
    table_layout
    invoice_showcase
    bank_statement_showcase
    bank_statement_joint_fee_interest_showcase
  )

  @doc """
  The name of every locked document: the basename of its digest under
  `test/fixtures/pdf/`.
  """
  @spec names() :: [String.t()]
  def names, do: @names

  @doc """
  Builds the locked document called `name`, exported with `export_opts`.
  """
  @spec build(String.t(), keyword()) :: binary()
  def build(name, export_opts \\ []), do: name |> document() |> Tincture.export(export_opts)

  defp document("core_text"), do: core_text()
  defp document("optimal_typography"), do: optimal_typography()
  defp document("table_layout"), do: table_layout()
  defp document("invoice_showcase"), do: Invoice.build_document().pdf
  defp document("bank_statement_showcase"), do: BankStatement.build_document().pdf

  defp document("bank_statement_joint_fee_interest_showcase"),
    do: BankStatement.build_document(:joint_fee_interest).pdf

  defp core_text do
    Tincture.new()
    |> Tincture.page_size(:letter)
    |> Tincture.set_font("Times-Roman", 16)
    |> Tincture.text_at(72, 720, "Locked fixture: core text")
    |> Tincture.text_at_rotated(300, 300, 30, "Rotation")
    |> Tincture.line(72, 710, 400, 710)
  end

  defp optimal_typography do
    rich =
      RichText.from_plain(
        "aa bb cc dd eeeeee aa- aa- aaa- aa aa- hyphenation strategy",
        font: "Courier",
        size: 10
      )

    Tincture.new()
    |> Tincture.text_paragraph(72, 700, rich, 220,
      align: :justified,
      line_break: :optimal,
      optimal_cost_model: :box_glue,
      justify_max_space_multiplier: 2.0,
      justify_min_space_multiplier: 0.75,
      widow_penalty: 800,
      orphan_penalty: 800,
      hyphen_penalty: 250,
      consecutive_hyphen_penalty: 350,
      fitness_class_penalty: 500
    )
  end

  defp table_layout do
    rows = [
      ["Item", "Qty", "Price"],
      ["Pencil", "12", "$1.50"],
      ["Notebook", "4", "$8.00"],
      ["Eraser", "6", "$0.75"]
    ]

    {pdf, _result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Table.render(72, 700, :auto, rows,
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4,
        table_width: 280
      )

    pdf
  end
end
