defmodule Tincture.PDFFixtureLockTest do
  use ExUnit.Case

  alias Tincture.Layout.Table
  alias Tincture.Showcase.BankStatement
  alias Tincture.Showcase.Invoice
  alias Tincture.Typography.RichText

  test "core text fixture hash stays stable" do
    pdf_binary =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Tincture.set_font("Times-Roman", 16)
      |> Tincture.text_at(72, 720, "Locked fixture: core text")
      |> Tincture.text_at_rotated(300, 300, 30, "Rotation")
      |> Tincture.line(72, 710, 400, 710)
      |> Tincture.export()

    assert sha256_hex(pdf_binary) == read_fixture_hash!("test/fixtures/pdf/core_text.sha256")
  end

  test "optimal typography fixture hash stays stable" do
    rich =
      RichText.from_plain(
        "aa bb cc dd eeeeee aa- aa- aaa- aa aa- hyphenation strategy",
        font: "Courier",
        size: 10
      )

    pdf_binary =
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
      |> Tincture.export()

    assert sha256_hex(pdf_binary) ==
             read_fixture_hash!("test/fixtures/pdf/optimal_typography.sha256")
  end

  test "table layout fixture hash stays stable" do
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

    pdf_binary = Tincture.export(pdf)

    assert sha256_hex(pdf_binary) == read_fixture_hash!("test/fixtures/pdf/table_layout.sha256")
  end

  test "invoice showcase fixture hash stays stable" do
    pdf_binary = Invoice.pdf_binary()

    assert sha256_hex(pdf_binary) ==
             read_fixture_hash!("test/fixtures/pdf/invoice_showcase.sha256")
  end

  test "bank statement showcase fixture hash stays stable" do
    pdf_binary = BankStatement.pdf_binary()

    assert sha256_hex(pdf_binary) ==
             read_fixture_hash!("test/fixtures/pdf/bank_statement_showcase.sha256")
  end

  test "bank statement joint fee/interest fixture hash stays stable" do
    pdf_binary = BankStatement.pdf_binary(:joint_fee_interest)

    assert sha256_hex(pdf_binary) ==
             read_fixture_hash!(
               "test/fixtures/pdf/bank_statement_joint_fee_interest_showcase.sha256"
             )
  end

  defp read_fixture_hash!(path) do
    path
    |> File.read!()
    |> String.trim()
  end

  defp sha256_hex(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end
end
