defmodule Tincture.Font.OpenType.GSUBTest do
  @moduledoc """
  Direct tests for the `GSUB` parser.

  Reaching a ligature means walking five levels of indirection — script list,
  language system, feature list, lookup list, subtable — so these tests build a
  complete synthetic `GSUB` table rather than mocking any of it. That is the
  point of the extraction: before it, the only way to exercise this code was to
  hand it a real font.

  Layout of the table built below (offsets are from the start of `GSUB`):

      0   header          major, minor, script/feature/lookup list offsets
      10  ScriptList      one "latn" record
      18  Script          default LangSys offset, 0 named LangSys
      22  LangSys         lookupOrder, requiredFeature=0xFFFF, [feature 0]
      30  FeatureList     one "liga" record
      38  Feature         featureParams, [lookup 0]
      44  LookupList      one lookup
      48  Lookup          type 4 (ligature), one subtable
      56  LigatureSubst   format 1, coverage offset, one LigatureSet
      64  LigatureSet     one Ligature
      68  Ligature        glyph, componentCount, components
      *   Coverage        format 1, [glyph 1] (placed after the Ligature)
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.OpenType.GSUB

  # "f" -> glyph 1, "i" -> glyph 2, the ligature "fi" -> glyph 3
  @cmap %{?f => 1, ?i => 2, ?ﬁ => 3}

  # Builds a GSUB table whose single "liga" feature maps glyphs
  # [first_glyph | components] to ligature_glyph.
  defp gsub_table(opts \\ []) do
    feature_tag = Keyword.get(opts, :feature_tag, "liga")
    lookup_type = Keyword.get(opts, :lookup_type, 4)
    first_glyph = Keyword.get(opts, :first_glyph, 1)
    components = Keyword.get(opts, :components, [2])
    ligature_glyph = Keyword.get(opts, :ligature_glyph, 3)

    script_list_off = 10
    script_off = 18
    lang_sys_off = 22
    feature_list_off = 30
    feature_off = 38
    lookup_list_off = 44
    lookup_off = 48
    subtable_off = 56
    ligature_set_off = 64
    ligature_off = 68
    # Ligature is 4 bytes of header plus one u16 per component; coverage has to
    # start clear of it or the two structures overlap.
    coverage_off = ligature_off + 4 + length(components) * 2

    header =
      <<1::16-big, 0::16-big, script_list_off::16-big, feature_list_off::16-big,
        lookup_list_off::16-big>>

    # ScriptList: count, {tag, offset-from-list}
    script_list = <<1::16-big, "latn"::binary, script_off - script_list_off::16-big>>
    # Script: defaultLangSys offset (from script table), langSysCount
    script = <<lang_sys_off - script_off::16-big, 0::16-big>>
    # LangSys: lookupOrder, requiredFeatureIndex (none), featureIndexCount, [0]
    lang_sys = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    # FeatureList: count, {tag, offset-from-list}
    feature_list =
      <<1::16-big, feature_tag::binary-size(4), feature_off - feature_list_off::16-big>>

    # Feature: featureParams, lookupIndexCount, [0]
    feature = <<0::16-big, 1::16-big, 0::16-big>>
    # LookupList: count, [offset-from-list]
    lookup_list = <<1::16-big, lookup_off - lookup_list_off::16-big>>
    # Lookup: type, flag, subtableCount, [offset-from-lookup]
    lookup = <<lookup_type::16-big, 0::16-big, 1::16-big, subtable_off - lookup_off::16-big>>

    # LigatureSubst format 1: format, coverageOffset, ligatureSetCount, [offsets]
    subtable =
      <<1::16-big, coverage_off - subtable_off::16-big, 1::16-big,
        ligature_set_off - subtable_off::16-big>>

    # LigatureSet: count, [offset-from-set]
    ligature_set = <<1::16-big, ligature_off - ligature_set_off::16-big>>

    # Ligature: ligatureGlyph, componentCount, componentGlyphIDs[count-1]
    component_bin = for g <- components, into: <<>>, do: <<g::16-big>>

    ligature =
      <<ligature_glyph::16-big, length(components) + 1::16-big, component_bin::binary>>

    coverage = <<1::16-big, 1::16-big, first_glyph::16-big>>

    parts = [
      {script_list_off, script_list},
      {script_off, script},
      {lang_sys_off, lang_sys},
      {feature_list_off, feature_list},
      {feature_off, feature},
      {lookup_list_off, lookup_list},
      {lookup_off, lookup},
      {subtable_off, subtable},
      {ligature_set_off, ligature_set},
      {ligature_off, ligature},
      {coverage_off, coverage}
    ]

    Enum.reduce(parts, header, fn {offset, bin}, acc ->
      padded = acc <> String.duplicate(<<0>>, max(offset - byte_size(acc), 0))
      padded <> bin
    end)
  end

  # A GSUB table whose single "liga" feature carries a type-1 (single
  # substitution) lookup. `subtable` is the caller-built subtable binary.
  defp single_subst_table(subtable, covered_glyphs) do
    script_list_off = 10
    script_off = 18
    lang_sys_off = 22
    feature_list_off = 30
    feature_off = 38
    lookup_list_off = 44
    lookup_off = 48
    subtable_off = 56
    coverage_off = subtable_off + byte_size(subtable)

    header =
      <<1::16-big, 0::16-big, script_list_off::16-big, feature_list_off::16-big,
        lookup_list_off::16-big>>

    parts = [
      {script_list_off, <<1::16-big, "latn"::binary, script_off - script_list_off::16-big>>},
      {script_off, <<lang_sys_off - script_off::16-big, 0::16-big>>},
      {lang_sys_off, <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>},
      {feature_list_off, <<1::16-big, "liga"::binary, feature_off - feature_list_off::16-big>>},
      {feature_off, <<0::16-big, 1::16-big, 0::16-big>>},
      {lookup_list_off, <<1::16-big, lookup_off - lookup_list_off::16-big>>},
      {lookup_off, <<1::16-big, 0::16-big, 1::16-big, subtable_off - lookup_off::16-big>>},
      {subtable_off, subtable},
      {coverage_off,
       <<1::16-big, length(covered_glyphs)::16-big,
         for(g <- covered_glyphs, into: <<>>, do: <<g::16-big>>)::binary>>}
    ]

    Enum.reduce(parts, header, fn {offset, bin}, acc ->
      acc <> String.duplicate(<<0>>, max(offset - byte_size(acc), 0)) <> bin
    end)
  end

  # SingleSubst format 1: every covered glyph is shifted by a constant delta.
  defp single_subst_format_1(delta, covered_glyphs) do
    subtable_size = 6
    single_subst_table(<<1::16-big, subtable_size::16-big, delta::16-signed-big>>, covered_glyphs)
  end

  # SingleSubst format 2: an explicit substitute per covered glyph.
  defp single_subst_format_2(substitutes, covered_glyphs) do
    body = for g <- substitutes, into: <<>>, do: <<g::16-big>>
    subtable_size = 6 + byte_size(body)

    single_subst_table(
      <<2::16-big, subtable_size::16-big, length(substitutes)::16-big, body::binary>>,
      covered_glyphs
    )
  end

  defp records(table), do: %{"GSUB" => {0, byte_size(table)}}

  describe "parse_gsub_ligatures/3" do
    test "resolves a ligature to its source and replacement text" do
      table = gsub_table()
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{"fi" => "ﬁ"}
    end

    test "returns an empty map when the font has no GSUB table" do
      assert GSUB.parse_gsub_ligatures(<<0, 0>>, %{}, @cmap) == %{}
    end

    test "returns an empty map when the GSUB record points outside the font" do
      assert GSUB.parse_gsub_ligatures(<<0, 0>>, %{"GSUB" => {900, 20}}, @cmap) == %{}
    end

    test "returns an empty map when the table is too short to hold a header" do
      short = <<1::16-big, 0::16-big>>
      assert GSUB.parse_gsub_ligatures(short, records(short), @cmap) == %{}
    end

    test "ignores a feature that is not one it asked for" do
      # "salt" is a stylistic alternate, not a ligature feature.
      table = gsub_table(feature_tag: "salt")
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end

    test "ignores a lookup whose type is not ligature substitution" do
      table = gsub_table(lookup_type: 2)
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end

    test "skips a ligature whose glyphs are not in the cmap" do
      # Glyph 3 has no codepoint, so the replacement cannot be expressed.
      table = gsub_table()
      assert GSUB.parse_gsub_ligatures(table, records(table), %{?f => 1, ?i => 2}) == %{}
    end

    test "skips a ligature whose source glyphs are not in the cmap" do
      table = gsub_table()
      assert GSUB.parse_gsub_ligatures(table, records(table), %{?ﬁ => 3}) == %{}
    end

    test "handles a three-glyph ligature" do
      # Coverage glyph 1 ("f") plus components [1, 2] -> "f" "f" "i".
      table = gsub_table(components: [1, 2])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{"ffi" => "ﬁ"}
    end

    test "rejects a ligature declaring fewer than two components" do
      # componentCount of 1 means no substitution to make.
      table = gsub_table(components: [])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end
  end

  describe "parse_gsub_ligatures_all_scripts/3" do
    test "finds the same ligature without restricting to a preferred script" do
      table = gsub_table()
      assert GSUB.parse_gsub_ligatures_all_scripts(table, records(table), @cmap) == %{"fi" => "ﬁ"}
    end

    test "returns an empty map for a font with no GSUB" do
      assert GSUB.parse_gsub_ligatures_all_scripts(<<0, 0>>, %{}, @cmap) == %{}
    end
  end

  describe "parse_gsub_substitutions_all_scripts/3" do
    test "accepts rlig as well as liga" do
      table = gsub_table(feature_tag: "rlig")

      assert GSUB.parse_gsub_substitutions_all_scripts(table, records(table), @cmap) ==
               %{"fi" => "ﬁ"}
    end

    test "accepts ccmp" do
      table = gsub_table(feature_tag: "ccmp")

      assert GSUB.parse_gsub_substitutions_all_scripts(table, records(table), @cmap) ==
               %{"fi" => "ﬁ"}
    end

    test "still ignores an unrelated feature" do
      table = gsub_table(feature_tag: "smcp")
      assert GSUB.parse_gsub_substitutions_all_scripts(table, records(table), @cmap) == %{}
    end

    test "returns an empty map for a font with no GSUB" do
      assert GSUB.parse_gsub_substitutions_all_scripts(<<0, 0>>, %{}, @cmap) == %{}
    end
  end

  describe "single substitution, format 1 (delta)" do
    test "shifts a covered glyph by the delta" do
      # glyph 1 ("f") + 1 -> glyph 2 ("i")
      table = single_subst_format_1(1, [1])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{"f" => "i"}
    end

    test "applies the same delta to every covered glyph" do
      table = single_subst_format_1(1, [1, 2])
      cmap = %{?a => 1, ?b => 2, ?c => 3}
      assert GSUB.parse_gsub_ligatures(table, records(table), cmap) == %{"a" => "b", "b" => "c"}
    end

    test "a negative delta shifts downwards" do
      table = single_subst_format_1(-1, [2])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{"i" => "f"}
    end

    test "drops a substitution that would produce a negative glyph id" do
      table = single_subst_format_1(-5, [1])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end

    test "drops a substitution whose result is not in the cmap" do
      table = single_subst_format_1(50, [1])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end
  end

  describe "single substitution, format 2 (explicit list)" do
    test "maps each covered glyph to its listed substitute" do
      # glyph 1 -> glyph 2, i.e. "f" -> "i"
      table = single_subst_format_2([2], [1])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{"f" => "i"}
    end

    test "maps several glyphs independently" do
      table = single_subst_format_2([2, 1], [1, 2])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{"f" => "i", "i" => "f"}
    end

    test "ignores the subtable when the substitute count disagrees with coverage" do
      # Two covered glyphs, one substitute: the table is internally inconsistent
      # and must be rejected rather than half-applied.
      table = single_subst_format_2([2], [1, 2])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end

    test "drops a substitute that is not in the cmap" do
      table = single_subst_format_2([99], [1])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end
  end

  describe "unknown single-substitution format" do
    test "an unrecognised subtable format yields nothing" do
      table = single_subst_table(<<7::16-big, 6::16-big, 0::16-big>>, [1])
      assert GSUB.parse_gsub_ligatures(table, records(table), @cmap) == %{}
    end
  end

  describe "malformed tables degrade rather than crash" do
    test "a truncated table yields no ligatures" do
      full = gsub_table()

      for cut <- [12, 20, 30, 45, 60, 70] do
        truncated = binary_part(full, 0, cut)

        assert GSUB.parse_gsub_ligatures(truncated, records(truncated), @cmap) == %{},
               "truncating to #{cut} bytes should degrade, not crash"
      end
    end

    test "a table of random bytes yields no ligatures" do
      # Deterministic pseudo-random: no crash on arbitrary input.
      junk = for i <- 1..200, into: <<>>, do: <<rem(i * 37, 256)>>
      assert GSUB.parse_gsub_ligatures(junk, records(junk), @cmap) == %{}
    end

    test "an empty cmap yields no ligatures" do
      table = gsub_table()
      assert GSUB.parse_gsub_ligatures(table, records(table), %{}) == %{}
    end
  end
end
