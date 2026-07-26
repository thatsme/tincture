defmodule Tincture.RenderMultiFontReportShowcaseScript do
  alias Tincture.Showcase.MultiFontReport

  def run do
    out_path =
      case System.argv() do
        [path | _rest] ->
          path

        [] ->
          System.get_env("EX_GUTEN_SHOWCASE_OUT", "tmp/multi_font_report_showcase.pdf")
      end

    path = MultiFontReport.write_pdf(out_path)
    IO.puts("Wrote multi-font report showcase PDF: #{path}")
  end
end

Tincture.RenderMultiFontReportShowcaseScript.run()
