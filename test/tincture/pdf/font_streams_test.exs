defmodule Tincture.PDF.FontStreamsTest do
  @moduledoc """
  Font discovery and subsetting walk a list of content streams, not a list of
  pages. The `*_by_font` collectors take `{stream_key, operations}` pairs, so
  a stream of any kind contributes the fonts and characters it draws.

  The published `FontEmbed.build_embedded_font_objects/3` still takes page
  numbers, and gives the same result as the stream-list version on the
  corresponding `{:page, n}` keys.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF
  alias Tincture.PDF.FontEmbed
  alias Tincture.Test.MeasurableFont

  # Plain data: no XObject exists yet, but the collectors read only the
  # operations, so the key's kind does not matter to them.
  @streams [
    {{:page, 1}, [{:text_at, 0, 0, "ab", {"Shared", 10}}, :stroke]},
    {{:xobject, "Badge"},
     [
       {:text_at, 0, 0, "Q", {"OnlyInXObject", 10}},
       {:text_at_rotated, 0, 0, 90, "bc", {"Shared", 10}}
     ]},
    {{:page, 2}, [{:text_at, 0, 0, "a", {"Shared", 12}}]}
  ]

  describe "the *_by_font collectors over a stream list that includes an XObject" do
    test "a font used only in the XObject stream is discovered, with its characters" do
      assert FontEmbed.used_char_codes_by_font(@streams)["OnlyInXObject"] == [?Q]
      assert FontEmbed.scalar_codepoints_by_font(@streams)["OnlyInXObject"] == [?Q]
      assert FontEmbed.used_cids_by_font(@streams)["OnlyInXObject"] == [?Q]
      assert FontEmbed.unicode_text_by_font(@streams)["OnlyInXObject"] == false

      assert [{_glyph, _unicode}] =
               FontEmbed.to_unicode_mappings_by_font(@streams)["OnlyInXObject"]

      assert FontEmbed.variation_sequences_by_font(@streams)["OnlyInXObject"] == []
    end

    test "a font used in pages and the XObject is counted once, with every character" do
      used = FontEmbed.used_char_codes_by_font(@streams)

      assert Map.keys(used) |> Enum.sort() == ["OnlyInXObject", "Shared"]
      assert used["Shared"] == [?a, ?b, ?c]
      assert FontEmbed.scalar_codepoints_by_font(@streams)["Shared"] == [?a, ?b, ?c]
      assert FontEmbed.used_cids_by_font(@streams)["Shared"] == [?a, ?b, ?c]
      assert length(FontEmbed.to_unicode_mappings_by_font(@streams)["Shared"]) == 3
    end

    test "dropping the XObject stream drops the font only it used" do
      pages_only = Enum.filter(@streams, &match?({{:page, _}, _}, &1))

      refute Map.has_key?(FontEmbed.used_char_codes_by_font(pages_only), "OnlyInXObject")
      assert FontEmbed.used_char_codes_by_font(pages_only)["Shared"] == [?a, ?b]
    end
  end

  describe "PDF.stream_keys/1" do
    test "is the page keys, in page order" do
      pdf = Tincture.new() |> Tincture.add_page() |> Tincture.add_page() |> Tincture.set_page(1)
      assert PDF.stream_keys(pdf) == [{:page, 1}, {:page, 2}, {:page, 3}]
    end
  end

  describe "the published build_embedded_font_objects/3" do
    setup do
      path = MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)

      pdf =
        Tincture.new()
        |> Tincture.register_ttf_font("Measurable", path)
        |> Tincture.set_font("Measurable", 10)
        |> Tincture.text_at(72, 700, "AB")
        |> Tincture.add_page()
        |> Tincture.set_font("Measurable", 10)
        |> Tincture.text_at(72, 700, "B A")

      %{pdf: pdf}
    end

    test "with page numbers, gives what the stream-list version gives on {:page, n}", %{pdf: pdf} do
      by_pages = FontEmbed.build_embedded_font_objects(pdf, PDF.page_numbers(pdf), 7)
      by_streams = FontEmbed.build_embedded_font_objects_for_streams(pdf, PDF.stream_keys(pdf), 7)

      assert by_pages == by_streams
      assert {%{"Measurable" => _ref}, [_ | _], _modes, _next} = by_pages
    end

    test "with a subset of the pages, still agrees", %{pdf: pdf} do
      assert FontEmbed.build_embedded_font_objects(pdf, [2], 7) ==
               FontEmbed.build_embedded_font_objects_for_streams(pdf, [{:page, 2}], 7)
    end
  end
end
