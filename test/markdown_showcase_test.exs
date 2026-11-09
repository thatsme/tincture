defmodule Tincture.MarkdownShowcaseTest do
  use ExUnit.Case

  alias Tincture.Showcase.MarkdownDoc

  test "markdown showcase renders a markdown subset into a paginated PDF" do
    markdown = """
    # Product Notes

    This document is generated from markdown and rendered with Tincture.

    ## Roadmap
    - Ship Hex package publishing
    - Add richer showcase assets
    - Document release workflow

    Visit [project docs](https://example.com/docs) for more details.

    ```elixir
    def add(a, b) do
      a + b
    end
    ```
    """

    %{pdf: pdf, pages: pages} = MarkdownDoc.build_document(markdown)
    pdf_binary = Tincture.export(pdf)
    content = Tincture.Test.PDFObjects.decoded(pdf_binary)

    assert pages == 1
    assert page_count(pdf_binary) == 1
    assert content =~ "/Title (Markdown Showcase Demo)"
    assert content =~ "/Title (Product Notes)"
    assert content =~ "(Product Notes) Tj"
    assert content =~ "(Roadmap) Tj"

    assert content =~ "(Visit) Tj"
    assert content =~ "(project) Tj"
    assert content =~ "https://example.com/docs"
    assert content =~ "(Ship) Tj"
    assert content =~ "(def add\\(a, b\\) do) Tj"
    assert content =~ "(  a + b) Tj"
  end

  test "markdown showcase can render from a markdown file path" do
    markdown_path =
      Path.join(System.tmp_dir!(), "tincture_markdown_#{System.unique_integer([:positive])}.md")

    out_path =
      Path.join(System.tmp_dir!(), "tincture_markdown_#{System.unique_integer([:positive])}.pdf")

    File.write!(markdown_path, "# File Input\n\n- item one\n- item two\n")

    try do
      assert MarkdownDoc.write_pdf_from_file(markdown_path, out_path) == out_path
      assert File.exists?(out_path)
    after
      File.rm(markdown_path)
      File.rm(out_path)
    end
  end

  defp page_count(pdf_binary) do
    [_, count] = Regex.run(~r{/Type /Pages /Kids \[[^\]]+\] /Count (\d+)}, pdf_binary)
    String.to_integer(count)
  end
end
