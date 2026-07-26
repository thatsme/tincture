defmodule Tincture.Font.TTFMetricsTest do
  @moduledoc """
  Malformed-table handling in the `Font.TTF` coordinator.

  `parse_basic_tables/1` fetches each required table and hands it to a parser
  that pattern-matches a fixed byte layout. Every one of those parsers has an
  `:error` fallback for a table that is present but too short, and until now
  none of them ran: the existing tests all build well-formed fonts.

  These build fonts that are structurally valid — real sfnt directory, all
  required tables present — but with one table truncated at a time, which is
  what a corrupt download or a bad subsetter actually produces. The whole parse
  must fail cleanly rather than raising.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.TTF

  # head is the fussiest table: indexToLocFormat sits at offset 50, so a head
  # shorter than 52 bytes fails even though everything before it is present.

  defp head(opts \\ []) do
    units_per_em = Keyword.get(opts, :units_per_em, 1000)
    mac_style = Keyword.get(opts, :mac_style, 0)
    index_to_loc = Keyword.get(opts, :index_to_loc_format, 0)
    bbox = Keyword.get(opts, :bbox, {0, 0, 100, 100})
    {x_min, y_min, x_max, y_max} = bbox

    <<0::size(18)-unit(8), units_per_em::16-big, 0::size(16)-unit(8), x_min::16-signed-big,
      y_min::16-signed-big, x_max::16-signed-big, y_max::16-signed-big, mac_style::16-big,
      0::size(4)-unit(8), index_to_loc::16-signed-big>>
  end

  defp hhea(opts \\ []) do
    number_of_h_metrics = Keyword.get(opts, :number_of_h_metrics, 1)
    ascender = Keyword.get(opts, :ascender, 800)
    descender = Keyword.get(opts, :descender, -200)

    <<0::32-big, ascender::16-signed-big, descender::16-signed-big, 0::16-signed-big, 0::16-big,
      0::size(22)-unit(8), number_of_h_metrics::16-big>>
  end

  defp maxp(num_glyphs \\ 1), do: <<0x0001_0000::32-big, num_glyphs::16-big>>
  defp hmtx(count \\ 1), do: String.duplicate(<<500::16-big, 0::16-signed-big>>, count)

  defp build_font(tables) do
    n = length(tables)
    header = <<0x0001_0000::32-big, n::16-big, 0::16-big, 0::16-big, 0::16-big>>
    base = byte_size(header) + n * 16

    {records, bodies, _} =
      Enum.reduce(tables, {[], [], base}, fn {tag, data}, {recs, bods, offset} ->
        record = <<tag::binary-size(4), 0::32-big, offset::32-big, byte_size(data)::32-big>>
        {recs ++ [record], bods ++ [data], offset + byte_size(data)}
      end)

    IO.iodata_to_binary([header, records, bodies])
  end

  # A structurally valid font; `overrides` replaces individual table bodies.
  defp font(overrides \\ %{}) do
    defaults = [
      {"head", head()},
      {"hhea", hhea()},
      {"maxp", maxp()},
      {"hmtx", hmtx()}
    ]

    default_tags = Enum.map(defaults, &elem(&1, 0))
    # Overrides may introduce tables the defaults do not carry (a CFF table,
    # say), so append anything unrecognised rather than silently dropping it.
    extra = for {tag, data} <- overrides, tag not in default_tags, data != :drop, do: {tag, data}

    defaults
    |> Enum.map(fn {tag, data} -> {tag, Map.get(overrides, tag, data)} end)
    |> Kernel.++(extra)
    |> Enum.reject(fn {_tag, data} -> data == :drop end)
    |> build_font()
  end

  describe "a well-formed font parses" do
    test "reads the basic metrics" do
      assert {:ok, metrics} = TTF.parse_basic_tables(font())

      assert metrics.units_per_em == 1000
      assert metrics.num_glyphs == 1
      # head carries its own bounding box; font_bbox is derived from glyf or
      # CFF outlines, which this minimal font has none of.
      assert metrics.head_bbox == {0, 0, 100, 100}
      assert metrics.font_bbox == nil
    end

    test "reads the style bits out of head.macStyle" do
      # Bit 0 is bold, bit 1 is italic.
      assert {:ok, plain} = TTF.parse_basic_tables(font(%{"head" => head(mac_style: 0)}))
      refute plain.italic
      refute plain.bold

      assert {:ok, italic} = TTF.parse_basic_tables(font(%{"head" => head(mac_style: 2)}))
      assert italic.italic

      assert {:ok, bold} = TTF.parse_basic_tables(font(%{"head" => head(mac_style: 1)}))
      assert bold.bold
    end

    test "reads vertical metrics from hhea" do
      assert {:ok, metrics} =
               TTF.parse_basic_tables(font(%{"hhea" => hhea(ascender: 750, descender: -250)}))

      assert metrics.hhea_ascender == 750
      assert metrics.hhea_descender == -250
    end

    test "reads a negative bounding box" do
      bbox = {-50, -200, 1000, 900}
      assert {:ok, metrics} = TTF.parse_basic_tables(font(%{"head" => head(bbox: bbox)}))
      assert metrics.head_bbox == bbox
    end
  end

  describe "missing required tables" do
    test "a font missing any required table fails" do
      for tag <- ["head", "hhea", "maxp", "hmtx"] do
        assert TTF.parse_basic_tables(font(%{tag => :drop})) == :error,
               "a font with no #{tag} table should not parse"
      end
    end

    test "a font with no table directory at all fails" do
      assert TTF.parse_basic_tables(<<>>) == :error
      assert TTF.parse_basic_tables(<<0x0001_0000::32-big>>) == :error
    end

    test "a table directory declaring more tables than it holds fails" do
      # Says four tables, supplies one record's worth of bytes.
      assert TTF.parse_basic_tables(
               <<0x0001_0000::32-big, 4::16-big, 0::16-big, 0::16-big, 0::16-big, "head",
                 0::32-big, 0::32-big>>
             ) == :error
    end

    test "a table record pointing outside the font fails" do
      binary =
        <<0x0001_0000::32-big, 1::16-big, 0::16-big, 0::16-big, 0::16-big, "head", 0::32-big,
          9999::32-big, 54::32-big>>

      assert TTF.parse_basic_tables(binary) == :error
    end
  end

  describe "truncated tables fail cleanly" do
    test "a head table too short for unitsPerEm" do
      assert TTF.parse_basic_tables(font(%{"head" => <<0::size(10)-unit(8)>>})) == :error
    end

    test "a head table long enough for unitsPerEm but not the bounding box" do
      assert TTF.parse_basic_tables(font(%{"head" => binary_part(head(), 0, 22)})) == :error
    end

    test "a head table missing macStyle" do
      assert TTF.parse_basic_tables(font(%{"head" => binary_part(head(), 0, 44)})) == :error
    end

    test "a head table missing indexToLocFormat" do
      # Everything up to offset 50 is present; the last field is not.
      assert TTF.parse_basic_tables(font(%{"head" => binary_part(head(), 0, 50)})) == :error
    end

    test "a maxp table too short for numGlyphs" do
      assert TTF.parse_basic_tables(font(%{"maxp" => <<0x0001_0000::32-big>>})) == :error
    end

    test "an hhea table too short for numberOfHMetrics" do
      assert TTF.parse_basic_tables(font(%{"hhea" => binary_part(hhea(), 0, 20)})) == :error
    end

    test "an hhea table too short for vertical metrics" do
      assert TTF.parse_basic_tables(font(%{"hhea" => <<0::32-big, 1::16-big>>})) == :error
    end

    test "an hmtx table shorter than numberOfHMetrics implies" do
      # hhea claims four metrics, hmtx supplies one.
      binary = font(%{"hhea" => hhea(number_of_h_metrics: 4), "maxp" => maxp(4)})
      assert TTF.parse_basic_tables(binary) == :error
    end

    test "an empty hmtx table" do
      assert TTF.parse_basic_tables(font(%{"hmtx" => <<>>})) == :error
    end
  end

  describe "values outside their legal range fail" do
    test "a unitsPerEm of zero" do
      assert TTF.parse_basic_tables(font(%{"head" => head(units_per_em: 0)})) == :error
    end

    test "a numGlyphs of zero" do
      assert TTF.parse_basic_tables(font(%{"maxp" => maxp(0)})) == :error
    end

    test "a numberOfHMetrics of zero" do
      assert TTF.parse_basic_tables(font(%{"hhea" => hhea(number_of_h_metrics: 0)})) == :error
    end

    test "an indexToLocFormat other than 0 or 1" do
      for value <- [2, -1, 99] do
        assert TTF.parse_basic_tables(font(%{"head" => head(index_to_loc_format: value)})) ==
                 :error,
               "indexToLocFormat=#{value} should be rejected"
      end
    end

    test "numberOfHMetrics larger than numGlyphs" do
      # hmtx cannot describe more glyphs than the font has.
      binary = font(%{"hhea" => hhea(number_of_h_metrics: 5), "maxp" => maxp(2)})
      assert TTF.parse_basic_tables(binary) == :error
    end
  end

  describe "both indexToLocFormat values are accepted" do
    test "short and long loca formats both parse" do
      for value <- [0, 1] do
        assert {:ok, _metrics} =
                 TTF.parse_basic_tables(font(%{"head" => head(index_to_loc_format: value)}))
      end
    end
  end

  describe "arbitrary input degrades rather than crashing" do
    test "random bytes fail cleanly" do
      junk = for i <- 1..400, into: <<>>, do: <<rem(i * 41, 256)>>
      assert TTF.parse_basic_tables(junk) == :error
    end

    test "a truncated valid font fails at every cut point" do
      full = font()

      for cut <- 1..byte_size(full)//7 do
        assert TTF.parse_basic_tables(binary_part(full, 0, cut)) == :error,
               "truncating to #{cut} bytes should fail cleanly"
      end
    end
  end

  # -- CFF descriptor metrics ------------------------------------------------

  describe "CFF descriptor metrics" do
    # A CFF INDEX: count, offSize, count+1 offsets, then the objects.
    defp cff_index([]), do: <<0::16-big>>

    defp cff_index(objects) do
      {offsets, _} =
        Enum.reduce(objects, {[1], 1}, fn object, {acc, cursor} ->
          next = cursor + byte_size(object)
          {acc ++ [next], next}
        end)

      offset_bin = for o <- offsets, into: <<>>, do: <<o::8>>
      <<length(objects)::16-big, 1::8, offset_bin::binary, IO.iodata_to_binary(objects)::binary>>
    end

    # DICT operand, two-byte form (covers 108..1131, which is all we need).
    defp dict_int(value) when value >= 108 and value <= 1131 do
      <<div(value - 108, 256) + 247::8, rem(value - 108, 256)::8>>
    end

    defp dict_int(value) when value >= 32 - 139 and value <= 246 - 139 do
      <<value + 139::8>>
    end

    # A CFF table whose top DICT carries the given entries. `strings` become
    # SIDs 391 upwards, which is where custom strings start.
    defp cff_table(top_dict_entries, opts \\ []) do
      strings = Keyword.get(opts, :strings, [])
      private = Keyword.get(opts, :private)

      {top_dict, trailer} =
        case private do
          nil ->
            {IO.iodata_to_binary(top_dict_entries), <<>>}

          private_dict ->
            # The Private DICT operator (18) takes {size, offset}, where the
            # offset is from the start of the CFF table - so the offset's own
            # encoded length changes the table size, which changes the offset.
            # Iterate to a fixed point rather than guessing.
            build = fn offset ->
              IO.iodata_to_binary(top_dict_entries) <>
                dict_int(byte_size(private_dict)) <> dict_int(offset) <> <<18::8>>
            end

            size_with = fn dict ->
              4 + byte_size(cff_index(["FontName"])) + byte_size(cff_index([dict])) +
                byte_size(cff_index(strings)) + byte_size(cff_index([]))
            end

            offset =
              Enum.reduce(1..5, 200, fn _, guess -> size_with.(build.(guess)) end)

            {build.(offset), private_dict}
        end

      <<1::8, 0::8, 4::8, 1::8>> <>
        cff_index(["FontName"]) <>
        cff_index([top_dict]) <> cff_index(strings) <> cff_index([]) <> trailer
    end

    defp cff_font(top_dict_entries, opts \\ []) do
      font(%{"CFF " => cff_table(top_dict_entries, opts)})
    end

    defp metrics!(binary) do
      {:ok, metrics} = TTF.parse_basic_tables(binary)
      metrics
    end

    test "maps a CFF Weight string to a numeric weight class" do
      # Operator 4 is Weight; SID 391 is the first custom string.
      for {name, expected} <- [
            {"Thin", 100},
            {"Hairline", 100},
            {"ExtraLight", 200},
            {"UltraLight", 200},
            {"Light", 300},
            {"Book", 350},
            {"Normal", 400},
            {"Regular", 400},
            {"Roman", 400},
            {"Medium", 500},
            {"SemiBold", 600},
            {"DemiBold", 600},
            {"Bold", 700},
            {"ExtraBold", 800},
            {"UltraBold", 800},
            {"Black", 900},
            {"Heavy", 900}
          ] do
        binary = cff_font([dict_int(391), <<4::8>>], strings: [name])
        assert metrics!(binary).cff_weight_class == expected, "Weight=#{name}"
      end
    end

    test "normalises spacing, punctuation and case in the weight name" do
      # "Extra-Light", "extra light" and "ExtraLight" are the same weight.
      for name <- ["Extra-Light", "extra light", "EXTRALIGHT", "Extra_Light"] do
        binary = cff_font([dict_int(391), <<4::8>>], strings: [name])
        assert metrics!(binary).cff_weight_class == 200, "Weight=#{name}"
      end
    end

    test "an unrecognised weight name yields no weight class" do
      binary = cff_font([dict_int(391), <<4::8>>], strings: ["Fantastical"])
      assert metrics!(binary).cff_weight_class == nil
    end

    test "a font with no Weight operator yields no weight class" do
      assert metrics!(cff_font([])).cff_weight_class == nil
    end

    test "a Weight SID pointing past the string index yields no weight class" do
      binary = cff_font([dict_int(999), <<4::8>>], strings: ["Bold"])
      assert metrics!(binary).cff_weight_class == nil
    end

    test "reads StemV and StemH from the Private DICT" do
      private = dict_int(120) <> <<11::8>> <> dict_int(80) <> <<10::8>>
      metrics = metrics!(cff_font([], private: private))

      assert metrics.cff_stem_v == 120
      assert metrics.cff_stem_h == 80
    end

    test "reads ForceBold from the Private DICT" do
      bold = metrics!(cff_font([], private: dict_int(140) <> <<14::8>>))
      assert bold.cff_force_bold == true

      not_bold = metrics!(cff_font([], private: <<139::8, 14::8>>))
      assert not_bold.cff_force_bold == false
    end

    test "a Private DICT with no stem entries yields no stem metrics" do
      metrics = metrics!(cff_font([], private: dict_int(140) <> <<14::8>>))
      assert metrics.cff_stem_v == nil
      assert metrics.cff_stem_h == nil
    end

    test "a font with no Private DICT yields no stem metrics or force bold" do
      metrics = metrics!(cff_font([]))
      assert metrics.cff_stem_v == nil
      assert metrics.cff_stem_h == nil
      assert metrics.cff_force_bold == nil
    end

    test "a malformed CFF table yields no descriptor metrics" do
      metrics = metrics!(font(%{"CFF " => <<1::8, 0::8, 4::8, 1::8, 0xFF, 0xFF>>}))
      assert metrics.cff_weight_class == nil
      assert metrics.cff_stem_v == nil
    end

    test "a CFF header shorter than its declared size yields no metrics" do
      metrics = metrics!(font(%{"CFF " => <<1::8, 0::8, 40::8, 1::8>>}))
      assert metrics.cff_weight_class == nil
    end
  end
end
