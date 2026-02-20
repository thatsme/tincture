defmodule ExGuten.RenderInvoiceShowcaseScript do
  alias ExGuten.Showcase.Invoice

  def run do
    out_path =
      case System.argv() do
        [path | _rest] ->
          path

        [] ->
          System.get_env("EX_GUTEN_SHOWCASE_OUT", "tmp/invoice_showcase.pdf")
      end

    path = Invoice.write_pdf(out_path)
    IO.puts("Wrote invoice showcase PDF: #{path}")
  end
end

ExGuten.RenderInvoiceShowcaseScript.run()
