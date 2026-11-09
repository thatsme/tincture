defmodule Tincture.InvoiceShowcaseTest do
  use ExUnit.Case

  alias Tincture.Showcase.Invoice

  test "complex invoice showcase renders end-to-end with layout, typography, tables, image, metadata, and bookmarks" do
    %{
      doc_result: doc_result,
      line_items_result: line_items_result,
      summary_result: summary_result
    } =
      Invoice.build_document()

    pdf_binary = Invoice.pdf_binary()
    content = Tincture.Test.PDFObjects.decoded(pdf_binary)

    assert doc_result.pages_used == 2
    assert line_items_result.rows == 7
    assert line_items_result.columns == 5
    assert summary_result.rows == 4
    assert summary_result.columns == 2

    assert content =~ "/Count 2"
    assert content =~ "/Subtype /Image"
    assert content =~ "/Type /Outlines"
    assert content =~ "/Title (Invoice Showcase Demo)"
    assert content =~ "/Title (Invoice Summary)"
    assert content =~ "/Title (Terms and Remittance)"
    assert content =~ "(INVOICE) Tj"
    assert content =~ "(Invoice # INV-2026-0042) Tj"
    assert content =~ "(TOTAL DUE) Tj"
    assert content =~ "(ACME Industrial Systems - Invoice 1/2) Tj"
    assert content =~ "(ACME Industrial Systems - Invoice 2/2) Tj"
    assert content =~ "(Confidential - Page 1 of 2) Tj"
    assert content =~ "(Confidential - Page 2 of 2) Tj"
  end
end
