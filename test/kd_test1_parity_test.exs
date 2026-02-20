defmodule ExGuten.KdTest1ParityTest do
  use ExUnit.Case

  alias ExGuten.Layout.Table
  alias ExGuten.Layout.Template
  alias ExGuten.Layout.Template.DocumentResult

  test "kd_test1-style commercial bill renders with logo, body flow, and line-item table" do
    logo_path = write_test_logo_png!()

    xml = """
    <document page_size="letter" margins="50,50,50,50" columns="1" gutter="20">
      <header font="Helvetica-Bold" size="13">ACME Billing Statement {page}/{total}</header>
      <footer font="Helvetica" size="9">Due in 30 days - Page {page}</footer>
      <body font="Times-Roman" size="11">
        Bill To: Northwind Supplies
        Invoice #: KD-0001
        Date: 2026-02-18
        Thank you for your business. Please review the line items below.
      </body>
    </document>
    """

    {:ok, pdf, %DocumentResult{} = doc_result} =
      ExGuten.new()
      |> ExGuten.page_size(:letter)
      |> ExGuten.set_metadata(title: "KD Test 1", author: "ExGuten")
      |> Template.render_xml_document(xml, page_number_start: 1, page_total: 1, line_height: 13)

    pdf =
      pdf
      |> ExGuten.image_png(50, 726, 24, 24, logo_path)
      |> ExGuten.add_bookmark("Invoice Start", 1)

    {pdf, table_result} =
      Table.render(
        pdf,
        50,
        520,
        [130, 250, 90],
        [
          ["Item", "Description", "Amount"],
          ["Consulting", "Architecture and implementation", "$1,200.00"],
          ["Support", "Priority support (monthly)", "$300.00"],
          ["Total Due", "", "$1,500.00"]
        ],
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4
      )

    assert doc_result.pages_used == 1
    assert doc_result.overflow? == false
    assert table_result.rows == 4
    assert table_result.columns == 3

    pdf_binary = ExGuten.export(pdf)

    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Filter /FlateDecode"
    assert pdf_binary =~ "(ACME Billing Statement 1/1) Tj"
    assert pdf_binary =~ "(Due in 30 days - Page 1) Tj"
    assert pdf_binary =~ "(Consulting) Tj"
    assert pdf_binary =~ "(Total Due) Tj"
    assert pdf_binary =~ "/Type /Outlines"
    assert pdf_binary =~ "/Title (Invoice Start)"
    assert pdf_binary =~ "/Title (KD Test 1)"

    File.rm(logo_path)
  end

  defp write_test_logo_png! do
    path =
      Path.join(System.tmp_dir!(), "ex_guten_kd_logo_#{System.unique_integer([:positive])}.png")

    :ok = File.write(path, test_logo_png_binary())
    path
  end

  defp test_logo_png_binary do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>
    idat = :zlib.compress(<<0, 0, 120, 215, 255>>)

    signature <>
      png_chunk("IHDR", ihdr) <>
      png_chunk("IDAT", idat) <>
      png_chunk("IEND", "")
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32-big, type::binary-size(4), data::binary, crc::32-big>>
  end
end
