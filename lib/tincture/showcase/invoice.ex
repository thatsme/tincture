defmodule Tincture.Showcase.Invoice do
  @moduledoc false

  alias Tincture.Layout.Table
  alias Tincture.Layout.Template.DocumentResult
  alias Tincture.Layout.Template.RenderResult
  alias Tincture.Typography.RichText

  @type build_result :: %{
          pdf: Tincture.PDF.t(),
          doc_result: DocumentResult.t(),
          line_items_result: Table.RenderResult.t(),
          summary_result: Table.RenderResult.t()
        }

  @spec build_document() :: build_result()
  def build_document do
    logo_path = write_test_logo_png!()

    try do
      pdf =
        Tincture.new()
        |> Tincture.page_size(:letter)
        |> Tincture.set_metadata(
          title: "Invoice Showcase Demo",
          author: "Tincture",
          subject: "Complex invoice integration test",
          keywords: "invoice,showcase,pdf"
        )
        |> Tincture.add_page()
        |> Tincture.add_bookmark("Invoice Summary", 1)
        |> Tincture.add_bookmark("Terms and Remittance", 2)
        |> Tincture.set_page(1)
        |> draw_header_footer(1, 2)
        |> Tincture.image_png(48, 736, 20, 20, logo_path)
        |> Tincture.set_font("Helvetica-Bold", 22)
        |> Tincture.text_at(74, 736, "INVOICE")
        |> Tincture.set_font("Helvetica", 10)
        |> Tincture.text_at(48, 712, "Invoice # INV-2026-0042")
        |> Tincture.text_at(48, 698, "Issue Date: 2026-02-20")
        |> Tincture.text_at(48, 684, "Bill To: Northwind Components")
        |> Tincture.text_at_rotated(438, 702, 20, "APPROVED")

      {pdf, line_items_result} =
        Table.render(pdf, 48, 654, :auto, invoice_line_items(),
          header_rows: 1,
          font: "Helvetica",
          header_font: "Helvetica-Bold",
          font_size: 9,
          padding: 4,
          valign: :middle,
          table_width: 516,
          min_col_width: 42
        )

      terms_rich =
        RichText.from_plain(
          "Payment due in 30 days. Late balances accrue 1.5% monthly. " <>
            "Please include invoice number INV-2026-0042 on remittance and ACH references.",
          font: "Times-Roman",
          size: 10
        )

      pdf =
        Tincture.text_paragraph(pdf, 48, 446, terms_rich, 250,
          align: :justified,
          line_break: :optimal,
          optimal_cost_model: :box_glue,
          line_height: 11
        )

      {pdf, summary_result} =
        Table.render(pdf, 350, 446, [110, 56], invoice_totals(),
          header_rows: 0,
          font: "Helvetica",
          header_font: "Helvetica-Bold",
          font_size: 10,
          padding: 4,
          valign: :middle
        )

      pdf =
        pdf
        |> Tincture.set_page(2)
        |> draw_header_footer(2, 2)
        |> Tincture.set_font("Helvetica-Bold", 12)
        |> Tincture.text_at(48, 708, "Remittance and Terms")
        |> Tincture.set_font("Helvetica", 10)
        |> Tincture.text_at(48, 690, "ACH: 021000021 / 123456789")
        |> Tincture.text_at(48, 676, "Reference: INV-2026-0042")
        |> Tincture.text_at(48, 650, "Please remit payment within 30 days of invoice date.")
        |> Tincture.text_at(48, 636, "Questions: billing@acme.example or (800) 555-0142")

      doc_result = %DocumentResult{
        pages_used: 2,
        overflow?: false,
        spill_text: "",
        page_results: [%RenderResult{}, %RenderResult{}]
      }

      %{
        pdf: pdf,
        doc_result: doc_result,
        line_items_result: line_items_result,
        summary_result: summary_result
      }
    after
      File.rm(logo_path)
    end
  end

  @spec pdf_binary() :: binary()
  def pdf_binary do
    %{pdf: pdf} = build_document()
    Tincture.export(pdf)
  end

  @spec write_pdf(Path.t()) :: Path.t()
  def write_pdf(path \\ "tmp/invoice_showcase.pdf") when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pdf_binary())
    path
  end

  defp invoice_line_items do
    [
      ["Code", "Description", "Qty", "Unit", "Amount"],
      ["A100", "Implementation planning workshop", "2", "$850.00", "$1,700.00"],
      ["A240", "API integration and QA", "18", "$125.00", "$2,250.00"],
      ["B015", "Stakeholder training session", "1", "$420.00", "$420.00"],
      ["B700", "Priority support retainer", "1", "$200.00", "$200.00"],
      ["C310", "Change request bundle", "2", "$95.00", "$190.00"],
      ["", "TOTAL DUE", "", "", "$4,935.28"]
    ]
  end

  defp invoice_totals do
    [
      ["Subtotal", "$4,760.00"],
      ["Discount", "-$100.00"],
      ["Tax", "$275.28"],
      ["TOTAL DUE", "$4,935.28"]
    ]
  end

  defp draw_header_footer(pdf, page, total) do
    pdf
    |> Tincture.set_font("Helvetica-Bold", 11)
    |> Tincture.text_at(48, 758, "ACME Industrial Systems - Invoice #{page}/#{total}")
    |> Tincture.set_font("Helvetica", 9)
    |> Tincture.text_at(48, 30, "Confidential - Page #{page} of #{total}")
  end

  defp write_test_logo_png! do
    path =
      Path.join(
        System.tmp_dir!(),
        "tincture_invoice_logo_#{System.unique_integer([:positive])}.png"
      )

    :ok = File.write(path, test_logo_png_binary())
    path
  end

  defp test_logo_png_binary do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>
    idat = :zlib.compress(<<0, 0, 90, 160, 245>>)

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
