# Generates the "before" evidence for the /OBJR conformance fix.
# Two pages, one tagged link on each, so a numbering bug cannot hide behind
# a single counter that is coincidentally zero.
pdf =
  Tincture.new()
  |> Tincture.set_language("en-GB")
  |> Tincture.tag(:document, fn pdf ->
    pdf
    |> Tincture.tag(:link, fn p ->
      Tincture.text_link(p, 72, 700, "first target", {:url, "https://example.org/one"})
    end)
    |> Tincture.add_page()
    |> Tincture.tag(:link, fn p ->
      Tincture.text_link(p, 72, 700, "second target", {:url, "https://example.org/two"})
    end)
  end)

path = "_build/objr-smoke.pdf"
File.write!(path, Tincture.export(pdf))
IO.puts("wrote #{path}")
