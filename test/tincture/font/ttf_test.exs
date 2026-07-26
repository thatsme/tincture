defmodule Tincture.Font.TTFTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias Tincture.Font.TTF

  test "parse_basic_tables/1 extracts head/maxp/hhea/hmtx metrics" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_binary())
    assert metrics.units_per_em == 1000
    assert metrics.num_glyphs == 3
    assert metrics.number_of_h_metrics == 2
    assert metrics.advance_widths == [500, 700, 700]
  end

  test "parse_basic_tables/1 also parses OTTO sfnt containers when required tables exist" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_metrics_binary())
    assert metrics.units_per_em == 1000
    assert metrics.advance_widths == [500, 700, 700]
  end

  test "parse_basic_tables/1 extracts max advance width from hmtx metrics" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_binary())
    assert metrics.max_advance_width == 700
  end

  test "parse_basic_tables/1 extracts a simple cmap mapping when present" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_binary())
    assert metrics.cmap_by_code[65] == 1
    assert metrics.cmap_by_code[66] == 2
    assert metrics.cmap_by_code[67] == 0
  end

  test "parse_basic_tables/1 extracts cmap format 4 mappings beyond latin-1 range" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format4_binary())
    assert metrics.cmap_by_code[9731] == 1
    assert metrics.cmap_by_code[9733] == 2
  end

  test "parse_basic_tables/1 extracts cmap format 6 trimmed-table mappings" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format6_binary())
    assert metrics.cmap_by_code[32] == 1
    assert metrics.cmap_by_code[33] == 2
    assert metrics.cmap_by_code[34] == 3
  end

  test "parse_basic_tables/1 extracts cmap format 2 high-byte mappings" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format2_binary())
    assert metrics.cmap_by_code[0x2603] == 1
    assert metrics.cmap_by_code[0x2604] == 2
  end

  test "parse_basic_tables/1 extracts cmap format 12 mappings for non-BMP codepoints" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format12_binary())
    assert metrics.cmap_by_code[0x1F600] == 1
    assert metrics.cmap_by_code[0x1F603] == 4
  end

  test "parse_basic_tables/1 extracts cmap format 13 many-to-one mappings" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format13_binary())
    assert metrics.cmap_by_code[0x2603] == 2
    assert metrics.cmap_by_code[0x2604] == 2
    assert metrics.cmap_by_code[0x2605] == 2
  end

  test "parse_basic_tables/1 extracts cmap format 10 trimmed 32-bit mappings" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format10_binary())
    assert metrics.cmap_by_code[0x2603] == 1
    assert metrics.cmap_by_code[0x2604] == 2
  end

  test "parse_basic_tables/1 extracts cmap format 8 group mappings" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format8_binary())
    assert metrics.cmap_by_code[0x2603] == 1
    assert metrics.cmap_by_code[0x2604] == 2
  end

  test "parse_basic_tables/1 extracts cmap format 14 variation selector metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_cmap_format14_binary())
    assert metrics.cmap_var_selectors == [0xFE0F]
    assert metrics.cmap_non_default_uvs[{0x2603, 0xFE0F}] == 1
  end

  test "parse_basic_tables/1 extracts loca/glyf offsets and glyph bounds when present" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_loca_glyf_binary())
    assert metrics.glyph_offsets == [0, 10, 20, 20]
    assert metrics.glyph_bboxes_by_id[0] == {0, -20, 500, 700}
    assert metrics.glyph_bboxes_by_id[1] == {0, -10, 700, 750}
    assert metrics.font_bbox == {0, -20, 700, 750}
    assert metrics.glyph_outline_types_by_id[0] == :simple
    assert metrics.glyph_outline_types_by_id[1] == :simple
    assert Map.has_key?(metrics.glyph_outline_types_by_id, 2) == false
    assert metrics.glyph_contour_counts_by_id[0] == 1
    assert metrics.glyph_contour_counts_by_id[1] == 1
    assert Map.has_key?(metrics.glyph_contour_counts_by_id, 2) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 0) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 1) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 2) == false
  end

  test "parse_basic_tables/1 extracts composite glyph outline metadata from loca/glyf tables" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_composite_loca_glyf_binary())
    assert metrics.glyph_outline_types_by_id[0] == :simple
    assert metrics.glyph_outline_types_by_id[1] == :composite
    assert Map.has_key?(metrics.glyph_outline_types_by_id, 2) == false
    assert metrics.glyph_contour_counts_by_id[0] == 1
    assert Map.has_key?(metrics.glyph_contour_counts_by_id, 1) == false
    assert Map.has_key?(metrics.glyph_contour_counts_by_id, 2) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 0) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 1) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 2) == false
    assert Map.has_key?(metrics.glyph_component_counts_by_id, 0) == false
    assert Map.has_key?(metrics.glyph_component_counts_by_id, 1) == false
    assert Map.has_key?(metrics.glyph_component_counts_by_id, 2) == false
    assert Map.has_key?(metrics.glyph_component_glyph_ids_by_id, 0) == false
    assert Map.has_key?(metrics.glyph_component_glyph_ids_by_id, 1) == false
    assert Map.has_key?(metrics.glyph_component_glyph_ids_by_id, 2) == false
  end

  test "parse_basic_tables/1 extracts composite glyph component-count metadata from loca/glyf tables" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_composite_components_loca_glyf_binary())

    assert metrics.glyph_outline_types_by_id[0] == :simple
    assert metrics.glyph_outline_types_by_id[1] == :composite
    assert metrics.glyph_contour_counts_by_id[0] == 1
    assert Map.has_key?(metrics.glyph_contour_counts_by_id, 1) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 0) == false
    assert Map.has_key?(metrics.glyph_point_counts_by_id, 1) == false
    assert metrics.glyph_component_counts_by_id[1] == 2
    assert metrics.glyph_component_glyph_ids_by_id[1] == [0, 2]
    assert Map.has_key?(metrics.glyph_composite_instruction_lengths_by_id, 1) == false
  end

  test "parse_basic_tables/1 extracts composite glyph instruction-length metadata from loca/glyf tables when instruction records are present" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_composite_instruction_lengths_loca_glyf_binary()
             )

    assert metrics.glyph_outline_types_by_id[1] == :composite
    assert metrics.glyph_component_counts_by_id[1] == 1
    assert metrics.glyph_component_glyph_ids_by_id[1] == [0]
    assert metrics.glyph_composite_instruction_lengths_by_id[1] == 2
  end

  test "parse_basic_tables/1 extracts simple glyph point-count metadata from loca/glyf tables when endpoint records are present" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_simple_point_counts_binary())
    assert metrics.glyph_outline_types_by_id[0] == :simple
    assert metrics.glyph_outline_types_by_id[1] == :simple
    assert metrics.glyph_contour_counts_by_id[0] == 1
    assert metrics.glyph_contour_counts_by_id[1] == 1
    assert metrics.glyph_point_counts_by_id[0] == 3
    assert metrics.glyph_point_counts_by_id[1] == 5
    assert metrics.glyph_simple_instruction_lengths_by_id[0] == 2
    assert metrics.glyph_simple_instruction_lengths_by_id[1] == 1
  end

  test "parse_basic_tables/1 extracts CFF FontBBox when loca/glyf tables are unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_font_bbox_binary())
    assert metrics.glyph_offsets == []
    assert metrics.glyph_bboxes_by_id == %{}
    assert metrics.glyph_outline_types_by_id == %{}
    assert metrics.glyph_contour_counts_by_id == %{}
    assert metrics.glyph_point_counts_by_id == %{}
    assert metrics.glyph_simple_instruction_lengths_by_id == %{}
    assert metrics.glyph_composite_instruction_lengths_by_id == %{}
    assert metrics.glyph_component_counts_by_id == %{}
    assert metrics.glyph_component_glyph_ids_by_id == %{}
    assert metrics.font_bbox == {-50, -200, 1100, 900}
  end

  test "parse_basic_tables/1 extracts CFF FontBBox when Top DICT uses real-number operands" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_real_font_bbox_binary())
    assert metrics.font_bbox == {-50, -200, 1100, 900}
  end

  test "parse_basic_tables/1 extracts CFF CharStrings outline metadata when loca/glyf tables are unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_charstrings_binary())
    assert metrics.cff_charstring_count == 3
    assert metrics.cff_charstring_lengths_by_id == %{0 => 1, 1 => 64, 2 => 72}
  end

  test "parse_basic_tables/1 extracts CFF CharStrings outline metadata when Top DICT includes real-number operands" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_otf_with_cff_charstrings_real_top_dict_binary())

    assert metrics.cff_charstring_count == 3
    assert metrics.cff_charstring_lengths_by_id == %{0 => 1, 1 => 64, 2 => 72}
  end

  test "parse_basic_tables/1 extracts CFF style metrics when post table is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_style_metrics_binary())
    assert_in_delta metrics.italic_angle, -12.0, 0.001
    assert metrics.fixed_pitch == true
    assert metrics.italic == true
  end

  test "parse_basic_tables/1 extracts CFF family name metadata when name table is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_family_name_binary())
    assert metrics.font_family == "CFF Demo Family"
  end

  test "parse_basic_tables/1 extracts CFF family name metadata from standard SID when name table is unavailable" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_otf_with_cff_standard_family_name_binary())

    assert metrics.font_family == "Regular"
  end

  test "parse_basic_tables/1 extracts CFF family fallback from FullName when FamilyName is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_full_name_binary())
    assert metrics.font_family == "CFF Demo FullName"
  end

  test "parse_basic_tables/1 extracts CFF family fallback from FontName when FamilyName and FullName are unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_font_name_binary())
    assert metrics.font_family == "CFF FontName Demo"
  end

  test "parse_basic_tables/1 extracts CFF weight metadata when OS/2 weight is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_weight_binary())
    assert metrics.cff_weight_class == 700
  end

  test "parse_basic_tables/1 extracts CFF weight metadata from standard SID when OS/2 weight is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_standard_weight_binary())
    assert metrics.cff_weight_class == 700
  end

  test "parse_basic_tables/1 extracts numeric CFF weight metadata when OS/2 weight is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_numeric_weight_binary())
    assert metrics.cff_weight_class == 650
  end

  test "parse_basic_tables/1 extracts hyphenated CFF weight metadata when OS/2 weight is unavailable" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_hyphen_weight_binary())
    assert metrics.cff_weight_class == 600
  end

  test "parse_basic_tables/1 extracts CFF StdVW stem metadata from Private DICT" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_stem_v_binary())
    assert metrics.cff_stem_v == 140
  end

  test "parse_basic_tables/1 extracts CFF StdHW stem metadata from Private DICT" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_stem_h_binary())
    assert metrics.cff_stem_h == 120
  end

  test "parse_basic_tables/1 extracts CFF ForceBold metadata from Private DICT" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_otf_with_cff_force_bold_binary())
    assert metrics.cff_force_bold == true
  end

  test "parse_basic_tables/1 extracts vertical metrics from hhea and OS/2 when present" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_binary())
    assert metrics.hhea_ascender == 760
    assert metrics.hhea_descender == -240
    assert metrics.hhea_line_gap == 0
    assert metrics.hhea_advance_width_max == 0
    assert metrics.typo_ascender == 780
    assert metrics.typo_descender == -220
    assert metrics.typo_line_gap == 0
    assert metrics.os2_win_ascent == 880
    assert metrics.os2_win_descent == 240
    assert metrics.x_height == 510
    assert metrics.cap_height == 730
    assert metrics.os2_weight_class == 700
    assert metrics.os2_width_class == 3
    assert metrics.os2_fs_type == 0
    assert metrics.os2_unicode_ranges == {0, 0, 0, 0}
    assert metrics.os2_code_page_ranges == {0, 0}
  end

  test "parse_basic_tables/1 extracts hhea and OS/2 line-gap metrics" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_line_gaps_binary())
    assert metrics.hhea_line_gap == 120
    assert metrics.typo_line_gap == 140
  end

  test "parse_basic_tables/1 extracts hhea advanceWidthMax metrics" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_hhea_advance_width_max_binary())

    assert metrics.hhea_advance_width_max == 900
  end

  test "parse_basic_tables/1 extracts OS/2 win ascent/descent fallback metrics" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_win_fallback_binary())
    assert metrics.hhea_ascender == 0
    assert metrics.hhea_descender == 0
    assert metrics.typo_ascender == 0
    assert metrics.typo_descender == 0
    assert metrics.os2_win_ascent == 840
    assert metrics.os2_win_descent == 260
  end

  test "parse_basic_tables/1 extracts OS/2 fsSelection bold/italic style metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_selection_binary())
    assert metrics.os2_version == 2
    assert metrics.os2_fs_selection == 33
    assert metrics.bold == true
    assert metrics.italic == true
    assert metrics.os2_bold == true
    assert metrics.os2_italic == true
  end

  test "parse_basic_tables/1 extracts OS/2 fsSelection oblique style metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_oblique_selection_binary())
    assert metrics.os2_version == 2
    assert metrics.os2_fs_selection == 512
    assert metrics.bold == false
    assert metrics.italic == true
    assert metrics.os2_bold == false
    assert metrics.os2_italic == false
    assert metrics.os2_oblique == true
  end

  test "parse_basic_tables/1 extracts OS/2 fsType embedding metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_fs_type_binary())
    assert metrics.os2_fs_type == 2
  end

  test "parse_basic_tables/1 extracts OS/2 average char width metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_avg_width_binary())
    assert metrics.os2_avg_char_width == 540
  end

  test "parse_basic_tables/1 extracts OS/2 default char metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_default_char_binary())
    assert metrics.os2_default_char == 65
  end

  test "parse_basic_tables/1 extracts OS/2 break char metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_break_char_binary())
    assert metrics.os2_break_char == 65
  end

  test "parse_basic_tables/1 extracts OS/2 first/last char index metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_char_range_binary())
    assert metrics.os2_first_char_index == 65
    assert metrics.os2_last_char_index == 66
  end

  test "parse_basic_tables/1 extracts OS/2 max context metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_max_context_binary())
    assert metrics.os2_max_context == 3
  end

  test "parse_basic_tables/1 extracts OS/2 family class and vendor id metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_family_vendor_binary())
    assert metrics.os2_family_class == 258
    assert metrics.os2_vendor_id == "TEST"
  end

  test "parse_basic_tables/1 extracts OS/2 optical point-size metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_optical_sizes_binary())
    assert metrics.os2_version == 5
    assert metrics.os2_lower_optical_point_size == 160
    assert metrics.os2_upper_optical_point_size == 720
  end

  test "parse_basic_tables/1 extracts OS/2 unicode range metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_unicode_ranges_binary())
    assert metrics.os2_unicode_ranges == {128, 0, 0, 0}
  end

  test "parse_basic_tables/1 extracts OS/2 code page range metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_codepage_ranges_binary())
    assert metrics.os2_code_page_ranges == {4, 0}
  end

  test "parse_basic_tables/1 extracts OS/2 panose metadata for descriptor style emission" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_panose_binary())
    assert metrics.os2_panose == <<2, 11, 6, 4, 2, 2, 2, 2, 2, 4>>
  end

  test "parse_basic_tables/1 extracts OS/2 subscript/superscript and strikeout metrics" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_os2_script_metrics_binary())
    assert metrics.os2_subscript_x_size == 650
    assert metrics.os2_subscript_y_size == 600
    assert metrics.os2_subscript_x_offset == -20
    assert metrics.os2_subscript_y_offset == 75
    assert metrics.os2_superscript_x_size == 660
    assert metrics.os2_superscript_y_size == 610
    assert metrics.os2_superscript_x_offset == 30
    assert metrics.os2_superscript_y_offset == 320
    assert metrics.os2_strikeout_size == 45
    assert metrics.os2_strikeout_position == 280
  end

  test "parse_basic_tables/1 extracts italic metadata from head/post tables" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_post_italic_binary())
    assert metrics.italic == true
    assert_in_delta metrics.italic_angle, -12.0, 0.001
  end

  test "parse_basic_tables/1 extracts fixed-pitch metadata from post table" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_post_fixed_pitch_binary())
    assert metrics.fixed_pitch == true
    assert_in_delta metrics.italic_angle, 0.0, 0.001
  end

  test "parse_basic_tables/1 extracts bold metadata from head macStyle" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_head_bold_binary())
    assert metrics.bold == true
    assert metrics.italic == false
  end

  test "parse_basic_tables/1 extracts family name metadata from name table" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_name_table_binary())
    assert metrics.font_family == "Demo Family"
  end

  test "parse_basic_tables/1 extracts GSUB/GPOS script and feature metadata" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_gsub_gpos_binary())
    assert metrics.gsub_scripts == ["latn"]
    assert metrics.gsub_features == ["liga"]
    assert metrics.gpos_scripts == ["latn"]
    assert metrics.gpos_features == ["kern"]
  end

  test "parse_basic_tables/1 extracts GSUB ligature substitutions from lookup tables" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_gsub_ligature_lookup_binary())
    assert metrics.gsub_ligatures == %{"st" => "ﬆ"}
  end

  test "parse_basic_tables/1 extracts GSUB single substitutions from lookup tables" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gsub_single_substitution_lookup_binary())

    assert metrics.gsub_ligatures == %{"A" => "B"}
  end

  test "parse_basic_tables/1 extracts GSUB rlig single substitutions into all-script shaping metadata" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gsub_single_substitution_rlig_lookup_binary())

    assert metrics.gsub_ligatures == %{}
    assert metrics.gsub_substitutions_all == %{"A" => "B"}
  end

  test "parse_basic_tables/1 ignores GSUB ligature lookups not referenced by liga feature" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gsub_ligature_lookup_without_liga_link_binary()
             )

    assert Enum.member?(metrics.gsub_features, "liga")
    assert metrics.gsub_ligatures == %{}
  end

  test "parse_basic_tables/1 prefers default GSUB LangSys over named LangSys for liga lookups" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gsub_default_langsys_without_liga_lookup_binary()
             )

    assert Enum.member?(metrics.gsub_features, "liga")
    assert metrics.gsub_ligatures == %{}
  end

  test "parse_basic_tables/1 extracts GPOS pair-kerning adjustments from lookup tables" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_gpos_pair_adjustment_binary())
    assert metrics.gpos_pair_kerns == %{{?A, ?V} => -80}
    assert metrics.gpos_guardrail_skips == 0
  end

  test "parse_basic_tables/1 extracts GPOS pair-kerning adjustments from ValueRecord2 xAdvance" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gpos_pair_adjustment_value2_binary())

    assert metrics.gpos_pair_kerns == %{{?A, ?V} => -80}
  end

  test "parse_basic_tables/1 skips malformed GPOS pair-kerning subtables when coverage count mismatches pair-set count" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_pair_adjustment_coverage_mismatch_binary()
             )

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping malformed GPOS pair-kerning subtables with coverage/pair-set mismatch" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_pair_adjustment_coverage_mismatch_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS pair subtable skipped"
    assert log =~ "coverage_glyph_count=2"
    assert log =~ "pair_set_count=1"
  end

  test "parse_basic_tables/1 ignores malformed GPOS pair-set with truncated pair-value records" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gpos_pair_adjustment_truncated_binary())

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 0
  end

  test "parse_basic_tables/1 skips oversized GPOS pair-set value records from format-1 lookups" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gpos_pair_adjustment_oversized_binary())

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping oversized GPOS pair-set value records from format-1 lookups" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(sample_ttf_with_gpos_pair_adjustment_oversized_binary())

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS pair-set skipped"
    assert log =~ "pair_value_count=10001"
  end

  test "parse_basic_tables/1 extracts GPOS class pair-kerning adjustments from format-2 lookup tables" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gpos_class_pair_adjustment_binary())

    assert metrics.gpos_pair_kerns == %{{?A, ?V} => -80, {?A, ?X} => -40}
  end

  test "parse_basic_tables/1 skips oversized GPOS class pair-kerning matrices" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gpos_class_pair_adjustment_oversized_binary())

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping oversized GPOS class pair-kerning matrices" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_class_pair_adjustment_oversized_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS class-pair matrix skipped"
    assert log =~ "class1_count=128"
    assert log =~ "class2_count=128"
  end

  test "parse_basic_tables/1 skips malformed GPOS class pair-kerning subtables with invalid class counts" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_class_pair_adjustment_invalid_class_counts_binary()
             )

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping malformed GPOS class pair-kerning subtables with invalid class counts" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_class_pair_adjustment_invalid_class_counts_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS class-pair subtable skipped"
    assert log =~ "class1_count=1"
    assert log =~ "class2_count=0"
  end

  test "parse_basic_tables/1 skips malformed GPOS class pair-kerning subtables with truncated class-adjustment records" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_class_pair_adjustment_truncated_records_binary()
             )

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping malformed GPOS class pair-kerning subtables with truncated class-adjustment records" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_class_pair_adjustment_truncated_records_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS class-pair subtable skipped"
    assert log =~ "malformed class adjustment records"
    assert log =~ "class1_count=2"
    assert log =~ "class2_count=3"
  end

  test "parse_basic_tables/1 skips malformed GPOS class pair-kerning subtables with invalid class-definition offsets" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_class_pair_adjustment_invalid_class_def_offsets_binary()
             )

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping malformed GPOS class pair-kerning subtables with invalid class-definition offsets" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_class_pair_adjustment_invalid_class_def_offsets_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS class-pair subtable skipped"
    assert log =~ "malformed class definition tables"
    assert log =~ "class1_count=2"
    assert log =~ "class2_count=3"
  end

  test "parse_basic_tables/1 skips oversized expanded GPOS class pair-kerning mappings" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_class_pair_adjustment_expansion_oversized_binary()
             )

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping oversized expanded GPOS class pair-kerning mappings" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_class_pair_adjustment_expansion_oversized_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS class-pair expansion skipped"
    assert log =~ "estimated_pairs="
  end

  test "parse_basic_tables/1 skips oversized GPOS class-definition expansions in format-2 lookups" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_class_pair_adjustment_classdef_oversized_binary()
             )

    assert metrics.gpos_pair_kerns == %{}
    assert metrics.gpos_guardrail_skips == 1
  end

  test "parse_basic_tables/1 logs when skipping oversized GPOS class-definition expansions in format-2 lookups" do
    log =
      capture_log(fn ->
        assert {:ok, metrics} =
                 TTF.parse_basic_tables(
                   sample_ttf_with_gpos_class_pair_adjustment_classdef_oversized_binary()
                 )

        assert metrics.gpos_pair_kerns == %{}
        assert metrics.gpos_guardrail_skips == 1
      end)

    assert log =~ "GPOS class definition skipped"
    assert log =~ "entries=10002"
  end

  test "parse_basic_tables/1 ignores GPOS pair lookups not referenced by kern feature" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_pair_adjustment_without_kern_link_binary()
             )

    assert Enum.member?(metrics.gpos_features, "kern")
    assert metrics.gpos_pair_kerns == %{}
  end

  test "parse_basic_tables/1 prefers default GPOS LangSys over named LangSys for kern lookups" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(
               sample_ttf_with_gpos_default_langsys_without_kern_lookup_binary()
             )

    assert Enum.member?(metrics.gpos_features, "kern")
    assert metrics.gpos_pair_kerns == %{}
  end

  test "parse_basic_tables/1 prefers latn script over other scripts for GSUB liga lookups" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gsub_liga_lookup_only_on_arab_script_binary())

    assert Enum.member?(metrics.gsub_scripts, "latn")
    assert metrics.gsub_ligatures == %{}
    assert metrics.gsub_ligatures_all == %{"st" => "ﬆ"}
  end

  test "parse_basic_tables/1 prefers latn script over other scripts for GPOS kern lookups" do
    assert {:ok, metrics} =
             TTF.parse_basic_tables(sample_ttf_with_gpos_kern_lookup_only_on_arab_script_binary())

    assert Enum.member?(metrics.gpos_scripts, "latn")
    assert metrics.gpos_pair_kerns == %{}
  end

  test "parse_basic_tables/1 extracts head table FontBBox fallback metrics" do
    assert {:ok, metrics} = TTF.parse_basic_tables(sample_ttf_with_head_bbox_binary())
    assert metrics.head_bbox == {-50, -200, 1100, 900}
  end

  test "parse_basic_tables/1 returns :error for malformed or incomplete data" do
    assert :error = TTF.parse_basic_tables(<<0, 1, 0, 0>>)
    assert :error = TTF.parse_basic_tables(missing_required_table_ttf_binary())
  end

  defp sample_ttf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp sample_otf_with_metrics_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 0}, {66, 1}])}
    ])
  end

  defp missing_required_table_ttf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 1::16-big>>},
      {"hmtx", <<600::16-big, 0::16-signed-big>>}
    ])
  end

  defp sample_ttf_with_cmap_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])}
    ])
  end

  defp sample_ttf_with_cmap_format4_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{9731, 1}, {9733, 2}])}
    ])
  end

  defp sample_ttf_with_cmap_format6_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 700::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format6(32, [1, 2, 3])}
    ])
  end

  defp sample_ttf_with_cmap_format2_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format2(0x26, 0x03, [1, 2])}
    ])
  end

  defp sample_ttf_with_cmap_format12_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 6::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big, 0::16-signed-big, 0::16-signed-big, 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format12([{0x1F600, 0x1F603, 1}])}
    ])
  end

  defp sample_ttf_with_cmap_format13_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format13([{0x2603, 0x2605, 2}])}
    ])
  end

  defp sample_ttf_with_cmap_format10_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format10(0x2603, [1, 2])}
    ])
  end

  defp sample_ttf_with_cmap_format8_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format8([{0x2603, 0x2604, 1}])}
    ])
  end

  defp sample_ttf_with_cmap_format14_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format14(0xFE0F, [{0x2603, 1}])}
    ])
  end

  defp sample_ttf_with_loca_glyf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"loca", <<0::16-big, 5::16-big, 10::16-big, 10::16-big>>},
      {"glyf",
       <<
         1::16-signed-big,
         0::16-signed-big,
         -20::16-signed-big,
         500::16-signed-big,
         700::16-signed-big,
         1::16-signed-big,
         0::16-signed-big,
         -10::16-signed-big,
         700::16-signed-big,
         750::16-signed-big
       >>}
    ])
  end

  defp sample_ttf_with_composite_loca_glyf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"loca", <<0::16-big, 5::16-big, 10::16-big, 10::16-big>>},
      {"glyf",
       <<
         1::16-signed-big,
         0::16-signed-big,
         -20::16-signed-big,
         500::16-signed-big,
         700::16-signed-big,
         -1::16-signed-big,
         0::16-signed-big,
         -10::16-signed-big,
         700::16-signed-big,
         750::16-signed-big
       >>}
    ])
  end

  defp sample_ttf_with_composite_components_loca_glyf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"loca", <<0::16-big, 5::16-big, 16::16-big, 16::16-big>>},
      {"glyf",
       <<
         1::16-signed-big,
         0::16-signed-big,
         -20::16-signed-big,
         500::16-signed-big,
         700::16-signed-big,
         -1::16-signed-big,
         0::16-signed-big,
         -10::16-signed-big,
         700::16-signed-big,
         750::16-signed-big,
         0x0020::16-big,
         0::16-big,
         0::8,
         0::8,
         0x0000::16-big,
         2::16-big,
         0::8,
         0::8
       >>}
    ])
  end

  defp sample_ttf_with_simple_point_counts_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"loca", <<0::16-big, 8::16-big, 16::16-big, 16::16-big>>},
      {"glyf",
       <<
         1::16-signed-big,
         0::16-signed-big,
         -20::16-signed-big,
         500::16-signed-big,
         700::16-signed-big,
         2::16-big,
         2::16-big,
         1::8,
         0::8,
         1::16-signed-big,
         0::16-signed-big,
         -10::16-signed-big,
         700::16-signed-big,
         750::16-signed-big,
         4::16-big,
         1::16-big,
         255::8,
         0::8
       >>}
    ])
  end

  defp sample_ttf_with_composite_instruction_lengths_loca_glyf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"loca", <<0::16-big, 5::16-big, 15::16-big, 15::16-big>>},
      {"glyf",
       <<
         1::16-signed-big,
         0::16-signed-big,
         -20::16-signed-big,
         500::16-signed-big,
         700::16-signed-big,
         -1::16-signed-big,
         0::16-signed-big,
         -10::16-signed-big,
         700::16-signed-big,
         750::16-signed-big,
         0x0100::16-big,
         0::16-big,
         0::8,
         0::8,
         2::16-big,
         0xAA::8,
         0xBB::8
       >>}
    ])
  end

  defp sample_otf_with_cff_font_bbox_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_font_bbox(-50, -200, 1100, 900)}
    ])
  end

  defp sample_otf_with_cff_real_font_bbox_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_real_font_bbox()}
    ])
  end

  defp sample_otf_with_cff_style_metrics_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_style_metrics(1, -12)}
    ])
  end

  defp sample_otf_with_cff_charstrings_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big>>},
      {"CFF ",
       cff_table_with_charstrings([
         <<14>>,
         :binary.copy(<<139>>, 64),
         :binary.copy(<<140>>, 72)
       ])}
    ])
  end

  defp sample_otf_with_cff_charstrings_real_top_dict_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big>>},
      {"CFF ",
       cff_table_with_charstrings(
         [
           <<14>>,
           :binary.copy(<<139>>, 64),
           :binary.copy(<<140>>, 72)
         ],
         cff_top_dict_font_matrix_prefix()
       )}
    ])
  end

  defp sample_otf_with_cff_family_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_family_name("CFF Demo Family")}
    ])
  end

  defp sample_otf_with_cff_standard_family_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_family_name_sid(388)}
    ])
  end

  defp sample_otf_with_cff_full_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_full_name("CFF Demo FullName")}
    ])
  end

  defp sample_otf_with_cff_font_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_font_name("CFF FontName Demo")}
    ])
  end

  defp sample_otf_with_cff_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight("Bold")}
    ])
  end

  defp sample_otf_with_cff_standard_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight_sid(384)}
    ])
  end

  defp sample_otf_with_cff_numeric_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight("650")}
    ])
  end

  defp sample_otf_with_cff_hyphen_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight("Semi-Bold")}
    ])
  end

  defp sample_otf_with_cff_stem_v_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_stem_v(140)}
    ])
  end

  defp sample_otf_with_cff_stem_h_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_stem_h(120)}
    ])
  end

  defp sample_otf_with_cff_force_bold_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_force_bold()}
    ])
  end

  defp sample_ttf_with_os2_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::size(26)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)}
    ])
  end

  defp sample_ttf_with_os2_win_fallback_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea", <<0::32-big, 0::16-signed-big, 0::16-signed-big, 0::size(26)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(0, 0, 840, 260, 510, 730, 500, 5, 0)}
    ])
  end

  defp sample_ttf_with_os2_selection_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(0, 0, 840, 260, 510, 730, 500, 5, 33)}
    ])
  end

  defp sample_ttf_with_os2_oblique_selection_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(0, 0, 840, 260, 510, 730, 500, 5, 512)}
    ])
  end

  defp sample_ttf_with_os2_fs_type_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 2)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big,
         0::size(24)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_avg_width_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_s16_at(2, 540)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big,
         0::size(24)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_default_char_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(90, 65)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}])},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_break_char_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(92, 65)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}])},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_char_range_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(64, 65)
      |> write_u16_at(66, 66)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_max_context_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(94, 3)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_family_vendor_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_s16_at(30, 258)
      |> write_bytes_at(58, "TEST")

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_optical_sizes_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> Kernel.<>(<<0::16-big, 0::16-big>>)
      |> write_u16_at(0, 5)
      |> write_u16_at(96, 160)
      |> write_u16_at(98, 720)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_unicode_ranges_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u32_at(42, 128)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_os2_codepage_ranges_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u32_at(78, 4)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_line_gaps_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_s16_at(72, 140)

    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 120::16-signed-big,
         0::size(24)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_hhea_advance_width_max_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 900::16-big,
         0::size(22)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp sample_ttf_with_os2_panose_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2",
       os2_table_with_panose(
         0,
         0,
         840,
         260,
         510,
         730,
         500,
         5,
         0,
         <<2, 11, 6, 4, 2, 2, 2, 2, 2, 4>>
       )}
    ])
  end

  defp sample_ttf_with_os2_script_metrics_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_s16_at(10, 650)
      |> write_s16_at(12, 600)
      |> write_s16_at(14, -20)
      |> write_s16_at(16, 75)
      |> write_s16_at(18, 660)
      |> write_s16_at(20, 610)
      |> write_s16_at(22, 30)
      |> write_s16_at(24, 320)
      |> write_s16_at(26, 45)
      |> write_s16_at(28, 280)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp sample_ttf_with_post_italic_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(24)-unit(8), 2::16-big, 0::16-big,
         0::16-signed-big, 0::16-signed-big, 0::16-signed-big>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"post", <<0x0003_0000::32-big, -786_432::32-signed-big>>}
    ])
  end

  defp sample_ttf_with_post_fixed_pitch_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"post",
       <<0x0003_0000::32-big, 0::32-signed-big, 0::16-signed-big, 0::16-signed-big, 1::32-big,
         0::32-big, 0::32-big, 0::32-big, 0::32-big>>}
    ])
  end

  defp sample_ttf_with_head_bold_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(24)-unit(8), 1::16-big, 0::16-big,
         0::16-signed-big, 0::16-signed-big, 0::16-signed-big>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp sample_ttf_with_name_table_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"name", name_table("Demo Family")}
    ])
  end

  defp sample_ttf_with_gsub_gpos_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"GSUB", layout_table_with_script_and_feature("latn", "liga")},
      {"GPOS", layout_table_with_script_and_feature("latn", "kern")}
    ])
  end

  defp sample_ttf_with_gsub_ligature_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big, 800::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?s, 1}, {?t, 2}, {0xFB06, 3}])},
      {"GSUB", gsub_ligature_table(1, [2], 3)}
    ])
  end

  defp sample_ttf_with_gsub_single_substitution_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?B, 2}])},
      {"GSUB", gsub_single_substitution_table(1, 2)}
    ])
  end

  defp sample_ttf_with_gsub_single_substitution_rlig_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?B, 2}])},
      {"GSUB", gsub_single_substitution_table_with_feature("rlig", 1, 2)}
    ])
  end

  defp sample_ttf_with_gsub_ligature_lookup_without_liga_link_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big, 800::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?s, 1}, {?t, 2}, {0xFB06, 3}])},
      {"GSUB", gsub_ligature_table_without_liga_lookup_link(1, [2], 3)}
    ])
  end

  defp sample_ttf_with_gsub_default_langsys_without_liga_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big, 800::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?s, 1}, {?t, 2}, {0xFB06, 3}])},
      {"GSUB", gsub_ligature_table_default_langsys_without_lookup(1, [2], 3)}
    ])
  end

  defp sample_ttf_with_gpos_pair_adjustment_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_gpos_pair_adjustment_value2_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_value2(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_gpos_pair_adjustment_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_oversized(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_gpos_pair_adjustment_coverage_mismatch_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 600::16-big,
         0::16-signed-big, 500::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?B, 2}, {?V, 3}, {?X, 4}])},
      {"GPOS", gpos_pair_adjustment_table_coverage_mismatch(1, 2, 3, -80)}
    ])
  end

  defp sample_ttf_with_gpos_pair_adjustment_truncated_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_truncated(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table(1, 2, 3, -80, -40)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_oversized(1, 2, 3, -80, -40)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_expansion_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap",
       cmap_format12([{?A, ?A, 1}, {?B, ?B, 4}, {?V, ?V, 2}, {?X, ?X, 3}, {0x1000, 0x370F, 2}])},
      {"GPOS", gpos_pair_adjustment_class_table_expansion_oversized(1, 4, -80)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_classdef_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_classdef_oversized(1, -80)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_invalid_class_counts_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_invalid_class_counts(1, 2)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_truncated_records_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_truncated_records(1)}
    ])
  end

  defp sample_ttf_with_gpos_class_pair_adjustment_invalid_class_def_offsets_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_invalid_class_def_offsets(1)}
    ])
  end

  defp sample_ttf_with_gpos_pair_adjustment_without_kern_link_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_without_kern_lookup_link(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_gpos_default_langsys_without_kern_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_default_langsys_without_lookup(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_gsub_liga_lookup_only_on_arab_script_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big, 800::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?s, 1}, {?t, 2}, {0xFB06, 3}])},
      {"GSUB", gsub_ligature_table_liga_lookup_only_on_arab_script(1, [2], 3)}
    ])
  end

  defp sample_ttf_with_gpos_kern_lookup_only_on_arab_script_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_kern_lookup_only_on_arab_script(1, 2, -80)}
    ])
  end

  defp sample_ttf_with_head_bbox_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(16)-unit(8), -50::16-signed-big,
         -200::16-signed-big, 1100::16-signed-big, 900::16-signed-big, 0::size(10)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp cmap_format0(entries) do
    glyph_ids =
      Enum.reduce(entries, :array.new(256, default: 0), fn {code, glyph_id}, acc ->
        :array.set(code, glyph_id, acc)
      end)
      |> :array.to_list()
      |> :erlang.list_to_binary()

    subtable =
      <<0::16-big, 262::16-big, 0::16-big, glyph_ids::binary>>

    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format4(entries) do
    sorted_entries = Enum.sort_by(entries, &elem(&1, 0))

    seg_data =
      Enum.map(sorted_entries, fn {code, glyph_id} ->
        delta = Integer.mod(glyph_id - code, 65_536)
        signed_delta = if delta > 32_767, do: delta - 65_536, else: delta
        {code, code, signed_delta, 0}
      end)

    segments = seg_data ++ [{0xFFFF, 0xFFFF, 1, 0}]
    seg_count = length(segments)

    end_codes = Enum.map(segments, fn {_, e, _, _} -> e end)
    start_codes = Enum.map(segments, fn {s, _, _, _} -> s end)
    id_deltas = Enum.map(segments, fn {_, _, d, _} -> d end)
    id_range_offsets = Enum.map(segments, fn {_, _, _, r} -> r end)

    subtable =
      <<
        4::16-big,
        16 + seg_count * 8::16-big,
        0::16-big,
        seg_count * 2::16-big,
        0::16-big,
        0::16-big,
        0::16-big,
        pack_u16(end_codes)::binary,
        0::16-big,
        pack_u16(start_codes)::binary,
        pack_s16(id_deltas)::binary,
        pack_u16(id_range_offsets)::binary
      >>

    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format6(first_code, glyph_ids)
       when is_integer(first_code) and first_code >= 0 and first_code <= 0xFFFF and
              is_list(glyph_ids) do
    entry_count = length(glyph_ids)
    glyph_data = pack_u16(glyph_ids)

    subtable =
      <<
        6::16-big,
        10 + entry_count * 2::16-big,
        0::16-big,
        first_code::16-big,
        entry_count::16-big,
        glyph_data::binary
      >>

    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format2(high_byte, first_low_byte, glyph_ids)
       when is_integer(high_byte) and high_byte >= 0 and high_byte <= 0xFF and
              is_integer(first_low_byte) and first_low_byte >= 0 and first_low_byte <= 0xFF and
              is_list(glyph_ids) and glyph_ids != [] do
    entry_count = length(glyph_ids)
    expected = Enum.to_list(1..entry_count)

    unless glyph_ids == expected do
      raise ArgumentError, "cmap_format2/3 expects contiguous glyph IDs starting at 1"
    end

    keys =
      for idx <- 0..255 do
        if idx == high_byte, do: 8, else: 0
      end

    id_delta = 1 - first_low_byte

    subtable =
      <<
        2::16-big,
        6 + 512 + 16::16-big,
        0::16-big,
        pack_u16(keys)::binary,
        0::16-big,
        0::16-big,
        0::16-signed-big,
        0::16-big,
        first_low_byte::16-big,
        entry_count::16-big,
        id_delta::16-signed-big,
        0::16-big
      >>

    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format12(groups) do
    n_groups = length(groups)

    group_data =
      groups
      |> Enum.map(fn {start_code, end_code, start_glyph_id} ->
        <<start_code::32-big, end_code::32-big, start_glyph_id::32-big>>
      end)
      |> IO.iodata_to_binary()

    subtable =
      <<
        12::16-big,
        0::16-big,
        16 + n_groups * 12::32-big,
        0::32-big,
        n_groups::32-big,
        group_data::binary
      >>

    <<0::16-big, 1::16-big, 3::16-big, 10::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format13(groups) do
    n_groups = length(groups)

    group_data =
      groups
      |> Enum.map(fn {start_code, end_code, glyph_id} ->
        <<start_code::32-big, end_code::32-big, glyph_id::32-big>>
      end)
      |> IO.iodata_to_binary()

    subtable =
      <<
        13::16-big,
        0::16-big,
        16 + n_groups * 12::32-big,
        0::32-big,
        n_groups::32-big,
        group_data::binary
      >>

    <<0::16-big, 1::16-big, 3::16-big, 10::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format10(start_char_code, glyph_ids)
       when is_integer(start_char_code) and start_char_code >= 0 and
              start_char_code <= 0xFFFF_FFFF and is_list(glyph_ids) do
    num_chars = length(glyph_ids)
    glyph_data = pack_u16(glyph_ids)

    subtable =
      <<
        10::16-big,
        0::16-big,
        20 + num_chars * 2::32-big,
        0::32-big,
        start_char_code::32-big,
        num_chars::32-big,
        glyph_data::binary
      >>

    <<0::16-big, 1::16-big, 3::16-big, 10::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format8(groups) do
    n_groups = length(groups)

    group_data =
      groups
      |> Enum.map(fn {start_code, end_code, start_glyph_id} ->
        <<start_code::32-big, end_code::32-big, start_glyph_id::32-big>>
      end)
      |> IO.iodata_to_binary()

    subtable =
      <<
        8::16-big,
        0::16-big,
        16 + 8192 + n_groups * 12::32-big,
        0::32-big,
        0::size(8192)-unit(8),
        n_groups::32-big,
        group_data::binary
      >>

    <<0::16-big, 1::16-big, 3::16-big, 10::16-big, 12::32-big, subtable::binary>>
  end

  defp cmap_format14(selector, non_default_mappings)
       when is_integer(selector) and selector >= 0 and selector <= 0xFFFFFF and
              is_list(non_default_mappings) do
    non_default_table =
      [
        <<length(non_default_mappings)::32-big>>,
        Enum.map(non_default_mappings, fn {unicode_value, glyph_id} ->
          <<unicode_value::24-big, glyph_id::16-big>>
        end)
      ]
      |> IO.iodata_to_binary()

    selector_record_offset = 10 + 11
    subtable_length = selector_record_offset + byte_size(non_default_table)

    subtable =
      <<
        14::16-big,
        subtable_length::32-big,
        1::32-big,
        selector::24-big,
        0::32-big,
        selector_record_offset::32-big,
        non_default_table::binary
      >>

    <<0::16-big, 1::16-big, 0::16-big, 5::16-big, 12::32-big, subtable::binary>>
  end

  defp cff_table_with_font_bbox(x_min, y_min, x_max, y_max) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(x_min),
        cff_shortint(y_min),
        cff_shortint(x_max),
        cff_shortint(y_max),
        <<5>>
      ])

    cff_table_with_top_dict(top_dict)
  end

  defp cff_table_with_style_metrics(is_fixed_pitch, italic_angle) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(is_fixed_pitch),
        <<12, 1>>,
        cff_shortint(italic_angle),
        <<12, 2>>
      ])

    cff_table_with_top_dict(top_dict)
  end

  defp cff_table_with_real_font_bbox do
    top_dict =
      IO.iodata_to_binary([
        cff_real_minus_50_4(),
        cff_shortint(-200),
        cff_shortint(1100),
        cff_shortint(900),
        <<5>>
      ])

    cff_table_with_top_dict(top_dict)
  end

  defp cff_table_with_family_name(family_name) when is_binary(family_name) do
    cff_table_with_family_name_sid(391, [family_name])
  end

  defp cff_table_with_full_name(full_name) when is_binary(full_name) do
    cff_table_with_full_name_sid(391, [full_name])
  end

  defp cff_table_with_weight(weight_name) when is_binary(weight_name) do
    cff_table_with_weight_sid(391, [weight_name])
  end

  defp cff_table_with_font_name(font_name) when is_binary(font_name) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(391),
        <<12, 38>>
      ])

    cff_table_with_top_dict(top_dict, [font_name])
  end

  defp cff_table_with_family_name_sid(sid, string_index_entries \\ [])
       when is_integer(sid) and sid >= 0 and sid <= 65_535 and is_list(string_index_entries) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(sid),
        <<3>>
      ])

    cff_table_with_top_dict(top_dict, string_index_entries)
  end

  defp cff_table_with_full_name_sid(sid, string_index_entries)
       when is_integer(sid) and sid >= 0 and sid <= 65_535 and is_list(string_index_entries) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(sid),
        <<2>>
      ])

    cff_table_with_top_dict(top_dict, string_index_entries)
  end

  defp cff_table_with_weight_sid(sid, string_index_entries \\ [])
       when is_integer(sid) and sid >= 0 and sid <= 65_535 and is_list(string_index_entries) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(sid),
        <<4>>
      ])

    cff_table_with_top_dict(top_dict, string_index_entries)
  end

  defp cff_table_with_stem_v(stem_v)
       when is_integer(stem_v) and stem_v > 0 and stem_v <= 65_535 do
    header = <<1, 0, 4, 1>>
    name_index = cff_index([<<"A">>])
    string_index = cff_index([])
    global_subr_index = cff_index([])
    private_dict = IO.iodata_to_binary([cff_shortint(stem_v), <<11>>])
    private_size = byte_size(private_dict)

    placeholder_top_dict =
      IO.iodata_to_binary([
        cff_shortint(private_size),
        cff_shortint(0),
        <<18>>
      ])

    placeholder_top_dict_index = cff_index([placeholder_top_dict])

    private_offset =
      byte_size(header) +
        byte_size(name_index) +
        byte_size(placeholder_top_dict_index) +
        byte_size(string_index) +
        byte_size(global_subr_index)

    top_dict =
      IO.iodata_to_binary([
        cff_shortint(private_size),
        cff_shortint(private_offset),
        <<18>>
      ])

    top_dict_index = cff_index([top_dict])

    IO.iodata_to_binary([
      header,
      name_index,
      top_dict_index,
      string_index,
      global_subr_index,
      private_dict
    ])
  end

  defp cff_table_with_stem_h(stem_h)
       when is_integer(stem_h) and stem_h > 0 and stem_h <= 65_535 do
    header = <<1, 0, 4, 1>>
    name_index = cff_index([<<"A">>])
    string_index = cff_index([])
    global_subr_index = cff_index([])
    private_dict = IO.iodata_to_binary([cff_shortint(stem_h), <<10>>])
    private_size = byte_size(private_dict)

    placeholder_top_dict =
      IO.iodata_to_binary([
        cff_shortint(private_size),
        cff_shortint(0),
        <<18>>
      ])

    placeholder_top_dict_index = cff_index([placeholder_top_dict])

    private_offset =
      byte_size(header) +
        byte_size(name_index) +
        byte_size(placeholder_top_dict_index) +
        byte_size(string_index) +
        byte_size(global_subr_index)

    top_dict =
      IO.iodata_to_binary([
        cff_shortint(private_size),
        cff_shortint(private_offset),
        <<18>>
      ])

    top_dict_index = cff_index([top_dict])

    IO.iodata_to_binary([
      header,
      name_index,
      top_dict_index,
      string_index,
      global_subr_index,
      private_dict
    ])
  end

  defp cff_table_with_force_bold do
    header = <<1, 0, 4, 1>>
    name_index = cff_index([<<"A">>])
    string_index = cff_index([])
    global_subr_index = cff_index([])
    private_dict = IO.iodata_to_binary([cff_shortint(1), <<14>>])
    private_size = byte_size(private_dict)

    placeholder_top_dict =
      IO.iodata_to_binary([
        cff_shortint(private_size),
        cff_shortint(0),
        <<18>>
      ])

    placeholder_top_dict_index = cff_index([placeholder_top_dict])

    private_offset =
      byte_size(header) +
        byte_size(name_index) +
        byte_size(placeholder_top_dict_index) +
        byte_size(string_index) +
        byte_size(global_subr_index)

    top_dict =
      IO.iodata_to_binary([
        cff_shortint(private_size),
        cff_shortint(private_offset),
        <<18>>
      ])

    top_dict_index = cff_index([top_dict])

    IO.iodata_to_binary([
      header,
      name_index,
      top_dict_index,
      string_index,
      global_subr_index,
      private_dict
    ])
  end

  defp cff_table_with_top_dict(top_dict, string_index_entries \\ []) do
    IO.iodata_to_binary([
      <<1, 0, 4, 1>>,
      cff_index([<<"A">>]),
      cff_index([top_dict]),
      cff_index(string_index_entries),
      <<0::16-big>>
    ])
  end

  defp cff_table_with_charstrings(charstrings, top_dict_prefix \\ <<>>)
       when is_list(charstrings) and charstrings != [] and is_binary(top_dict_prefix) do
    normalized_charstrings =
      Enum.map(charstrings, fn charstring ->
        case charstring do
          data when is_binary(data) and byte_size(data) > 0 -> data
          _ -> <<14>>
        end
      end)

    header = <<1, 0, 4, 1>>
    name_index = cff_index([<<"A">>])
    string_index = cff_index([])
    global_subr_index = cff_index([])

    placeholder_top_dict_index =
      cff_index([IO.iodata_to_binary([top_dict_prefix, cff_shortint(0), <<17>>])])

    charstrings_offset =
      byte_size(header) +
        byte_size(name_index) +
        byte_size(placeholder_top_dict_index) +
        byte_size(string_index) +
        byte_size(global_subr_index)

    top_dict =
      IO.iodata_to_binary([
        top_dict_prefix,
        cff_shortint(charstrings_offset),
        <<17>>
      ])

    top_dict_index = cff_index([top_dict])
    charstrings_index = cff_index(normalized_charstrings)

    IO.iodata_to_binary([
      header,
      name_index,
      top_dict_index,
      string_index,
      global_subr_index,
      charstrings_index
    ])
  end

  defp cff_index(entries) when is_list(entries) do
    count = length(entries)

    if count == 0 do
      <<0::16-big>>
    else
      entry_data = IO.iodata_to_binary(entries)

      offsets =
        entries
        |> Enum.reduce({[1], 1}, fn entry, {acc, current} ->
          next = current + byte_size(entry)
          {[next | acc], next}
        end)
        |> elem(0)
        |> Enum.reverse()

      max_offset = List.last(offsets)

      off_size =
        cond do
          max_offset <= 0xFF -> 1
          max_offset <= 0xFFFF -> 2
          max_offset <= 0xFF_FFFF -> 3
          true -> 4
        end

      encoded_offsets =
        offsets
        |> Enum.map(&cff_index_offset(&1, off_size))
        |> IO.iodata_to_binary()

      <<count::16-big, off_size::8, encoded_offsets::binary, entry_data::binary>>
    end
  end

  defp cff_index_offset(offset, off_size)
       when is_integer(offset) and offset >= 0 and is_integer(off_size) and off_size >= 1 and
              off_size <= 4 do
    encoded = :binary.encode_unsigned(offset)
    padding_bytes = max(off_size - byte_size(encoded), 0)
    <<0::size(padding_bytes)-unit(8), encoded::binary>>
  end

  defp cff_shortint(value) when is_integer(value) do
    <<28, value::16-signed-big>>
  end

  defp cff_real_minus_50_4 do
    <<30, 0xE5, 0x0A, 0x4F>>
  end

  defp cff_top_dict_font_matrix_prefix do
    IO.iodata_to_binary([
      cff_real_0_001(),
      cff_shortint(0),
      cff_shortint(0),
      cff_real_0_001(),
      cff_shortint(0),
      cff_shortint(0),
      <<12, 7>>
    ])
  end

  defp cff_real_0_001 do
    <<30, 0x0A, 0x00, 0x1F>>
  end

  defp os2_table(
         typo_ascender,
         typo_descender,
         win_ascent,
         win_descent,
         x_height,
         cap_height,
         weight_class,
         width_class,
         fs_selection
       ) do
    <<
      2::16-big,
      0::16-signed-big,
      weight_class::16-big,
      width_class::16-big,
      0::16-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::16-signed-big,
      0::size(10)-unit(8),
      0::32-big,
      0::32-big,
      0::32-big,
      0::32-big,
      0::32-big,
      fs_selection::16-big,
      0::16-big,
      0::16-big,
      typo_ascender::16-signed-big,
      typo_descender::16-signed-big,
      0::16-signed-big,
      win_ascent::16-big,
      win_descent::16-big,
      0::32-big,
      0::32-big,
      x_height::16-signed-big,
      cap_height::16-signed-big,
      0::16-big,
      0::16-big,
      0::16-big
    >>
  end

  defp os2_table_with_panose(
         typo_ascender,
         typo_descender,
         win_ascent,
         win_descent,
         x_height,
         cap_height,
         weight_class,
         width_class,
         fs_selection,
         panose
       )
       when is_binary(panose) and byte_size(panose) == 10 do
    base =
      os2_table(
        typo_ascender,
        typo_descender,
        win_ascent,
        win_descent,
        x_height,
        cap_height,
        weight_class,
        width_class,
        fs_selection
      )

    <<prefix::binary-size(32), _old_panose::binary-size(10), suffix::binary>> = base
    <<prefix::binary, panose::binary, suffix::binary>>
  end

  defp write_s16_at(bin, offset, value)
       when is_binary(bin) and is_integer(offset) and offset >= 0 and is_integer(value) do
    <<prefix::binary-size(offset), _old::16-signed-big, suffix::binary>> = bin
    <<prefix::binary, value::16-signed-big, suffix::binary>>
  end

  defp write_u16_at(bin, offset, value)
       when is_binary(bin) and is_integer(offset) and offset >= 0 and is_integer(value) and
              value >= 0 and value <= 65_535 do
    <<prefix::binary-size(offset), _old::16-big, suffix::binary>> = bin
    <<prefix::binary, value::16-big, suffix::binary>>
  end

  defp write_u32_at(bin, offset, value)
       when is_binary(bin) and is_integer(offset) and offset >= 0 and is_integer(value) and
              value >= 0 and value <= 4_294_967_295 do
    <<prefix::binary-size(offset), _old::32-big, suffix::binary>> = bin
    <<prefix::binary, value::32-big, suffix::binary>>
  end

  defp write_bytes_at(bin, offset, replacement)
       when is_binary(bin) and is_integer(offset) and offset >= 0 and is_binary(replacement) do
    size = byte_size(replacement)
    <<prefix::binary-size(offset), _old::binary-size(size), suffix::binary>> = bin
    <<prefix::binary, replacement::binary, suffix::binary>>
  end

  defp name_table(family_name) do
    encoded = :unicode.characters_to_binary(family_name, :utf8, {:utf16, :big})
    string_offset = 6 + 12

    record =
      <<3::16-big, 1::16-big, 0x0409::16-big, 1::16-big, byte_size(encoded)::16-big, 0::16-big>>

    <<0::16-big, 1::16-big, string_offset::16-big, record::binary, encoded::binary>>
  end

  defp layout_table_with_script_and_feature(script_tag, feature_tag)
       when is_binary(script_tag) and byte_size(script_tag) == 4 and is_binary(feature_tag) and
              byte_size(feature_tag) == 4 do
    script_table = <<4::16-big, 0::16-big, 0::16-big, 0xFFFF::16-big, 0::16-big>>
    script_list = <<1::16-big, script_tag::binary-size(4), 8::16-big, script_table::binary>>
    feature_table = <<0::16-big, 0::16-big>>
    feature_list = <<1::16-big, feature_tag::binary-size(4), 8::16-big, feature_table::binary>>
    lookup_list = <<0::16-big>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gsub_ligature_table(coverage_glyph_id, component_glyph_ids, ligature_glyph_id)
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_list(component_glyph_ids) and component_glyph_ids != [] and
              is_integer(ligature_glyph_id) and ligature_glyph_id >= 0 do
    component_count = length(component_glyph_ids) + 1

    ligature_table =
      <<
        ligature_glyph_id::16-big,
        component_count::16-big,
        pack_u16(component_glyph_ids)::binary
      >>

    ligature_set = <<1::16-big, 4::16-big, ligature_table::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    ligature_subtable =
      <<
        1::16-big,
        8::16-big,
        1::16-big,
        14::16-big,
        coverage_table::binary,
        ligature_set::binary
      >>

    lookup_table = <<4::16-big, 0::16-big, 1::16-big, 8::16-big, ligature_subtable::binary>>
    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "liga"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gsub_single_substitution_table(coverage_glyph_id, substitute_glyph_id)
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(substitute_glyph_id) and substitute_glyph_id >= 0 do
    gsub_single_substitution_table_with_feature("liga", coverage_glyph_id, substitute_glyph_id)
  end

  defp gsub_single_substitution_table_with_feature(
         feature_tag,
         coverage_glyph_id,
         substitute_glyph_id
       )
       when is_binary(feature_tag) and byte_size(feature_tag) == 4 and
              is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(substitute_glyph_id) and substitute_glyph_id >= 0 do
    delta_glyph_id = substitute_glyph_id - coverage_glyph_id
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    single_subtable =
      <<1::16-big, 6::16-big, delta_glyph_id::16-signed-big, coverage_table::binary>>

    lookup_table = <<1::16-big, 0::16-big, 1::16-big, 8::16-big, single_subtable::binary>>
    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, feature_tag::binary-size(4), 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gsub_ligature_table_without_liga_lookup_link(
         coverage_glyph_id,
         component_glyph_ids,
         ligature_glyph_id
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_list(component_glyph_ids) and component_glyph_ids != [] and
              is_integer(ligature_glyph_id) and ligature_glyph_id >= 0 do
    component_count = length(component_glyph_ids) + 1

    ligature_table =
      <<
        ligature_glyph_id::16-big,
        component_count::16-big,
        pack_u16(component_glyph_ids)::binary
      >>

    ligature_set = <<1::16-big, 4::16-big, ligature_table::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    ligature_subtable =
      <<
        1::16-big,
        8::16-big,
        1::16-big,
        14::16-big,
        coverage_table::binary,
        ligature_set::binary
      >>

    lookup_table = <<4::16-big, 0::16-big, 1::16-big, 8::16-big, ligature_subtable::binary>>
    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_liga = <<0::16-big, 0::16-big>>
    feature_dlig = <<0::16-big, 1::16-big, 0::16-big>>

    feature_list =
      <<2::16-big, "liga"::binary, 14::16-big, "dlig"::binary, 18::16-big, feature_liga::binary,
        feature_dlig::binary>>

    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 2::16-big, 0::16-big, 1::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gsub_ligature_table_default_langsys_without_lookup(
         coverage_glyph_id,
         component_glyph_ids,
         ligature_glyph_id
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_list(component_glyph_ids) and component_glyph_ids != [] and
              is_integer(ligature_glyph_id) and ligature_glyph_id >= 0 do
    component_count = length(component_glyph_ids) + 1

    ligature_table =
      <<
        ligature_glyph_id::16-big,
        component_count::16-big,
        pack_u16(component_glyph_ids)::binary
      >>

    ligature_set = <<1::16-big, 4::16-big, ligature_table::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    ligature_subtable =
      <<
        1::16-big,
        8::16-big,
        1::16-big,
        14::16-big,
        coverage_table::binary,
        ligature_set::binary
      >>

    lookup_table = <<4::16-big, 0::16-big, 1::16-big, 8::16-big, ligature_subtable::binary>>
    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_liga_default = <<0::16-big, 0::16-big>>
    feature_liga_named = <<0::16-big, 1::16-big, 0::16-big>>

    feature_list =
      <<2::16-big, "liga"::binary, 14::16-big, "liga"::binary, 18::16-big,
        feature_liga_default::binary, feature_liga_named::binary>>

    default_lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    named_lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 1::16-big>>

    script_table =
      <<10::16-big, 1::16-big, "TRK "::binary, 18::16-big, default_lang_sys_table::binary,
        named_lang_sys_table::binary>>

    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table(coverage_glyph_id, second_glyph_id, x_advance_adjustment)
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<1::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_value2(coverage_glyph_id, second_glyph_id, x_advance_adjustment)
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<1::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0::16-big,
        0x0004::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_oversized(
         coverage_glyph_id,
         second_glyph_id,
         x_advance_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<10_001::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_truncated(
         coverage_glyph_id,
         second_glyph_id,
         x_advance_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<2::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_coverage_mismatch(
         coverage_glyph_id_1,
         coverage_glyph_id_2,
         second_glyph_id,
         x_advance_adjustment
       )
       when is_integer(coverage_glyph_id_1) and coverage_glyph_id_1 >= 0 and
              is_integer(coverage_glyph_id_2) and coverage_glyph_id_2 >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<1::16-big, pair_value_record::binary>>

    coverage_table =
      <<1::16-big, 2::16-big, coverage_glyph_id_1::16-big, coverage_glyph_id_2::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        20::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table(
         coverage_glyph_id,
         right_glyph_class_1,
         right_glyph_class_2,
         class_1_1_adjustment,
         class_1_2_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(right_glyph_class_1) and right_glyph_class_1 >= 0 and
              is_integer(right_glyph_class_2) and right_glyph_class_2 >= 0 and
              is_integer(class_1_1_adjustment) and is_integer(class_1_2_adjustment) do
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>
    class_def_1 = <<1::16-big, coverage_glyph_id::16-big, 1::16-big, 1::16-big>>

    class_def_2 =
      <<
        1::16-big,
        right_glyph_class_1::16-big,
        2::16-big,
        1::16-big,
        2::16-big
      >>

    class_1_record_0 = <<0::16-signed-big, 0::16-signed-big, 0::16-signed-big>>

    class_1_record_1 =
      <<0::16-signed-big, class_1_1_adjustment::16-signed-big,
        class_1_2_adjustment::16-signed-big>>

    pair_adjustment_subtable =
      <<
        2::16-big,
        28::16-big,
        0x0004::16-big,
        0::16-big,
        34::16-big,
        42::16-big,
        2::16-big,
        3::16-big,
        class_1_record_0::binary,
        class_1_record_1::binary,
        coverage_table::binary,
        class_def_1::binary,
        class_def_2::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table_oversized(
         coverage_glyph_id,
         right_glyph_class_1,
         right_glyph_class_2,
         class_1_1_adjustment,
         class_1_2_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(right_glyph_class_1) and right_glyph_class_1 >= 0 and
              is_integer(right_glyph_class_2) and right_glyph_class_2 >= 0 and
              is_integer(class_1_1_adjustment) and is_integer(class_1_2_adjustment) do
    class_1_count = 128
    class_2_count = 128
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>
    class_def_1 = <<1::16-big, coverage_glyph_id::16-big, 1::16-big, 1::16-big>>

    class_def_2 =
      <<
        1::16-big,
        right_glyph_class_1::16-big,
        2::16-big,
        1::16-big,
        2::16-big
      >>

    class_1_record_0 = :binary.copy(<<0::16-signed-big>>, class_2_count)

    class_1_record_1 =
      <<
        0::16-signed-big,
        class_1_1_adjustment::16-signed-big,
        class_1_2_adjustment::16-signed-big,
        0::size((class_2_count - 3) * 16)
      >>

    trailing_zero_rows = :binary.copy(class_1_record_0, class_1_count - 2)
    class_records = [class_1_record_0, class_1_record_1, trailing_zero_rows]
    class_records_size = class_1_count * class_2_count * 2
    coverage_offset = 16 + class_records_size
    class_def_1_offset = coverage_offset + byte_size(coverage_table)
    class_def_2_offset = class_def_1_offset + byte_size(class_def_1)

    pair_adjustment_subtable =
      [
        <<
          2::16-big,
          coverage_offset::16-big,
          0x0004::16-big,
          0::16-big,
          class_def_1_offset::16-big,
          class_def_2_offset::16-big,
          class_1_count::16-big,
          class_2_count::16-big
        >>,
        class_records,
        coverage_table,
        class_def_1,
        class_def_2
      ]
      |> IO.iodata_to_binary()

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table_expansion_oversized(
         coverage_glyph_id_1,
         coverage_glyph_id_2,
         class_1_1_adjustment
       )
       when is_integer(coverage_glyph_id_1) and coverage_glyph_id_1 >= 0 and
              is_integer(coverage_glyph_id_2) and coverage_glyph_id_2 >= 0 and
              is_integer(class_1_1_adjustment) do
    class_1_count = 2
    class_2_count = 2

    coverage_table =
      <<1::16-big, 2::16-big, coverage_glyph_id_1::16-big, coverage_glyph_id_2::16-big>>

    class_def_1 =
      <<
        2::16-big,
        2::16-big,
        coverage_glyph_id_1::16-big,
        coverage_glyph_id_1::16-big,
        1::16-big,
        coverage_glyph_id_2::16-big,
        coverage_glyph_id_2::16-big,
        1::16-big
      >>

    class_def_2 =
      <<
        2::16-big,
        1::16-big,
        2::16-big,
        10_001::16-big,
        1::16-big
      >>

    class_records =
      <<
        0::16-signed-big,
        0::16-signed-big,
        0::16-signed-big,
        class_1_1_adjustment::16-signed-big
      >>

    class_records_size = class_1_count * class_2_count * 2
    coverage_offset = 16 + class_records_size
    class_def_1_offset = coverage_offset + byte_size(coverage_table)
    class_def_2_offset = class_def_1_offset + byte_size(class_def_1)

    pair_adjustment_subtable =
      [
        <<
          2::16-big,
          coverage_offset::16-big,
          0x0004::16-big,
          0::16-big,
          class_def_1_offset::16-big,
          class_def_2_offset::16-big,
          class_1_count::16-big,
          class_2_count::16-big
        >>,
        class_records,
        coverage_table,
        class_def_1,
        class_def_2
      ]
      |> IO.iodata_to_binary()

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table_classdef_oversized(
         coverage_glyph_id,
         class_1_1_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(class_1_1_adjustment) do
    class_1_count = 2
    class_2_count = 2
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>
    class_def_1 = <<1::16-big, coverage_glyph_id::16-big, 1::16-big, 1::16-big>>

    class_def_2 =
      <<
        2::16-big,
        1::16-big,
        2::16-big,
        10_003::16-big,
        1::16-big
      >>

    class_records =
      <<
        0::16-signed-big,
        0::16-signed-big,
        0::16-signed-big,
        class_1_1_adjustment::16-signed-big
      >>

    class_records_size = class_1_count * class_2_count * 2
    coverage_offset = 16 + class_records_size
    class_def_1_offset = coverage_offset + byte_size(coverage_table)
    class_def_2_offset = class_def_1_offset + byte_size(class_def_1)

    pair_adjustment_subtable =
      [
        <<
          2::16-big,
          coverage_offset::16-big,
          0x0004::16-big,
          0::16-big,
          class_def_1_offset::16-big,
          class_def_2_offset::16-big,
          class_1_count::16-big,
          class_2_count::16-big
        >>,
        class_records,
        coverage_table,
        class_def_1,
        class_def_2
      ]
      |> IO.iodata_to_binary()

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table_invalid_class_counts(
         coverage_glyph_id,
         right_glyph_id
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(right_glyph_id) and right_glyph_id >= 0 do
    class_1_count = 1
    class_2_count = 0
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>
    class_def_1 = <<1::16-big, coverage_glyph_id::16-big, 1::16-big, 0::16-big>>
    class_def_2 = <<1::16-big, right_glyph_id::16-big, 1::16-big, 0::16-big>>

    class_records_size = class_1_count * class_2_count * 2
    coverage_offset = 16 + class_records_size
    class_def_1_offset = coverage_offset + byte_size(coverage_table)
    class_def_2_offset = class_def_1_offset + byte_size(class_def_1)

    pair_adjustment_subtable =
      [
        <<
          2::16-big,
          coverage_offset::16-big,
          0x0004::16-big,
          0::16-big,
          class_def_1_offset::16-big,
          class_def_2_offset::16-big,
          class_1_count::16-big,
          class_2_count::16-big
        >>,
        coverage_table,
        class_def_1,
        class_def_2
      ]
      |> IO.iodata_to_binary()

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table_truncated_records(coverage_glyph_id)
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 do
    class_1_count = 2
    class_2_count = 3
    coverage_offset = 16 + class_1_count * class_2_count * 2

    pair_adjustment_subtable =
      <<
        2::16-big,
        coverage_offset::16-big,
        0x0004::16-big,
        0::16-big,
        0::16-big,
        0::16-big,
        class_1_count::16-big,
        class_2_count::16-big,
        0::16-signed-big,
        0::16-signed-big,
        0::16-signed-big,
        coverage_glyph_id::16-big
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_class_table_invalid_class_def_offsets(coverage_glyph_id)
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 do
    class_1_count = 2
    class_2_count = 3

    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    class_1_record_0 = <<0::16-signed-big, 0::16-signed-big, 0::16-signed-big>>
    class_1_record_1 = <<0::16-signed-big, -80::16-signed-big, -40::16-signed-big>>
    class_records = <<class_1_record_0::binary, class_1_record_1::binary>>

    class_records_size = class_1_count * class_2_count * 2
    coverage_offset = 16 + class_records_size

    pair_adjustment_subtable =
      [
        <<
          2::16-big,
          coverage_offset::16-big,
          0x0004::16-big,
          0::16-big,
          0x7FFF::16-big,
          0x7FFF::16-big,
          class_1_count::16-big,
          class_2_count::16-big
        >>,
        class_records,
        coverage_table
      ]
      |> IO.iodata_to_binary()

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_table = <<0::16-big, 1::16-big, 0::16-big>>
    feature_list = <<1::16-big, "kern"::binary, 8::16-big, feature_table::binary>>
    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_without_kern_lookup_link(
         coverage_glyph_id,
         second_glyph_id,
         x_advance_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<1::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_kern = <<0::16-big, 0::16-big>>
    feature_mark = <<0::16-big, 1::16-big, 0::16-big>>

    feature_list =
      <<2::16-big, "kern"::binary, 14::16-big, "mark"::binary, 18::16-big, feature_kern::binary,
        feature_mark::binary>>

    lang_sys_table = <<0::16-big, 0xFFFF::16-big, 2::16-big, 0::16-big, 1::16-big>>
    script_table = <<4::16-big, 0::16-big, lang_sys_table::binary>>
    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_default_langsys_without_lookup(
         coverage_glyph_id,
         second_glyph_id,
         x_advance_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<1::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_kern_default = <<0::16-big, 0::16-big>>
    feature_kern_named = <<0::16-big, 1::16-big, 0::16-big>>

    feature_list =
      <<2::16-big, "kern"::binary, 14::16-big, "kern"::binary, 18::16-big,
        feature_kern_default::binary, feature_kern_named::binary>>

    default_lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    named_lang_sys_table = <<0::16-big, 0xFFFF::16-big, 1::16-big, 1::16-big>>

    script_table =
      <<10::16-big, 1::16-big, "TRK "::binary, 18::16-big, default_lang_sys_table::binary,
        named_lang_sys_table::binary>>

    script_list = <<1::16-big, "latn"::binary, 8::16-big, script_table::binary>>
    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gsub_ligature_table_liga_lookup_only_on_arab_script(
         coverage_glyph_id,
         component_glyph_ids,
         ligature_glyph_id
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_list(component_glyph_ids) and component_glyph_ids != [] and
              is_integer(ligature_glyph_id) and ligature_glyph_id >= 0 do
    component_count = length(component_glyph_ids) + 1

    ligature_table =
      <<
        ligature_glyph_id::16-big,
        component_count::16-big,
        pack_u16(component_glyph_ids)::binary
      >>

    ligature_set = <<1::16-big, 4::16-big, ligature_table::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    ligature_subtable =
      <<
        1::16-big,
        8::16-big,
        1::16-big,
        14::16-big,
        coverage_table::binary,
        ligature_set::binary
      >>

    lookup_table = <<4::16-big, 0::16-big, 1::16-big, 8::16-big, ligature_subtable::binary>>
    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_liga_no_lookup = <<0::16-big, 0::16-big>>
    feature_liga_with_lookup = <<0::16-big, 1::16-big, 0::16-big>>

    feature_list =
      <<2::16-big, "liga"::binary, 14::16-big, "liga"::binary, 18::16-big,
        feature_liga_no_lookup::binary, feature_liga_with_lookup::binary>>

    lang_sys_latn = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    lang_sys_arab = <<0::16-big, 0xFFFF::16-big, 1::16-big, 1::16-big>>
    script_latn = <<4::16-big, 0::16-big, lang_sys_latn::binary>>
    script_arab = <<4::16-big, 0::16-big, lang_sys_arab::binary>>

    script_list =
      <<2::16-big, "latn"::binary, 14::16-big, "arab"::binary, 26::16-big, script_latn::binary,
        script_arab::binary>>

    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp gpos_pair_adjustment_table_kern_lookup_only_on_arab_script(
         coverage_glyph_id,
         second_glyph_id,
         x_advance_adjustment
       )
       when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
              is_integer(second_glyph_id) and second_glyph_id >= 0 and
              is_integer(x_advance_adjustment) do
    pair_value_record = <<second_glyph_id::16-big, x_advance_adjustment::16-signed-big>>
    pair_set = <<1::16-big, pair_value_record::binary>>
    coverage_table = <<1::16-big, 1::16-big, coverage_glyph_id::16-big>>

    pair_adjustment_subtable =
      <<
        1::16-big,
        12::16-big,
        0x0004::16-big,
        0::16-big,
        1::16-big,
        18::16-big,
        coverage_table::binary,
        pair_set::binary
      >>

    lookup_table =
      <<2::16-big, 0::16-big, 1::16-big, 8::16-big, pair_adjustment_subtable::binary>>

    lookup_list = <<1::16-big, 4::16-big, lookup_table::binary>>
    feature_kern_no_lookup = <<0::16-big, 0::16-big>>
    feature_kern_with_lookup = <<0::16-big, 1::16-big, 0::16-big>>

    feature_list =
      <<2::16-big, "kern"::binary, 14::16-big, "kern"::binary, 18::16-big,
        feature_kern_no_lookup::binary, feature_kern_with_lookup::binary>>

    lang_sys_latn = <<0::16-big, 0xFFFF::16-big, 1::16-big, 0::16-big>>
    lang_sys_arab = <<0::16-big, 0xFFFF::16-big, 1::16-big, 1::16-big>>
    script_latn = <<4::16-big, 0::16-big, lang_sys_latn::binary>>
    script_arab = <<4::16-big, 0::16-big, lang_sys_arab::binary>>

    script_list =
      <<2::16-big, "latn"::binary, 14::16-big, "arab"::binary, 26::16-big, script_latn::binary,
        script_arab::binary>>

    script_list_offset = 10
    feature_list_offset = script_list_offset + byte_size(script_list)
    lookup_list_offset = feature_list_offset + byte_size(feature_list)

    <<
      1::16-big,
      0::16-big,
      script_list_offset::16-big,
      feature_list_offset::16-big,
      lookup_list_offset::16-big,
      script_list::binary,
      feature_list::binary,
      lookup_list::binary
    >>
  end

  defp pack_u16(values) do
    values
    |> Enum.map(fn value -> <<value::16-big>> end)
    |> IO.iodata_to_binary()
  end

  defp pack_s16(values) do
    values
    |> Enum.map(fn value -> <<value::16-signed-big>> end)
    |> IO.iodata_to_binary()
  end

  defp build_ttf(tables) do
    build_sfnt(<<0x0001_0000::32-big>>, tables)
  end

  defp build_otf(tables) do
    build_sfnt(<<"OTTO">>, tables)
  end

  defp build_sfnt(sfnt_version, tables) do
    num_tables = length(tables)
    header = <<sfnt_version::binary-size(4), num_tables::16-big, 0::16-big, 0::16-big, 0::16-big>>
    table_dir_size = num_tables * 16
    base_offset = byte_size(header) + table_dir_size

    {records, binaries, _next_offset} =
      Enum.reduce(tables, {[], [], base_offset}, fn {tag, data}, {rec_acc, bin_acc, offset} ->
        length = byte_size(data)
        record = <<tag::binary-size(4), 0::32-big, offset::32-big, length::32-big>>
        {rec_acc ++ [record], bin_acc ++ [data], offset + length}
      end)

    IO.iodata_to_binary([header, records, binaries])
  end
end
