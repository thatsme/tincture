defmodule Tincture.Font.SubsetEmptyGlyphTest do
  @moduledoc """
  Regression tests for subsetting text that includes a glyph with no outline.

  In TrueType a glyph with no outline is encoded as `loca[i] == loca[i+1]`,
  i.e. zero bytes of glyph data. This is legal and extremely common: the space
  character does it, as does every non-marking character.

  Treating that as malformed aborts the entire subset and silently falls back to
  embedding the full font. Because almost every real string contains a space,
  that defeated subsetting for essentially all real text — the fallback was only
  visible as a log warning and a PDF several times larger than it should be.
  """
  use ExUnit.Case, async: true

  # Glyph 1 = "A" (a real outline), glyph 3 = a deliberately empty glyph that the
  # cmap maps the space character to. loca's last two entries are equal, which is
  # how "no outline" is spelled.
  defp empty_glyph_ttf_binary do
    outline = fn x_min, y_min, x_max, y_max ->
      <<1::16-signed-big, x_min::16-signed-big, y_min::16-signed-big, x_max::16-signed-big,
        y_max::16-signed-big>>
    end

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 300::16-big, 0::16-signed-big>>},
      # 'A' -> glyph 1, 'B' -> glyph 2, ' ' -> glyph 3 (empty)
      {"cmap", cmap_format0([{?A, 1}, {?B, 2}, {?\s, 3}])},
      # Short loca, so stored values are byte offsets / 2.
      # Glyph 3 spans 30..30 — zero bytes.
      {"loca", <<0::16-big, 5::16-big, 10::16-big, 15::16-big, 15::16-big>>},
      {"glyf",
       <<outline.(0, -20, 500, 700)::binary, outline.(0, -10, 700, 750)::binary,
         outline.(0, -30, 900, 820)::binary>>}
    ])
  end

  defp write_empty_glyph_ttf! do
    path =
      Path.join(
        System.tmp_dir!(),
        "tincture_empty_glyph_#{System.unique_integer([:positive])}.ttf"
      )

    :ok = File.write(path, empty_glyph_ttf_binary())
    path
  end

  defp embedded_font_length1(path, text) do
    binary =
      Tincture.new()
      |> Tincture.register_ttf_font("EmptyGlyphProbe", path, subset: :used_text)
      |> Tincture.add_page()
      |> Tincture.set_font("EmptyGlyphProbe", 14)
      |> Tincture.text_at(50, 700, text)
      |> Tincture.export()

    case Regex.run(~r/\/Length1\s+(\d+)/, binary) do
      [_, length] -> String.to_integer(length)
      _ -> flunk("expected /Length1 for the embedded FontFile stream")
    end
  end

  defp cmap_format0(entries) do
    glyph_ids =
      entries
      |> Enum.reduce(:array.new(256, default: 0), fn {code, glyph_id}, acc ->
        :array.set(code, glyph_id, acc)
      end)
      |> :array.to_list()
      |> :erlang.list_to_binary()

    subtable = <<0::16-big, 262::16-big, 0::16-big, glyph_ids::binary>>
    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp build_ttf(tables) do
    num_tables = length(tables)

    header =
      <<0x0001_0000::32-big, num_tables::16-big, 0::16-big, 0::16-big, 0::16-big>>

    base_offset = byte_size(header) + num_tables * 16

    {records, binaries, _next} =
      Enum.reduce(tables, {[], [], base_offset}, fn {tag, data}, {recs, bins, offset} ->
        record = <<tag::binary-size(4), 0::32-big, offset::32-big, byte_size(data)::32-big>>
        {recs ++ [record], bins ++ [data], offset + byte_size(data)}
      end)

    IO.iodata_to_binary([header, records, binaries])
  end

  setup do
    path = write_empty_glyph_ttf!()
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  # Size alone is not a reliable fallback detector on a fixture this small: the
  # fixed cost of rebuilding and realigning sfnt tables means a legitimate
  # subset can come out the same size as, or larger than, the source. The
  # fallback path logs, so assert on that instead. The real-font cases at the
  # bottom cover the actual size win.
  defp subset_fallback_log(path, text) do
    ExUnit.CaptureLog.capture_log(fn -> embedded_font_length1(path, text) end)
  end

  test "text containing an empty glyph does not fall back", %{path: path} do
    refute subset_fallback_log(path, "A B") =~ "subset fallback to full font",
           "subsetting fell back to the full font because the space glyph has no outline"
  end

  test "a lone empty glyph does not fall back", %{path: path} do
    refute subset_fallback_log(path, " ") =~ "subset fallback to full font"
  end

  test "adding an empty glyph does not change the subset size", %{path: path} do
    # The space glyph contributes no outline bytes, so including it must not grow
    # the subset at all — and certainly must not jump to the full font size.
    assert embedded_font_length1(path, "AB") == embedded_font_length1(path, "A B")
  end

  # A real font is large enough to show the actual payoff, which the synthetic
  # fixture above is too small to demonstrate. Skipped where the font is absent
  # (CI runners, non-macOS), so this never turns into a spurious failure.
  describe "with a real system font" do
    @system_font "/System/Library/Fonts/Supplemental/Andale Mono.ttf"

    setup do
      if File.exists?(@system_font) do
        {:ok, system_font: @system_font, system_full_size: byte_size(File.read!(@system_font))}
      else
        {:ok, skip: true}
      end
    end

    test "a sentence with spaces subsets to a fraction of the full font", context do
      if context[:skip] do
        :ok
      else
        subset = embedded_font_length1(context.system_font, "Embedded TTF: Hello Omega")

        assert subset < context.system_full_size * 0.5,
               "expected a large subset win, got #{subset} of #{context.system_full_size}"
      end
    end

    test "spaces cost almost nothing versus the same text without them", context do
      if context[:skip] do
        :ok
      else
        without = embedded_font_length1(context.system_font, "HelloWorld")
        with_spaces = embedded_font_length1(context.system_font, "Hello World")

        assert with_spaces < without * 1.1,
               "adding a space grew the subset from #{without} to #{with_spaces}"
      end
    end
  end
end
