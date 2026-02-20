defmodule ExGuten.RenderMarketingPosterShowcaseScript do
  alias ExGuten.Showcase.MarketingPoster

  def run do
    out_path =
      case System.argv() do
        [path | _rest] ->
          path

        [] ->
          System.get_env("EX_GUTEN_SHOWCASE_OUT", "tmp/marketing_poster_showcase.pdf")
      end

    path = MarketingPoster.write_pdf(out_path)
    IO.puts("Wrote marketing poster showcase PDF: #{path}")
  end
end

ExGuten.RenderMarketingPosterShowcaseScript.run()
