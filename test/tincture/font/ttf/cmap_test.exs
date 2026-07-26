defmodule Tincture.Font.TTF.CmapTest do
  @moduledoc """
  Direct tests for the `cmap` table.

  `cmap` maps Unicode codepoints to glyph indices — the table that decides
  whether a font can render a character at all. It is really several
  incompatible on-disk layouts sharing a table tag:

    * format 0 — a flat 256-byte array, the original Macintosh mapping
    * format 4 — segmented, the common case for the Basic Multilingual Plane
    * format 6 — a trimmed contiguous range
    * format 12 — segmented 32-bit, required for anything outside the BMP
    * format 13 — many-to-one, used by last-resort fonts
    * format 14 — Unicode variation sequences

  A font carries several subtables under different platform and encoding IDs
  and the reader has to pick the best one, so these tests build tables with
  competing records rather than one subtable at a time.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.TTF.Cmap

  # cmap header: version, numTables, then {platformID, encodingID, offset}.
  defp cmap(records) do
    header_size = 4 + length(records) * 8

    {record_bin, bodies, _} =
      Enum.reduce(records, {<<>>, <<>>, header_size}, fn {plat, enc, sub}, {recs, bods, cursor} ->
        {recs <> <<plat::16-big, enc::16-big, cursor::32-big>>, bods <> sub,
         cursor + byte_size(sub)}
      end)

    <<0::16-big, length(records)::16-big, record_bin::binary, bodies::binary>>
  end

  # format 0: a 256-entry byte array indexed by codepoint.
  defp format_0(mapping) do
    glyphs =
      Enum.reduce(mapping, :binary.copy(<<0>>, 256), fn {code, glyph}, acc ->
        <<before::binary-size(code), _::8, rest::binary>> = acc
        <<before::binary, glyph::8, rest::binary>>
      end)

    <<0::16-big, 262::16-big, 0::16-big, glyphs::binary>>
  end

  # format 4: segments of {start, end, id_delta}. A terminating 0xFFFF segment
  # is required by the specification.
  defp format_4(segments) do
    segments = segments ++ [{0xFFFF, 0xFFFF, 1}]
    seg_count = length(segments)

    ends = for {_s, e, _d} <- segments, into: <<>>, do: <<e::16-big>>
    starts = for {s, _e, _d} <- segments, into: <<>>, do: <<s::16-big>>
    deltas = for {_s, _e, d} <- segments, into: <<>>, do: <<d::16-signed-big>>
    range_offsets = :binary.copy(<<0, 0>>, seg_count)

    body =
      <<seg_count * 2::16-big, 0::16-big, 0::16-big, 0::16-big, ends::binary, 0::16-big,
        starts::binary, deltas::binary, range_offsets::binary>>

    <<4::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
  end

  # format 6: a contiguous run starting at first_code.
  defp format_6(first_code, glyph_ids) do
    body = for g <- glyph_ids, into: <<>>, do: <<g::16-big>>

    <<6::16-big, 10 + byte_size(body)::16-big, 0::16-big, first_code::16-big,
      length(glyph_ids)::16-big, body::binary>>
  end

  # format 12: groups of {start_char, end_char, start_glyph}.
  defp format_12(groups) do
    body =
      for {sc, ec, sg} <- groups,
          into: <<>>,
          do: <<sc::32-big, ec::32-big, sg::32-big>>

    length_field = 16 + byte_size(body)

    <<12::16-big, 0::16-big, length_field::32-big, 0::32-big, length(groups)::32-big,
      body::binary>>
  end

  # format 13: same shape as 12, but every codepoint in the group maps to the
  # same glyph rather than a run.
  defp format_13(groups) do
    body =
      for {sc, ec, g} <- groups,
          into: <<>>,
          do: <<sc::32-big, ec::32-big, g::32-big>>

    length_field = 16 + byte_size(body)

    <<13::16-big, 0::16-big, length_field::32-big, 0::32-big, length(groups)::32-big,
      body::binary>>
  end

  defp font_with(cmap_table), do: {<<0xAA, 0xBB>> <> cmap_table, byte_size(cmap_table)}

  defp by_code(cmap_table) do
    {data, length} = font_with(cmap_table)
    {:ok, map} = Cmap.parse_cmap_by_code(data, %{"cmap" => {2, length}})
    map
  end

  describe "format 0 (byte encoding)" do
    test "maps codepoints through a 256-entry array" do
      table = cmap([{1, 0, format_0(%{65 => 1, 66 => 2})}])
      assert by_code(table)[65] == 1
      assert by_code(table)[66] == 2
    end

    test "every one of the 256 slots is mapped, including unmapped ones" do
      # Format 0 is a dense array, so unassigned codepoints come back mapped to
      # glyph 0 (.notdef) rather than being absent. Callers distinguish "has no
      # glyph" by the value, not by key presence.
      map = by_code(cmap([{1, 0, format_0(%{65 => 1})}]))

      assert map_size(map) == 256
      assert map[65] == 1
      assert map[66] == 0
    end

    test "a truncated format 0 subtable yields no mapping" do
      short = <<0::16-big, 262::16-big, 0::16-big, 1, 2, 3>>
      assert by_code(cmap([{1, 0, short}])) == %{}
    end
  end

  describe "format 4 (segmented BMP)" do
    test "maps a segment through its id delta" do
      # Codepoints 65..67 map to glyphs 66..68 via a delta of 1.
      table = cmap([{3, 1, format_4([{65, 67, 1}])}])
      map = by_code(table)

      assert map[65] == 66
      assert map[66] == 67
      assert map[67] == 68
    end

    test "maps several segments independently" do
      table = cmap([{3, 1, format_4([{65, 65, 1}, {200, 201, 100}])}])
      map = by_code(table)

      assert map[65] == 66
      assert map[200] == 300
      assert map[201] == 301
    end

    test "the id delta wraps modulo 65536" do
      # Specified behaviour, not an accident: glyph ids are 16-bit, so a delta
      # taking a codepoint below zero wraps to the top of the range.
      # 65 + (-66) = -1, which is glyph 65535.
      table = cmap([{3, 1, format_4([{65, 65, -66}])}])
      assert by_code(table)[65] == 65_535
    end

    test "codepoints outside every segment are absent" do
      table = cmap([{3, 1, format_4([{65, 67, 1}])}])
      refute Map.has_key?(by_code(table), 100)
    end

    test "a segment count of zero yields no mapping" do
      body = <<0::16-big, 0::16-big, 0::16-big, 0::16-big>>
      subtable = <<4::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
      assert by_code(cmap([{3, 1, subtable}])) == %{}
    end

    test "an odd segCountX2 yields no mapping" do
      body = <<3::16-big, 0::16-big, 0::16-big, 0::16-big>>
      subtable = <<4::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
      assert by_code(cmap([{3, 1, subtable}])) == %{}
    end

    test "a truncated segment array yields no mapping" do
      body = <<8::16-big, 0::16-big, 0::16-big, 0::16-big, 1, 2>>
      subtable = <<4::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
      assert by_code(cmap([{3, 1, subtable}])) == %{}
    end
  end

  describe "format 6 (trimmed range)" do
    test "maps a contiguous run from first_code" do
      table = cmap([{3, 1, format_6(65, [10, 11, 12])}])
      map = by_code(table)

      assert map[65] == 10
      assert map[66] == 11
      assert map[67] == 12
    end

    test "codepoints outside the run are absent" do
      table = cmap([{3, 1, format_6(65, [10])}])
      refute Map.has_key?(by_code(table), 64)
      refute Map.has_key?(by_code(table), 66)
    end

    test "an entry count larger than the data yields no mapping" do
      subtable = <<6::16-big, 12::16-big, 0::16-big, 65::16-big, 50::16-big, 0, 1>>
      assert by_code(cmap([{3, 1, subtable}])) == %{}
    end

    test "an empty run yields no mapping" do
      assert by_code(cmap([{3, 1, format_6(65, [])}])) == %{}
    end
  end

  describe "format 12 (segmented 32-bit)" do
    test "maps a group as a run of consecutive glyphs" do
      table = cmap([{3, 10, format_12([{0x10000, 0x10002, 5}])}])
      map = by_code(table)

      assert map[0x10000] == 5
      assert map[0x10001] == 6
      assert map[0x10002] == 7
    end

    test "reaches codepoints outside the Basic Multilingual Plane" do
      # This is the whole point of format 12: format 4 cannot express these.
      table = cmap([{3, 10, format_12([{0x1F600, 0x1F600, 42}])}])
      assert by_code(table)[0x1F600] == 42
    end

    test "maps several groups independently" do
      table = cmap([{3, 10, format_12([{65, 65, 1}, {0x20000, 0x20001, 900}])}])
      map = by_code(table)

      assert map[65] == 1
      assert map[0x20000] == 900
      assert map[0x20001] == 901
    end

    test "a group whose end precedes its start rejects the whole subtable" do
      # Not just that group: a malformed group means the table cannot be
      # trusted, so nothing from it is used. The valid group alongside it is
      # discarded too.
      table = cmap([{3, 10, format_12([{100, 50, 5}, {65, 65, 1}])}])
      assert by_code(table) == %{}
    end

    test "a group count larger than the data yields no mapping" do
      subtable = <<12::16-big, 0::16-big, 40::32-big, 0::32-big, 99::32-big, 0, 1, 2, 3>>
      assert by_code(cmap([{3, 10, subtable}])) == %{}
    end

    test "a declared length shorter than the header is rejected" do
      subtable = <<12::16-big, 0::16-big, 8::32-big, 0::32-big>>
      assert by_code(cmap([{3, 10, subtable}])) == %{}
    end
  end

  describe "format 13 (many-to-one)" do
    test "maps every codepoint in a group to the same glyph" do
      # A last-resort font maps whole ranges to one fallback glyph.
      table = cmap([{3, 10, format_13([{65, 68, 7}])}])
      map = by_code(table)

      assert map[65] == 7
      assert map[66] == 7
      assert map[67] == 7
      assert map[68] == 7
    end

    test "differs from format 12, which would produce a run" do
      thirteen = by_code(cmap([{3, 10, format_13([{65, 67, 7}])}]))
      twelve = by_code(cmap([{3, 10, format_12([{65, 67, 7}])}]))

      assert thirteen[66] == 7
      assert twelve[66] == 8
    end
  end

  describe "choosing between competing subtables" do
    test "prefers the Windows UCS-4 record over Windows BMP" do
      # Platform 3 encoding 10 covers more than encoding 1, so it wins.
      table =
        cmap([
          {3, 1, format_4([{65, 65, 1}])},
          {3, 10, format_12([{65, 65, 99}])}
        ])

      assert by_code(table)[65] == 99
    end

    test "prefers Windows BMP over a symbol or Macintosh record" do
      table =
        cmap([
          {1, 0, format_0(%{65 => 5})},
          {3, 0, format_4([{65, 65, 10}])},
          {3, 1, format_4([{65, 65, 1}])}
        ])

      assert by_code(table)[65] == 66
    end

    test "falls back to a Macintosh record when nothing better exists" do
      assert by_code(cmap([{1, 0, format_0(%{65 => 5})}]))[65] == 5
    end

    test "skips a preferred record that fails to parse" do
      # The platform 3/10 record is malformed, so the readable 3/1 one is used.
      table =
        cmap([
          {3, 10, <<12::16-big, 0::16-big, 8::32-big, 0::32-big>>},
          {3, 1, format_4([{65, 65, 1}])}
        ])

      assert by_code(table)[65] == 66
    end
  end

  describe "malformed tables degrade rather than crashing" do
    test "a font with no cmap table yields an empty map" do
      assert Cmap.parse_cmap_by_code(<<0, 0>>, %{}) == {:ok, %{}}
    end

    test "a cmap record pointing outside the font yields an empty map" do
      assert Cmap.parse_cmap_by_code(<<0, 0>>, %{"cmap" => {900, 40}}) == {:ok, %{}}
    end

    test "a table with no encoding records yields an empty map" do
      assert by_code(cmap([])) == %{}
    end

    test "a record count larger than the table yields an empty map" do
      assert by_code(<<0::16-big, 99::16-big, 1, 2, 3>>) == %{}
    end

    test "an encoding record pointing past the table yields an empty map" do
      table = <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 9999::32-big>>
      assert by_code(table) == %{}
    end

    test "an unknown subtable format yields an empty map" do
      assert by_code(cmap([{3, 1, <<99::16-big, 8::16-big, 0::16-big, 0, 0>>}])) == %{}
    end

    test "random bytes yield an empty map" do
      junk = for i <- 1..200, into: <<>>, do: <<rem(i * 31, 256)>>
      assert by_code(junk) == %{}
    end
  end

  describe "variation selector metadata (format 14)" do
    test "a font with no cmap yields empty variation metadata" do
      assert {:ok, metadata} = Cmap.parse_cmap_variation_metadata(<<0, 0>>, %{})
      assert metadata.cmap_var_selectors == []
      assert metadata.cmap_non_default_uvs == %{}
    end

    test "a cmap with no format 14 subtable yields empty metadata" do
      table = cmap([{3, 1, format_4([{65, 65, 1}])}])
      {data, length} = font_with(table)

      assert {:ok, metadata} =
               Cmap.parse_cmap_variation_metadata(data, %{"cmap" => {2, length}})

      assert metadata.cmap_var_selectors == []
    end

    test "a cmap record pointing outside the font yields empty metadata" do
      assert {:ok, metadata} =
               Cmap.parse_cmap_variation_metadata(<<0, 0>>, %{"cmap" => {900, 40}})

      assert metadata.cmap_var_selectors == []
    end
  end

  describe "format 2 (high-byte mapping)" do
    # The legacy CJK format. subHeaderKeys maps a high byte to a subHeader;
    # subHeader 0 handles single-byte codes. idRangeOffset is measured from the
    # position of the idRangeOffset field itself, which sits at
    # 6 + 512 + index * 8 + 6 - so the offset depends on where it is stored.
    defp format_2(first_code, glyph_ids, opts \\ []) do
      keys = Keyword.get(opts, :keys, :binary.copy(<<0::16-big>>, 256))
      id_delta = Keyword.get(opts, :id_delta, 0)

      glyphs = for g <- glyph_ids, into: <<>>, do: <<g::16-big>>
      # subHeader[0] spans 518..526; the glyph array starts immediately after,
      # so the offset from the idRangeOffset field at 524 is 2.
      subheader =
        <<first_code::16-big, length(glyph_ids)::16-big, id_delta::16-signed-big, 2::16-big>>

      body = keys <> subheader <> glyphs
      <<2::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
    end

    test "maps single-byte codes through subheader zero" do
      map = by_code(cmap([{1, 0, format_2(65, [1, 2, 3, 4])}]))

      assert map[65] == 1
      assert map[66] == 2
      assert map[67] == 3
      assert map[68] == 4
    end

    test "applies the subheader's id delta" do
      map = by_code(cmap([{1, 0, format_2(65, [1, 2], id_delta: 100)}]))

      assert map[65] == 101
      assert map[66] == 102
    end

    test "a glyph id of zero stays zero rather than taking the delta" do
      # .notdef must not be shifted into a real glyph by the delta.
      map = by_code(cmap([{1, 0, format_2(65, [0, 2], id_delta: 100)}]))
      assert map[65] == 0
    end

    test "codes outside the subheader's range are absent" do
      map = by_code(cmap([{1, 0, format_2(65, [1])}]))
      refute Map.has_key?(map, 64)
      refute Map.has_key?(map, 70)
    end

    test "a subHeaderKeys entry that is not a multiple of eight is rejected" do
      # Keys index into an array of 8-byte records, so a key of 3 is malformed.
      keys = <<3::16-big>> <> :binary.copy(<<0::16-big>>, 255)
      assert by_code(cmap([{1, 0, format_2(65, [1], keys: keys)}])) == %{}
    end

    test "a subheader array shorter than the keys imply is rejected" do
      keys = <<8::16-big>> <> :binary.copy(<<0::16-big>>, 255)
      body = keys <> <<65::16-big, 1::16-big, 0::16-signed-big, 2::16-big>>
      subtable = <<2::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
      assert by_code(cmap([{1, 0, subtable}])) == %{}
    end

    test "a truncated format 2 subtable is rejected" do
      assert by_code(cmap([{1, 0, <<2::16-big, 10::16-big, 0::16-big, 1, 2, 3>>}])) == %{}
    end
  end
end
