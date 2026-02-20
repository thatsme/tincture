defmodule ExGuten.InvoiceShowcaseTest do
  use ExUnit.Case

  alias ExGuten.Showcase.Invoice

  test "complex invoice showcase renders end-to-end with layout, typography, tables, image, metadata, and bookmarks" do
    %{
      doc_result: doc_result,
      line_items_result: line_items_result,
      summary_result: summary_result
    } =
      Invoice.build_document()

    pdf_binary = Invoice.pdf_binary()

    assert doc_result.pages_used == 2
    assert line_items_result.rows == 7
    assert line_items_result.columns == 5
    assert summary_result.rows == 4
    assert summary_result.columns == 2

    assert pdf_binary =~ "/Count 2"
    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Type /Outlines"
    assert pdf_binary =~ "/Title (Invoice Showcase Demo)"
    assert pdf_binary =~ "/Title (Invoice Summary)"
    assert pdf_binary =~ "/Title (Terms and Remittance)"
    assert pdf_binary =~ "(INVOICE) Tj"
    assert pdf_binary =~ "(Invoice # INV-2026-0042) Tj"
    assert pdf_binary =~ "(TOTAL DUE) Tj"
    assert pdf_binary =~ "(ACME Industrial Systems - Invoice 1/2) Tj"
    assert pdf_binary =~ "(ACME Industrial Systems - Invoice 2/2) Tj"
    assert pdf_binary =~ "(Confidential - Page 1 of 2) Tj"
    assert pdf_binary =~ "(Confidential - Page 2 of 2) Tj"
  end
end
