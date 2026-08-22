# A minimal PDF/UA-declaring document with one tagged link.
Code.require_file("examples/support/fonts.exs", ".")

{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(title: "Link probe", author: "probe", subject: "link conformance")
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)

pdf
|> Tincture.set_language("en-GB")
|> Tincture.tag(:document, fn doc ->
  doc
  |> Tincture.tag(:h1, fn p ->
    p |> Tincture.set_font(body, 18) |> Tincture.text_at(50, 780, "Link probe")
  end)
  |> Tincture.tag(:p, fn p ->
    p |> Tincture.set_font(body, 12) |> Tincture.text_at(50, 740, "A paragraph of body text.")
  end)
  |> Tincture.tag(:link, fn p ->
    p
    |> Tincture.set_font(body, 12)
    |> Tincture.text_link(50, 700, "Elixir", {:url, "https://elixir-lang.org"})
  end)
end)
|> Tincture.export()
|> then(&File.write!(System.get_env("OUT", "_build/ua-link-probe.pdf"), &1))
