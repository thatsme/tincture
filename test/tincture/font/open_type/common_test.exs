defmodule Tincture.Font.OpenType.CommonTest do
  @moduledoc """
  Direct tests for the OpenType Layout common table formats.

  These were private inside a 1,783-line module and reachable only by parsing a
  complete font, so the malformed-input paths — which is most of what this code
  is — were never exercised directly. Font tables supply their own offsets and
  counts, and both are untrusted: a table can claim 65,535 coverage glyphs and
  supply four bytes.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.OpenType.Common

  # -- builders for the on-disk structures -----------------------------------

  # Layout table header: major, minor, then three offsets.
  defp layout_header(script_off, feature_off, lookup_off) do
    <<1::16-big, 0::16-big, script_off::16-big, feature_off::16-big, lookup_off::16-big>>
  end

  # A ScriptList or FeatureList: count, then {4-byte tag, offset} records.
  defp tag_records(records) do
    body =
      for {tag, offset} <- records,
          into: <<>>,
          do: <<tag::binary-size(4), offset::16-big>>

    <<length(records)::16-big, body::binary>>
  end

  defp coverage_format_1(glyph_ids) do
    body = for id <- glyph_ids, into: <<>>, do: <<id::16-big>>
    <<1::16-big, length(glyph_ids)::16-big, body::binary>>
  end

  defp coverage_format_2(ranges) do
    body =
      for {first, last, index} <- ranges,
          into: <<>>,
          do: <<first::16-big, last::16-big, index::16-big>>

    <<2::16-big, length(ranges)::16-big, body::binary>>
  end

  # LookupList: count, then offsets relative to the list itself.
  defp lookup_list(lookups) do
    count = length(lookups)
    header_size = 2 + count * 2

    {offsets, bodies, _} =
      Enum.reduce(lookups, {[], [], header_size}, fn lookup, {offs, bods, cursor} ->
        {offs ++ [cursor], bods ++ [lookup], cursor + byte_size(lookup)}
      end)

    offset_bin = for o <- offsets, into: <<>>, do: <<o::16-big>>
    <<count::16-big, offset_bin::binary, IO.iodata_to_binary(bodies)::binary>>
  end

  # A Lookup table: type, flag, subtable count, then subtable offsets.
  defp lookup(type, subtable_offsets) do
    body = for o <- subtable_offsets, into: <<>>, do: <<o::16-big>>
    <<type::16-big, 0::16-big, length(subtable_offsets)::16-big, body::binary>>
  end

  describe "parse_open_type_layout_table/1" do
    test "reads the three list offsets out of the header" do
      table = layout_header(10, 20, 30) <> String.duplicate(<<0>>, 40)
      assert {:ok, _scripts, _features, 30} = Common.parse_open_type_layout_table(table)
    end

    test "parses script and feature tag records at their offsets" do
      scripts = tag_records([{"latn", 0}, {"cyrl", 0}])
      features = tag_records([{"liga", 0}])
      # header is 10 bytes; place scripts then features after it
      table = layout_header(10, 10 + byte_size(scripts), 0) <> scripts <> features

      assert {:ok, script_tags, feature_tags, 0} = Common.parse_open_type_layout_table(table)
      assert "latn" in script_tags
      assert "cyrl" in script_tags
      assert "liga" in feature_tags
    end

    test "rejects a table too short to hold a header" do
      assert Common.parse_open_type_layout_table(<<1::16-big, 0::16-big>>) == :error
      assert Common.parse_open_type_layout_table(<<>>) == :error
    end

    test "rejects a non-binary" do
      assert Common.parse_open_type_layout_table(nil) == :error
      assert Common.parse_open_type_layout_table(%{}) == :error
    end
  end

  describe "parse_open_type_coverage_table/2 format 1" do
    test "reads an explicit glyph list" do
      table = coverage_format_1([3, 7, 11])
      assert Common.parse_open_type_coverage_table(table, 0) == [3, 7, 11]
    end

    test "an empty coverage table is legal" do
      assert Common.parse_open_type_coverage_table(coverage_format_1([]), 0) == []
    end

    test "reads at a non-zero offset" do
      table = <<0xFF, 0xFF>> <> coverage_format_1([5])
      assert Common.parse_open_type_coverage_table(table, 2) == [5]
    end

    test "returns [] when the declared glyph count exceeds the data" do
      # Claims 100 glyphs, supplies two bytes.
      assert Common.parse_open_type_coverage_table(<<1::16-big, 100::16-big, 0, 1>>, 0) == []
    end
  end

  describe "parse_open_type_coverage_table/2 format 2" do
    test "expands ranges into glyph ids" do
      table = coverage_format_2([{5, 8, 0}])
      assert Common.parse_open_type_coverage_table(table, 0) == [5, 6, 7, 8]
    end

    test "expands multiple ranges in order" do
      table = coverage_format_2([{1, 2, 0}, {10, 11, 2}])
      assert Common.parse_open_type_coverage_table(table, 0) == [1, 2, 10, 11]
    end

    test "a single-glyph range is legal" do
      assert Common.parse_open_type_coverage_table(coverage_format_2([{9, 9, 0}]), 0) == [9]
    end

    test "stops at a range whose end precedes its start" do
      # Malformed: 8..5 would otherwise expand descending or crash.
      table = coverage_format_2([{1, 2, 0}, {8, 5, 2}])
      assert Common.parse_open_type_coverage_table(table, 0) == [1, 2]
    end

    test "returns [] when the declared range count exceeds the data" do
      assert Common.parse_open_type_coverage_table(<<2::16-big, 50::16-big, 0, 1>>, 0) == []
    end
  end

  describe "parse_open_type_coverage_table/2 rejections" do
    test "returns [] for an unknown coverage format" do
      assert Common.parse_open_type_coverage_table(<<7::16-big, 1::16-big, 0, 3>>, 0) == []
      assert Common.parse_open_type_coverage_table(<<0::16-big, 1::16-big, 0, 3>>, 0) == []
    end

    test "returns [] for an offset past the end" do
      assert Common.parse_open_type_coverage_table(coverage_format_1([1]), 999) == []
    end

    test "returns [] for a negative offset or non-binary table" do
      assert Common.parse_open_type_coverage_table(coverage_format_1([1]), -1) == []
      assert Common.parse_open_type_coverage_table(nil, 0) == []
    end
  end

  describe "parse_open_type_lookup_entries/2" do
    test "an offset of zero means the table has no lookup list" do
      assert Common.parse_open_type_lookup_entries(<<0, 0, 0, 0>>, 0) == []
    end

    test "reads lookup type and subtable offsets" do
      # The list is placed at a non-zero offset: an offset of 0 is the sentinel
      # for "this table has no lookup list" and short-circuits.
      table = <<0xFF, 0xFF>> <> lookup_list([lookup(4, [20])])

      assert [%{type: 4, subtable_offsets: [offset]}] =
               Common.parse_open_type_lookup_entries(table, 2)

      # Subtable offsets come back absolute, not relative to the lookup.
      assert is_integer(offset) and offset > 20
    end

    test "reads several lookups in order" do
      table = <<0xFF, 0xFF>> <> lookup_list([lookup(1, [10]), lookup(4, [12])])
      entries = Common.parse_open_type_lookup_entries(table, 2)
      assert Enum.map(entries, & &1.type) == [1, 4]
    end

    test "drops subtable offsets of zero, which mean absent" do
      table = <<0xFF, 0xFF>> <> lookup_list([lookup(4, [0, 30])])
      assert [%{subtable_offsets: offsets}] = Common.parse_open_type_lookup_entries(table, 2)
      assert length(offsets) == 1
    end

    test "returns [] when the declared lookup count exceeds the data" do
      assert Common.parse_open_type_lookup_entries(<<0xFF, 0xFF, 99::16-big, 0, 1>>, 2) == []
    end

    test "skips a lookup whose own table runs past the end" do
      # One lookup, pointing far beyond the table.
      table = <<0xFF, 0xFF, 1::16-big, 9000::16-big>>
      assert Common.parse_open_type_lookup_entries(table, 2) == []
    end

    test "returns [] for a negative offset or non-binary table" do
      assert Common.parse_open_type_lookup_entries(<<0, 0>>, -1) == []
      assert Common.parse_open_type_lookup_entries(nil, 0) == []
    end
  end

  describe "filter_open_type_lookup_entries_by_features/4" do
    test "returns the entries untouched when the table is not a binary" do
      entries = [%{type: 4, subtable_offsets: [1]}]

      assert Common.filter_open_type_lookup_entries_by_features(nil, entries, ["liga"], :all) ==
               entries
    end

    test "returns [] when no feature in the table matches the requested tags" do
      table = layout_header(10, 10, 0) <> tag_records([])
      assert Common.filter_open_type_lookup_entries_by_features(table, [], ["liga"], :all) == []
    end

    test "ignores tags that are not four bytes" do
      table = layout_header(10, 10, 0) <> tag_records([])

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [],
               ["li", "toolong", 42],
               :all
             ) == []
    end
  end

  describe "invert_cmap_by_code/1" do
    test "inverts codepoint -> glyph into glyph -> codepoint" do
      assert Common.invert_cmap_by_code(%{65 => 1, 66 => 2}) == %{1 => 65, 2 => 66}
    end

    test "when several codepoints share a glyph, the lowest wins" do
      # Deterministic choice matters: the inverse feeds ligature mapping, and a
      # map's iteration order must not decide which codepoint is reported.
      assert Common.invert_cmap_by_code(%{200 => 1, 65 => 1, 300 => 1}) == %{1 => 65}
    end

    test "an empty cmap inverts to an empty map" do
      assert Common.invert_cmap_by_code(%{}) == %{}
    end
  end

  describe "valid_unicode_codepoint?/1" do
    test "accepts the full Unicode range" do
      assert Common.valid_unicode_codepoint?(0)
      assert Common.valid_unicode_codepoint?(0x10FFFF)
      assert Common.valid_unicode_codepoint?(?A)
    end

    test "rejects values outside it" do
      refute Common.valid_unicode_codepoint?(-1)
      refute Common.valid_unicode_codepoint?(0x110000)
    end

    test "rejects non-integers" do
      refute Common.valid_unicode_codepoint?(nil)
      refute Common.valid_unicode_codepoint?("A")
      refute Common.valid_unicode_codepoint?(1.0)
    end
  end

  describe "parse_layout_table_metadata/3" do
    test "returns empty lists when the tag is absent" do
      assert Common.parse_layout_table_metadata(<<0, 0>>, %{}, "GSUB") == {[], []}
    end

    test "returns empty lists when the record points outside the font" do
      assert Common.parse_layout_table_metadata(<<0, 0>>, %{"GSUB" => {500, 10}}, "GSUB") ==
               {[], []}
    end

    test "reads scripts and features from a table the record points at" do
      scripts = tag_records([{"latn", 0}])
      features = tag_records([{"liga", 0}])
      table = layout_header(10, 10 + byte_size(scripts), 0) <> scripts <> features
      font = <<0xAA, 0xBB>> <> table

      assert {script_tags, feature_tags} =
               Common.parse_layout_table_metadata(
                 font,
                 %{"GSUB" => {2, byte_size(table)}},
                 "GSUB"
               )

      assert "latn" in script_tags
      assert "liga" in feature_tags
    end
  end

  describe "script and feature resolution" do
    # A complete ScriptList -> LangSys -> FeatureList -> LookupList chain, built
    # so the feature-linked lookup resolution can be driven from the public API.
    defp feature_chain(opts) do
      script_tag = Keyword.get(opts, :script_tag, "latn")
      feature_tag = Keyword.get(opts, :feature_tag, "liga")
      required_index = Keyword.get(opts, :required_feature_index, 0xFFFF)
      feature_indices = Keyword.get(opts, :feature_indices, [0])
      named_lang_sys = Keyword.get(opts, :named_lang_sys, false)

      script_list_off = 10
      script_off = 20
      lang_sys_off = 30
      feature_list_off = 50
      feature_off = 60
      lookup_list_off = 70

      fi_bin = for i <- feature_indices, into: <<>>, do: <<i::16-big>>

      lang_sys =
        <<0::16-big, required_index::16-big, length(feature_indices)::16-big, fi_bin::binary>>

      script =
        if named_lang_sys do
          # No default LangSys; one named record pointing at the same LangSys.
          <<0::16-big, 1::16-big, "ENG "::binary, lang_sys_off - script_off::16-big>>
        else
          <<lang_sys_off - script_off::16-big, 0::16-big>>
        end

      parts = [
        {script_list_off,
         <<1::16-big, script_tag::binary-size(4), script_off - script_list_off::16-big>>},
        {script_off, script},
        {lang_sys_off, lang_sys},
        {feature_list_off,
         <<1::16-big, feature_tag::binary-size(4), feature_off - feature_list_off::16-big>>},
        {feature_off, <<0::16-big, 1::16-big, 0::16-big>>},
        {lookup_list_off, <<1::16-big, 4::16-big>>}
      ]

      header =
        <<1::16-big, 0::16-big, script_list_off::16-big, feature_list_off::16-big,
          lookup_list_off::16-big>>

      Enum.reduce(parts, header, fn {offset, bin}, acc ->
        acc <> String.duplicate(<<0>>, max(offset - byte_size(acc), 0)) <> bin
      end)
    end

    @entry %{type: 4, subtable_offsets: [1]}

    test "resolves a feature to its lookup under the default language system" do
      table = feature_chain([])

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [@entry],
               ["liga"],
               :all
             ) == [@entry]
    end

    test "resolves a feature reached through a named language system" do
      # No default LangSys, only a named one - the parser must fall through.
      table = feature_chain(named_lang_sys: true)

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [@entry],
               ["liga"],
               :all
             ) == [@entry]
    end

    test "includes a required feature index alongside the listed ones" do
      # requiredFeatureIndex is a separate field from the feature index list;
      # 0xFFFF means none, anything else must be treated as present.
      table = feature_chain(required_feature_index: 0, feature_indices: [])

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [@entry],
               ["liga"],
               :all
             ) == [@entry]
    end

    test "rlig and ccmp resolve under the preferred-script path" do
      for tag <- ["rlig", "ccmp"] do
        table = feature_chain(feature_tag: tag)

        assert Common.filter_open_type_lookup_entries_by_features(
                 table,
                 [@entry],
                 [tag],
                 :preferred
               ) == [@entry],
               "#{tag} should resolve for the latn script"
      end
    end

    test ":preferred falls back to every script when the feature has no preference" do
      # "zzzz" has no entry in the preferred-script table, so there is nothing to
      # narrow to. The fallback is "use them all" rather than "use none" - a font
      # declaring an unusual feature should still have it found.
      table = feature_chain(feature_tag: "zzzz")

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [@entry],
               ["zzzz"],
               :preferred
             ) == [@entry]
    end

    test ":preferred falls back to every script when no preferred one is present" do
      # liga prefers latn and DFLT; this font declares only cyrl. Narrowing would
      # find nothing, so the parser uses what the font does have.
      table = feature_chain(script_tag: "cyrl")

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [@entry],
               ["liga"],
               :preferred
             ) == [@entry]
    end

    test "the same script is still found when scope is :all" do
      table = feature_chain(script_tag: "cyrl")

      assert Common.filter_open_type_lookup_entries_by_features(
               table,
               [@entry],
               ["liga"],
               :all
             ) == [@entry]
    end

    test "a lookup index with no matching entry is dropped" do
      table = feature_chain([])
      assert Common.filter_open_type_lookup_entries_by_features(table, [], ["liga"], :all) == []
    end
  end

  describe "absent lists" do
    test "a script or feature list offset of zero yields no tags" do
      table = layout_header(0, 0, 0) <> String.duplicate(<<0>>, 20)
      assert {:ok, [], [], 0} = Common.parse_open_type_layout_table(table)
    end

    test "a list offset past the end yields no tags" do
      table = layout_header(900, 900, 0) <> String.duplicate(<<0>>, 20)
      assert {:ok, [], [], 0} = Common.parse_open_type_layout_table(table)
    end
  end
end
