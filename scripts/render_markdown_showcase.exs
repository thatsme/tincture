defmodule Tincture.RenderMarkdownShowcaseScript do
  alias Tincture.Showcase.MarkdownDoc

  def run do
    {markdown_path, out_path} =
      case System.argv() do
        [source_path, target_path | _rest] ->
          {source_path, target_path}

        [target_path] ->
          {MarkdownDoc.sample_markdown_path(), target_path}

        [] ->
          {
            MarkdownDoc.sample_markdown_path(),
            System.get_env("EX_GUTEN_SHOWCASE_OUT", "tmp/markdown_showcase.pdf")
          }
      end

    path = MarkdownDoc.write_pdf_from_file(markdown_path, out_path)
    IO.puts("Wrote markdown showcase PDF from #{markdown_path}: #{path}")
  end
end

Tincture.RenderMarkdownShowcaseScript.run()
