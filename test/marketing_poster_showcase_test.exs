defmodule Tincture.MarketingPosterShowcaseTest do
  use ExUnit.Case

  alias Tincture.Showcase.MarketingPoster

  test "graphics-heavy poster showcase renders vector graphics, image, and strong typography" do
    %{pdf: pdf, pages: pages} = MarketingPoster.build_document()
    pdf_binary = Tincture.export(pdf)
    content = Tincture.Test.PDFObjects.decoded(pdf_binary)

    assert pages == 1
    assert page_count(pdf_binary) == 1
    assert content =~ "/Subtype /Image"
    assert content =~ "/Title (Marketing Poster Showcase Demo)"
    assert content =~ "/Title (Launch Week)"
    assert content =~ "(Launch Week 2026) Tj"
    assert content =~ "(VECTOR GRAPHICS + IMAGES + TYPE) Tj"
    assert content =~ "(SCAN FOR DEMO) Tj"
  end

  defp page_count(pdf_binary) do
    [_, count] = Regex.run(~r{/Type /Pages /Kids \[[^\]]+\] /Count (\d+)}, pdf_binary)
    String.to_integer(count)
  end
end
