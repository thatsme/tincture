defmodule Tincture.MissingGlyphWarningTest do
  # Not async: these tests capture stderr, which is shared by the whole VM, and
  # a test running alongside that writes to it would land in the capture.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Tincture.Layout.Box
  alias Tincture.Layout.Table
  alias Tincture.Layout.Template
  alias Tincture.Typography.RichText

  # W9. Text drawn in an embedded font that has no glyph for one of its
  # characters is written as glyph 0 and drawn as a blank. Every public
  # function that draws text warns once per call, listing each such
  # character once. Liberation Sans has no "✓" (U+2713) and no "★" (U+2605).

  @font "examples/fonts/LiberationSans-Regular.ttf"

  @one ~s[font "Sans" has no glyph for "✓" (U+2713), which is drawn as a blank. ] <>
         "Register a font that covers it, or remove the character. This will raise in 0.4.0."

  @several ~s[font "Sans" has no glyph for "✓" (U+2713), "★" (U+2605), which are drawn as ] <>
             "blanks. Register a font that covers them, or remove the characters. This will " <>
             "raise in 0.4.0."

  defp sans do
    Tincture.new()
    |> Tincture.register_ttf_font("Sans", @font)
    |> Tincture.set_font("Sans", 12)
  end

  defp rich(text), do: RichText.from_plain(text, font: "Sans", size: 12)

  # Non-ASCII as character references: parse_xml/1 does not accept a literal
  # "✓" or "№" (xmerl's bad_character).
  defp xml(text) do
    body =
      text
      |> String.to_charlist()
      |> Enum.map_join(fn
        codepoint when codepoint > 127 -> "&##{codepoint};"
        codepoint -> <<codepoint::utf8>>
      end)

    ~s(<document><body font="Sans" size="12">#{body}</body></document>)
  end

  # Each public function that draws text, as a function of the text it draws.
  # The layout functions break the text into words, so the characters arrive
  # in several text operations, and the call must still warn once.
  defp drawers do
    [
      {"text_at/4", &Tincture.text_at(&1, 50, 700, &2)},
      {"text_at_rotated/5", &Tincture.text_at_rotated(&1, 50, 700, 30, &2)},
      {"text_at_with_fallback/5",
       &Tincture.text_at_with_fallback(&1, 50, 700, &2, ["Helvetica"])},
      {"text_at_with_fallback/6",
       &Tincture.text_at_with_fallback(&1, 50, 700, &2, [], kerning: :gpos)},
      {"text_at_rotated_with_fallback/6",
       &Tincture.text_at_rotated_with_fallback(&1, 50, 700, 30, &2)},
      {"text_at_rotated_with_fallback/7",
       &Tincture.text_at_rotated_with_fallback(&1, 50, 700, 30, &2, [], shaping: :latin_ligatures)},
      {"text_link/5", &Tincture.text_link(&1, 50, 700, &2, "https://example.com")},
      {"text_link/6",
       &Tincture.text_link(&1, 50, 700, &2, "https://example.com", color: {0, 0, 1})},
      {"text_paragraph/6", &Tincture.text_paragraph(&1, 50, 700, rich(&2), 120)},
      {"Layout.Box.flow_text/7", &elem(Box.flow_text(&1, 50, 700, 120, 300, rich(&2)), 0)},
      {"Layout.Box.flow_across_boxes/4",
       &elem(Box.flow_across_boxes(&1, rich(&2), [{50, 700, 60, 40}, {50, 600, 60, 300}]), 0)},
      {"Layout.Table.render/6",
       &elem(
         Table.render(&1, 50, 700, [150, 150], [["x " <> &2, "y"], ["z", &2]], font: "Sans"),
         0
       )},
      {"Layout.Template.render/4", &elem(Template.render(&1, Template.new(), rich(&2)), 0)},
      {"Layout.Template.render_document/4",
       &elem(Template.render_document(&1, Template.new(), rich(&2)), 0)},
      {"Layout.Template.render_xml_document/3",
       fn pdf, text ->
         {:ok, pdf, _result} = Template.render_xml_document(pdf, xml(text))
         pdf
       end}
    ]
  end

  defp warnings(fun) do
    {_pdf, stderr} = with_io(:stderr, fun)
    Regex.scan(~r/warning: (.*?)\n/, stderr, capture: :all_but_first) |> List.flatten()
  end

  test "every function that draws text warns once, with the full message, for one character" do
    for {name, draw} <- drawers() do
      text = "one ✓ two three ✓ four"
      assert warnings(fn -> draw.(sans(), text) end) == [@one], name
    end
  end

  test "every function that draws text warns once, listing several characters once each" do
    for {name, draw} <- drawers() do
      text = "one ✓ two ★ three ✓ four ★"
      assert warnings(fn -> draw.(sans(), text) end) == [@several], name
    end
  end

  test "text the font covers does not warn, in any function" do
    for {name, draw} <- drawers() do
      assert warnings(fn -> draw.(sans(), "Ada Lovelace, № 1843") end) == [], name
    end
  end

  test "a standard-14 font does not warn, whatever the text" do
    pdf = Tincture.set_font(Tincture.new(), "Helvetica", 12)

    assert warnings(fn -> Tincture.text_at(pdf, 50, 700, "plain text") end) == []
    assert warnings(fn -> Tincture.text_at(pdf, 50, 700, "★") end) == []
  end

  test "a variation selector is not a missing character" do
    assert warnings(fn -> Tincture.text_at(sans(), 50, 700, "a️ b") end) == []
  end

  describe "a default-ignorable code point" do
    # The fixture font maps only "A", "B" and space, so it has no glyph for any
    # of these: the test would pass without the exemption only if the font
    # covered them, and it does not.
    setup do
      path = Tincture.Test.MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)

      pdf =
        Tincture.new()
        |> Tincture.register_ttf_font("Probe", path)
        |> Tincture.set_font("Probe", 12)

      {:ok, pdf: pdf}
    end

    test "ZWJ, ZWNJ, ZWSP and a soft hyphen are not missing characters", %{pdf: pdf} do
      for {name, character} <- [
            zwj: "‍",
            zwnj: "‌",
            zwsp: "​",
            soft_hyphen: "­"
          ] do
        text = "A" <> character <> "B"
        assert warnings(fn -> Tincture.text_at(pdf, 50, 700, text) end) == [], "#{name}"
      end
    end

    test "beside a character that is really missing, only that one is named", %{pdf: pdf} do
      text = "A‍B‌ A​C­B"

      assert warnings(fn -> Tincture.text_at(pdf, 50, 700, text) end) == [
               ~s[font "Probe" has no glyph for "C" (U+0043), which is drawn as a blank. ] <>
                 "Register a font that covers it, or remove the character. This will raise " <>
                 "in 0.4.0."
             ]
    end

    test "a character the cmap maps to glyph 0 is missing, as one it does not list", %{pdf: pdf} do
      # The fixture's cmap is format 0: it lists every byte, "C" among them,
      # with glyph 0 for the ones the font lacks.
      assert warnings(fn -> Tincture.text_at(pdf, 50, 700, "AC") end) == [
               ~s[font "Probe" has no glyph for "C" (U+0043), which is drawn as a blank. ] <>
                 "Register a font that covers it, or remove the character. This will raise " <>
                 "in 0.4.0."
             ]
    end

    test "the exempt set is Unicode 17.0.0's Default_Ignorable_Code_Point: 4174 code points" do
      exempt = Enum.filter(0..0x10FFFF, &Tincture.PDF.Ops.default_ignorable?/1)

      assert length(exempt) == 4174
      assert 0x00AD in exempt and 0x200D in exempt and 0xFE0F in exempt and 0xE01EF in exempt
      refute 0x0301 in exempt or 0x2713 in exempt or 0x0020 in exempt
    end
  end

  test "a character missing from two fonts in one call is listed under each" do
    pdf =
      Tincture.register_ttf_font(sans(), "Serif", "examples/fonts/LiberationSerif-Regular.ttf")

    rich =
      RichText.from_runs([
        %{text: "one ✓", font: "Sans", size: 12},
        %{text: " two ★", font: "Serif", size: 12}
      ])

    assert warnings(fn -> Tincture.text_paragraph(pdf, 50, 700, rich, 300) end) == [
             ~s[font "Sans" has no glyph for "✓" (U+2713); font "Serif" has no glyph for ] <>
               ~s["★" (U+2605), which are drawn as blanks. Register a font that covers ] <>
               "them, or remove the characters. This will raise in 0.4.0."
           ]
  end

  test "the text is written as before: the missing character keeps its code" do
    {binary, _stderr} =
      with_io(:stderr, fn -> sans() |> Tincture.text_at(50, 700, "a ✓ b") |> Tincture.export() end)

    assert binary =~ "<00610020271300200062> Tj"
  end

  describe "our own documents" do
    test "no showcase draws a character its font cannot draw" do
      for build <- [
            fn -> Tincture.Showcase.Invoice.build_document() end,
            fn -> Tincture.Showcase.BankStatement.build_document() end,
            fn -> Tincture.Showcase.MarkdownDoc.build_document() end,
            fn -> Tincture.Showcase.MarketingPoster.build_document() end,
            fn -> Tincture.Showcase.MultiFontReport.build_document() end
          ] do
        refute capture_io(:stderr, build) =~ "has no glyph"
      end
    end
  end
end
