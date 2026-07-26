defmodule Tincture.MarketingPosterShowcaseTest do
  use ExUnit.Case

  alias Tincture.Showcase.MarketingPoster

  test "graphics-heavy poster showcase renders vector graphics, image, and strong typography" do
    %{pdf: pdf, pages: pages} = MarketingPoster.build_document()
    pdf_binary = Tincture.export(pdf)

    assert pages == 1
    assert page_count(pdf_binary) == 1
    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Title (Marketing Poster Showcase Demo)"
    assert pdf_binary =~ "/Title (Launch Week)"
    assert pdf_binary =~ "(Launch Week 2026) Tj"
    assert pdf_binary =~ "(VECTOR GRAPHICS + IMAGES + TYPE) Tj"
    assert pdf_binary =~ "(SCAN FOR DEMO) Tj"
  end

  defp page_count(pdf_binary) do
    [_, count] = Regex.run(~r{/Type /Pages /Kids \[[^\]]+\] /Count (\d+)}, pdf_binary)
    String.to_integer(count)
  end
end
