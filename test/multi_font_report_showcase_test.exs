defmodule Tincture.MultiFontReportShowcaseTest do
  use ExUnit.Case

  alias Tincture.Showcase.MultiFontReport

  test "multi-font report showcase renders headings, narrative text, code block, and table across pages" do
    %{pdf: pdf, pages: pages, metrics_result: metrics_result} = MultiFontReport.build_document()
    pdf_binary = Tincture.export(pdf)

    assert pages == 2
    assert metrics_result.rows == 5
    assert metrics_result.columns == 4

    assert page_count(pdf_binary) == 2
    assert pdf_binary =~ "/Title (Multi-Font Report Showcase Demo)"
    assert pdf_binary =~ "/Title (Executive Summary)"
    assert pdf_binary =~ "/Title (Implementation Appendix)"
    assert pdf_binary =~ "(Helvetica headline drives hierarchy.) Tj"
    assert pdf_binary =~ "(Times body copy demonstrates readable long-form text.) Tj"
    assert pdf_binary =~ "(Courier code block preserves alignment.) Tj"
    assert pdf_binary =~ "(Kerning and line-break modes can be tuned per block.) Tj"
  end

  defp page_count(pdf_binary) do
    [_, count] = Regex.run(~r{/Type /Pages /Kids \[[^\]]+\] /Count (\d+)}, pdf_binary)
    String.to_integer(count)
  end
end
