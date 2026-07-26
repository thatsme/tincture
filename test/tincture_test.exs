defmodule TinctureTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias Tincture.Typography.RichText

  test "new/0 builds a pdf state struct" do
    pdf = Tincture.new()

    assert %Tincture.PDF{} = pdf
    assert pdf.page_size == :a4
    assert pdf.operations == []
  end

  test "page_size/2 updates a named page size" do
    pdf =
      Tincture.new()
      |> Tincture.page_size(:letter)

    assert pdf.page_size == :letter
  end

  test "add_page/1 creates a new current page with isolated operations" do
    pdf =
      Tincture.new()
      |> Tincture.text_at(10, 700, "page one")
      |> Tincture.add_page()
      |> Tincture.text_at(10, 700, "page two")

    assert pdf.current_page == 2
    assert pdf.operations == [{:text_at, 10, 700, "page two", {"Helvetica", 12}}]
  end

  test "set_page/2 switches current page and preserves per-page operations" do
    pdf =
      Tincture.new()
      |> Tincture.text_at(10, 700, "one")
      |> Tincture.add_page()
      |> Tincture.text_at(10, 700, "two")
      |> Tincture.set_page(1)
      |> Tincture.text_at(20, 680, "one-more")

    assert pdf.current_page == 1

    assert [
             {:text_at, 10, 700, "one", {"Helvetica", 12}},
             {:text_at, 20, 680, "one-more", {"Helvetica", 12}}
           ] = pdf.operations

    pdf_page_two = Tincture.set_page(pdf, 2)
    assert pdf_page_two.operations == [{:text_at, 10, 700, "two", {"Helvetica", 12}}]
  end

  test "set_page/2 rejects unknown page numbers" do
    assert_raise ArgumentError, "unknown page: 2", fn ->
      Tincture.new()
      |> Tincture.set_page(2)
    end
  end

  test "set_font/3 and text_at/4 append text operations with active font" do
    pdf =
      Tincture.new()
      |> Tincture.set_font("Times-Roman", 16)
      |> Tincture.text_at(50, 700, "Hello")

    assert pdf.current_font == {"Times-Roman", 16}
    assert pdf.operations == [{:text_at, 50, 700, "Hello", {"Times-Roman", 16}}]
  end

  test "register_ttf_font/3 embeds a TrueType font and allows set_font/3" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoTTF", path)
      |> Tincture.set_font("DemoTTF", 14)
      |> Tincture.text_at(50, 700, "Hello TTF")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /TrueType"
    assert pdf_binary =~ "/BaseFont /DemoTTF"
    assert pdf_binary =~ "/FontFile2 "
    assert pdf_binary =~ "/F1 "
    assert pdf_binary =~ "/F1 14 Tf"

    File.rm(path)
  end

  test "register_ttf_font/4 supports opt-in baseline subset mode" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoSubset", path, subset: :ascii_basic)
      |> Tincture.set_font("DemoSubset", 14)
      |> Tincture.text_at(50, 700, "Subset text")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /TrueType"
    assert pdf_binary =~ "/FirstChar 32 /LastChar 126"
    assert pdf_binary =~ "+DemoSubset"

    File.rm(path)
  end

  test "register_ttf_font/4 ascii_basic subset uses Type0/CID objects for non-ASCII text runs" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoSubsetUnicode", path, subset: :ascii_basic)
      |> Tincture.set_font("DemoSubsetUnicode", 14)
      |> Tincture.text_at(50, 700, "Snowman ☃")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Type0"
    assert pdf_binary =~ "/Encoding /Identity-H"
    assert pdf_binary =~ "/Subtype /CIDFontType2"
    assert pdf_binary =~ "+DemoSubsetUnicode"
    refute pdf_binary =~ "/FirstChar "

    File.rm(path)
  end

  test "register_ttf_font/4 supports used-text subset range mode" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUsedSubset", path, subset: :used_text)
      |> Tincture.set_font("DemoUsedSubset", 14)
      |> Tincture.text_at(50, 700, "AZ")
      |> Tincture.export()

    assert pdf_binary =~ "/FirstChar 65 /LastChar 90"
    assert pdf_binary =~ "+DemoUsedSubset"

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset includes space/punctuation ranges" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUsedSubsetRange", path, subset: :used_text)
      |> Tincture.set_font("DemoUsedSubsetRange", 14)
      |> Tincture.text_at(50, 700, "A Z!")
      |> Tincture.export()

    assert pdf_binary =~ "/FirstChar 32 /LastChar 90"

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset uses Type0/CID objects for non-ASCII text runs" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUsedSubsetUnicode", path, subset: :used_text)
      |> Tincture.set_font("DemoUsedSubsetUnicode", 14)
      |> Tincture.text_at(50, 700, "Snowman ☃")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Type0"
    assert pdf_binary =~ "/Encoding /Identity-H"
    assert pdf_binary =~ "/Subtype /CIDFontType2"
    assert pdf_binary =~ "/CIDSet "
    assert pdf_binary =~ "+DemoUsedSubsetUnicode"
    refute pdf_binary =~ "/FirstChar "

    File.rm(path)
  end

  test "register_ttf_font/4 uses parsed TTF widths for used-text subset ranges" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoMappedWidths", path, subset: :used_text)
      |> Tincture.set_font("DemoMappedWidths", 14)
      |> Tincture.text_at(50, 700, "AB")
      |> Tincture.export()

    assert pdf_binary =~ "/FirstChar 65 /LastChar 66"
    assert pdf_binary =~ "/Widths [500 700]"

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset emits smaller FontFile2 stream when loca/glyf subset is possible" do
    path = write_test_ttf_with_cmap_loca_glyf!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoSubsetProgram", path, subset: :used_text)
      |> Tincture.set_font("DemoSubsetProgram", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_length = font_file_length1_from_pdf!(pdf_binary)
    assert subset_length < original_length

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset emits 4-byte aligned sfnt table offsets" do
    path = write_test_ttf_with_cmap_loca_glyf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoSubsetAligned", path, subset: :used_text)
      |> Tincture.set_font("DemoSubsetAligned", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    offsets = sfnt_table_offsets!(subset_font_data)
    assert offsets != []
    assert Enum.all?(offsets, &(rem(&1, 4) == 0))

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset emits valid sfnt checkSumAdjustment" do
    path = write_test_ttf_with_cmap_loca_glyf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoSubsetChecksum", path, subset: :used_text)
      |> Tincture.set_font("DemoSubsetChecksum", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)

    assert sfnt_checksum(subset_font_data) == 0xB1B0AFBA
    assert sfnt_head_check_sum_adjustment!(subset_font_data) > 0

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset keeps component glyph programs for composite glyphs" do
    path = write_test_ttf_with_composite_loca_glyf!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoCompositeSubset", path, subset: :used_text)
      |> Tincture.set_font("DemoCompositeSubset", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    assert byte_size(subset_font_data) < original_length

    loca_offsets = ttf_loca_offsets_from_sfnt!(subset_font_data)
    assert Enum.at(loca_offsets, 1) < Enum.at(loca_offsets, 2)
    assert Enum.at(loca_offsets, 2) < Enum.at(loca_offsets, 3)
    assert Enum.at(loca_offsets, 3) == Enum.at(loca_offsets, 4)

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset falls back to full FontFile2 stream when composite glyph references an invalid component glyph ID" do
    path = write_test_ttf_with_composite_invalid_component_loca_glyf!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoCompositeSubsetInvalidComponent", path,
        subset: :used_text
      )
      |> Tincture.set_font("DemoCompositeSubsetInvalidComponent", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert font_file_length1_from_pdf!(pdf_binary) == original_length

    File.rm(path)
  end

  test "register_ttf_font/4 logs when used-text subset falls back due to invalid composite component glyph ID references" do
    path = write_test_ttf_with_composite_invalid_component_loca_glyf!()
    original_length = byte_size(File.read!(path))

    log =
      capture_log(fn ->
        pdf_binary =
          Tincture.new()
          |> Tincture.register_ttf_font("DemoCompositeSubsetInvalidComponent", path,
            subset: :used_text
          )
          |> Tincture.set_font("DemoCompositeSubsetInvalidComponent", 14)
          |> Tincture.text_at(50, 700, "A")
          |> Tincture.export()

        assert font_file_length1_from_pdf!(pdf_binary) == original_length
      end)

    assert log =~ "TTF subset fallback to full font"
    assert log =~ "invalid composite component reference"

    File.rm(path)
  end

  test "register_ttf_font/4 used-text subset falls back to full FontFile2 stream when composite glyph has malformed component records" do
    path = write_test_ttf_with_composite_malformed_component_loca_glyf!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoCompositeSubsetMalformedComponent", path,
        subset: :used_text
      )
      |> Tincture.set_font("DemoCompositeSubsetMalformedComponent", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert font_file_length1_from_pdf!(pdf_binary) == original_length

    File.rm(path)
  end

  test "register_ttf_font/4 logs when used-text subset falls back due to malformed composite component records" do
    path = write_test_ttf_with_composite_malformed_component_loca_glyf!()
    original_length = byte_size(File.read!(path))

    log =
      capture_log(fn ->
        pdf_binary =
          Tincture.new()
          |> Tincture.register_ttf_font("DemoCompositeSubsetMalformedComponent", path,
            subset: :used_text
          )
          |> Tincture.set_font("DemoCompositeSubsetMalformedComponent", 14)
          |> Tincture.text_at(50, 700, "A")
          |> Tincture.export()

        assert font_file_length1_from_pdf!(pdf_binary) == original_length
      end)

    assert log =~ "TTF subset fallback to full font"
    assert log =~ "malformed composite component records"

    File.rm(path)
  end

  test "register_ttf_font/3 keeps full FontFile2 stream length when subset mode is :none" do
    path = write_test_ttf_with_cmap_loca_glyf!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoFullProgram", path, subset: :none)
      |> Tincture.set_font("DemoFullProgram", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert font_file_length1_from_pdf!(pdf_binary) == original_length

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor FontBBox from parsed glyf bounds when available" do
    path = write_test_ttf_with_loca_glyf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoGlyphBBox", path)
      |> Tincture.set_font("DemoGlyphBBox", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontBBox [0 -20 700 750]"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor FontBBox from head table when glyf bounds are absent" do
    path = write_test_ttf_with_head_bbox!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoHeadBBox", path)
      |> Tincture.set_font("DemoHeadBBox", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontBBox [-50 -200 1100 900]"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor ascent/descent/cap height from parsed metrics" do
    path = write_test_ttf_with_os2!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoVerticalMetrics", path)
      |> Tincture.set_font("DemoVerticalMetrics", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Ascent 780"
    assert pdf_binary =~ "/Descent -220"
    assert pdf_binary =~ "/XHeight 510"
    assert pdf_binary =~ "/CapHeight 730"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor Leading from parsed line-gap metrics" do
    path = write_test_ttf_with_line_gaps!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoLeadingMetrics", path)
      |> Tincture.set_font("DemoLeadingMetrics", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Leading 140"

    File.rm(path)
  end

  test "register_ttf_font/3 falls back to OS/2 win ascent/descent when typo and hhea metrics are zero" do
    path = write_test_ttf_with_os2_win_fallback!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoWinFallbackMetrics", path)
      |> Tincture.set_font("DemoWinFallbackMetrics", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Ascent 840"
    assert pdf_binary =~ "/Descent -260"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor StemV from parsed OS/2 weight class when present" do
    path = write_test_ttf_with_os2_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoWeightStemV", path)
      |> Tincture.set_font("DemoWeightStemV", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/StemV 180"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor StemH from parsed OS/2 weight class fallback" do
    path = write_test_ttf_with_os2_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoWeightStemH", path)
      |> Tincture.set_font("DemoWeightStemH", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/StemH 180"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor FontWeight from parsed OS/2 weight class" do
    path = write_test_ttf_with_os2_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoFontWeight", path)
      |> Tincture.set_font("DemoFontWeight", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontWeight 900"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor StemV from parsed CFF StdVW when OS/2 weight is unavailable" do
    path = write_test_otf_with_cff_stem_v!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFStemV", path)
      |> Tincture.set_font("DemoCFFStemV", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/StemV 140"

    File.rm(path)
  end

  test "register_otf_font/3 falls back descriptor StemV to parsed CFF StdHW when StdVW and OS/2 weight are unavailable" do
    path = write_test_otf_with_cff_stem_h!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFStemHFallback", path)
      |> Tincture.set_font("DemoCFFStemHFallback", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/StemV 120"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor StemH from parsed CFF StdHW when present" do
    path = write_test_otf_with_cff_stem_h!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFStemH", path)
      |> Tincture.set_font("DemoCFFStemH", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/StemH 120"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor force-bold flag from parsed CFF Private ForceBold metadata" do
    path = write_test_otf_with_cff_force_bold!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFForceBold", path)
      |> Tincture.set_font("DemoCFFForceBold", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Flags 262176"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontWeight from parsed CFF weight metadata when OS/2 weight is unavailable" do
    path = write_test_otf_with_cff_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFFontWeight", path)
      |> Tincture.set_font("DemoCFFFontWeight", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontWeight 700"
    assert pdf_binary =~ "/StemV 140"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontWeight from parsed CFF standard SID weight metadata when OS/2 weight is unavailable" do
    path = write_test_otf_with_cff_standard_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFStandardSIDFontWeight", path)
      |> Tincture.set_font("DemoCFFStandardSIDFontWeight", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontWeight 700"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontWeight from numeric parsed CFF weight metadata when OS/2 weight is unavailable" do
    path = write_test_otf_with_cff_numeric_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFNumericFontWeight", path)
      |> Tincture.set_font("DemoCFFNumericFontWeight", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontWeight 650"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontWeight from hyphenated parsed CFF weight metadata when OS/2 weight is unavailable" do
    path = write_test_otf_with_cff_hyphen_weight!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFHyphenFontWeight", path)
      |> Tincture.set_font("DemoCFFHyphenFontWeight", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontWeight 600"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor FontStretch from parsed OS/2 width class" do
    path = write_test_ttf_with_os2!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoFontStretch", path)
      |> Tincture.set_font("DemoFontStretch", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontStretch /Condensed"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor FSType from parsed OS/2 metadata" do
    path = write_test_ttf_with_os2_fs_type!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoFSType", path)
      |> Tincture.set_font("DemoFSType", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FSType 2"

    File.rm(path)
  end

  test "register_ttf_font/4 can enforce OS/2 embedding permissions for restricted-license fonts" do
    path = write_test_ttf_with_os2_fs_type!()

    assert_raise ArgumentError, ~r/font embedding restricted by OS\/2 fsType \(2\)/, fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("DemoRestrictedEmbedding", path,
        enforce_embedding_permissions: true
      )
    end

    File.rm(path)
  end

  test "register_ttf_font/4 can enforce OS/2 no-subsetting permissions for subset modes" do
    path = write_test_ttf_with_os2_no_subsetting!()

    assert_raise ArgumentError, ~r/font disallows subsetting via OS\/2 fsType \(256\)/, fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("DemoNoSubsetting", path,
        subset: :used_text,
        enforce_embedding_permissions: true
      )
    end

    File.rm(path)
  end

  test "register_ttf_font/4 can enforce OS/2 bitmap-only embedding permissions" do
    path = write_test_ttf_with_os2_bitmap_only!()

    assert_raise ArgumentError,
                 ~r/font allows bitmap embedding only via OS\/2 fsType \(512\)/,
                 fn ->
                   Tincture.new()
                   |> Tincture.register_ttf_font("DemoBitmapOnlyEmbedding", path,
                     enforce_embedding_permissions: true
                   )
                 end

    File.rm(path)
  end

  test "register_ttf_font/4 enforcement reports combined OS/2 bitmap-only and no-subsetting flags" do
    path = write_test_ttf_with_os2_bitmap_and_no_subsetting!()

    assert_raise ArgumentError,
                 ~r/font .* OS\/2 fsType \(768\).*bitmap embedding only.*disallows subsetting/s,
                 fn ->
                   Tincture.new()
                   |> Tincture.register_ttf_font("DemoCombinedFlagsEmbedding", path,
                     subset: :used_text,
                     enforce_embedding_permissions: true
                   )
                 end

    File.rm(path)
  end

  test "register_ttf_font/3 warns on restricted OS/2 embedding permissions when enforcement is disabled" do
    path = write_test_ttf_with_os2_fs_type!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_ttf_font("DemoRestrictedWarn", path)
      end)

    assert log =~ "OS/2 fsType (2)"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_ttf_font/4 warns on OS/2 no-subsetting permissions when enforcement is disabled" do
    path = write_test_ttf_with_os2_no_subsetting!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_ttf_font("DemoNoSubsetWarn", path, subset: :used_text)
      end)

    assert log =~ "OS/2 fsType (256)"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_ttf_font/4 warning reports combined OS/2 bitmap-only and no-subsetting flags" do
    path = write_test_ttf_with_os2_bitmap_and_no_subsetting!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_ttf_font("DemoCombinedFlagsWarn", path, subset: :used_text)
      end)

    assert log =~ "OS/2 fsType (768)"
    assert log =~ "bitmap embedding only"
    assert log =~ "disallows subsetting"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_otf_font/4 can enforce OS/2 embedding permissions for restricted-license fonts" do
    path = write_test_otf_with_os2_fs_type!()

    assert_raise ArgumentError, ~r/font embedding restricted by OS\/2 fsType \(2\)/, fn ->
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFRestrictedEmbedding", path,
        enforce_embedding_permissions: true
      )
    end

    File.rm(path)
  end

  test "register_otf_font/4 can enforce OS/2 no-subsetting permissions for subset modes" do
    path = write_test_otf_with_os2_no_subsetting!()

    assert_raise ArgumentError, ~r/font disallows subsetting via OS\/2 fsType \(256\)/, fn ->
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFNoSubsetting", path,
        subset: :used_text,
        enforce_embedding_permissions: true
      )
    end

    File.rm(path)
  end

  test "register_otf_font/4 can enforce OS/2 bitmap-only embedding permissions" do
    path = write_test_otf_with_os2_bitmap_only!()

    assert_raise ArgumentError,
                 ~r/font allows bitmap embedding only via OS\/2 fsType \(512\)/,
                 fn ->
                   Tincture.new()
                   |> Tincture.register_otf_font("DemoOTFBitmapOnlyEmbedding", path,
                     enforce_embedding_permissions: true
                   )
                 end

    File.rm(path)
  end

  test "register_otf_font/4 enforcement reports combined OS/2 bitmap-only and no-subsetting flags" do
    path = write_test_otf_with_os2_bitmap_and_no_subsetting!()

    assert_raise ArgumentError,
                 ~r/font .* OS\/2 fsType \(768\).*bitmap embedding only.*disallows subsetting/s,
                 fn ->
                   Tincture.new()
                   |> Tincture.register_otf_font("DemoOTFCombinedFlagsEmbedding", path,
                     subset: :used_text,
                     enforce_embedding_permissions: true
                   )
                 end

    File.rm(path)
  end

  test "register_otf_font/3 warns on restricted OS/2 embedding permissions when enforcement is disabled" do
    path = write_test_otf_with_os2_fs_type!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_otf_font("DemoOTFRestrictedWarn", path)
      end)

    assert log =~ "OS/2 fsType (2)"
    assert log =~ "OTF file"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_otf_font/4 warns on OS/2 no-subsetting permissions when enforcement is disabled" do
    path = write_test_otf_with_os2_no_subsetting!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_otf_font("DemoOTFNoSubsetWarn", path, subset: :used_text)
      end)

    assert log =~ "OS/2 fsType (256)"
    assert log =~ "OTF file"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_otf_font/3 warns on OS/2 bitmap-only embedding permissions when enforcement is disabled" do
    path = write_test_otf_with_os2_bitmap_only!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_otf_font("DemoOTFBitmapOnlyWarn", path)
      end)

    assert log =~ "OS/2 fsType (512)"
    assert log =~ "OTF file"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_otf_font/4 warning reports combined OS/2 bitmap-only and no-subsetting flags" do
    path = write_test_otf_with_os2_bitmap_and_no_subsetting!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_otf_font("DemoOTFCombinedFlagsWarn", path, subset: :used_text)
      end)

    assert log =~ "OS/2 fsType (768)"
    assert log =~ "bitmap embedding only"
    assert log =~ "disallows subsetting"
    assert log =~ "enforce_embedding_permissions: true"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor AvgWidth from parsed OS/2 metadata" do
    path = write_test_ttf_with_os2_avg_width!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoAvgWidth", path)
      |> Tincture.set_font("DemoAvgWidth", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/AvgWidth 540"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor MaxWidth from parsed hmtx metrics" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoMaxWidth", path)
      |> Tincture.set_font("DemoMaxWidth", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/MaxWidth 700"

    File.rm(path)
  end

  test "register_ttf_font/3 prefers descriptor MaxWidth from parsed hhea advanceWidthMax" do
    path = write_test_ttf_with_hhea_advance_width_max!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoHheaMaxWidth", path)
      |> Tincture.set_font("DemoHheaMaxWidth", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/MaxWidth 900"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor MissingWidth from glyph 0 advance width" do
    path = write_test_ttf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoMissingWidth", path)
      |> Tincture.set_font("DemoMissingWidth", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/MissingWidth 500"

    File.rm(path)
  end

  test "register_ttf_font/3 prefers descriptor MissingWidth from OS/2 default char glyph" do
    path = write_test_ttf_with_os2_default_char!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoDefaultCharMissingWidth", path)
      |> Tincture.set_font("DemoDefaultCharMissingWidth", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/MissingWidth 700"

    File.rm(path)
  end

  test "register_ttf_font/3 falls back MissingWidth to OS/2 break char glyph when default char is unmapped" do
    path = write_test_ttf_with_os2_break_char!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoBreakCharMissingWidth", path)
      |> Tincture.set_font("DemoBreakCharMissingWidth", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/MissingWidth 700"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed OS/2 first/last char indexes for non-subset char range" do
    path = write_test_ttf_with_os2_char_range!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoOS2CharRange", path)
      |> Tincture.set_font("DemoOS2CharRange", 14)
      |> Tincture.text_at(50, 700, "AB")
      |> Tincture.export()

    assert pdf_binary =~ "/FirstChar 65 /LastChar 66"
    assert pdf_binary =~ "/Widths [500 700]"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor italic angle and italic flag from parsed metrics" do
    path = write_test_ttf_with_post_italic!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoItalicMetrics", path)
      |> Tincture.set_font("DemoItalicMetrics", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Flags 96"
    assert pdf_binary =~ "/ItalicAngle -12"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor fixed-pitch flag from parsed post metrics" do
    path = write_test_ttf_with_post_fixed_pitch!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoFixedPitchMetrics", path)
      |> Tincture.set_font("DemoFixedPitchMetrics", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Flags 33"
    assert pdf_binary =~ "/ItalicAngle 0"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor force-bold flag from parsed head macStyle" do
    path = write_test_ttf_with_head_bold!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoForceBoldMetrics", path)
      |> Tincture.set_font("DemoForceBoldMetrics", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Flags 262176"
    assert pdf_binary =~ "/ItalicAngle 0"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor FontFamily from parsed name table" do
    path = write_test_ttf_with_name_table!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoFamilyName", path)
      |> Tincture.set_font("DemoFamilyName", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontFamily (Demo Family)"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontFamily from parsed CFF metadata when name table is unavailable" do
    path = write_test_otf_with_cff_family_name!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFFamilyName", path)
      |> Tincture.set_font("DemoCFFFamilyName", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontFamily (CFF Demo Family)"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontFamily from parsed CFF standard SID family metadata when name table is unavailable" do
    path = write_test_otf_with_cff_standard_family_name!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFStandardSIDFamilyName", path)
      |> Tincture.set_font("DemoCFFStandardSIDFamilyName", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontFamily (Regular)"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontFamily from CFF FullName fallback when FamilyName and name table are unavailable" do
    path = write_test_otf_with_cff_full_name!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFFullNameFamily", path)
      |> Tincture.set_font("DemoCFFFullNameFamily", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontFamily (CFF Demo FullName)"

    File.rm(path)
  end

  test "register_otf_font/3 emits descriptor FontFamily from CFF FontName fallback when FamilyName, FullName, and name table are unavailable" do
    path = write_test_otf_with_cff_font_name!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoCFFFontNameFamily", path)
      |> Tincture.set_font("DemoCFFFontNameFamily", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/FontFamily (CFF FontName Demo)"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor style flags from OS/2 fsSelection bits" do
    path = write_test_ttf_with_os2_selection!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoOS2SelectionStyle", path)
      |> Tincture.set_font("DemoOS2SelectionStyle", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Flags 262240"
    assert pdf_binary =~ "/ItalicAngle 0"

    File.rm(path)
  end

  test "register_ttf_font/3 emits italic descriptor style flags from OS/2 fsSelection oblique bit" do
    path = write_test_ttf_with_os2_oblique_selection!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoOS2ObliqueSelectionStyle", path)
      |> Tincture.set_font("DemoOS2ObliqueSelectionStyle", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Flags 96"
    assert pdf_binary =~ "/ItalicAngle 0"

    File.rm(path)
  end

  test "register_ttf_font/3 emits descriptor Style Panose from parsed OS/2 metadata" do
    path = write_test_ttf_with_os2_panose!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoPanoseStyle", path)
      |> Tincture.set_font("DemoPanoseStyle", 14)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    assert pdf_binary =~ "/Style << /Panose <020B0604020202020204> >>"

    File.rm(path)
  end

  test "register_ttf_font/3 emits Type0/CID font objects for unicode text runs" do
    path = write_test_ttf_with_os2!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeType0", path)
      |> Tincture.set_font("DemoUnicodeType0", 12)
      |> Tincture.text_at(50, 700, "Snowman ☃")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Type0"
    assert pdf_binary =~ "/Encoding /Identity-H"
    assert pdf_binary =~ "/Subtype /CIDFontType2"
    assert pdf_binary =~ "/DescendantFonts ["
    assert pdf_binary =~ "<0053006E006F0077006D0061006E00202603> Tj"

    File.rm(path)
  end

  test "register_ttf_font/3 emits ToUnicode cmap for Type0 unicode fonts" do
    path = write_test_ttf_with_os2!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeToUnicode", path)
      |> Tincture.set_font("DemoUnicodeToUnicode", 12)
      |> Tincture.text_at(50, 700, "Snowman ☃")
      |> Tincture.export()

    assert pdf_binary =~ "/ToUnicode "
    assert pdf_binary =~ "begincmap"
    assert pdf_binary =~ "beginbfchar"
    assert pdf_binary =~ "<2603> <2603>"

    File.rm(path)
  end

  test "register_ttf_font/3 emits CID width arrays for Type0 unicode fonts" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeCIDWidths", path)
      |> Tincture.set_font("DemoUnicodeCIDWidths", 12)
      |> Tincture.text_at(50, 700, "AB☃")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /CIDFontType2"
    assert pdf_binary =~ "/CIDToGIDMap "
    refute pdf_binary =~ "/CIDToGIDMap /Identity"
    assert pdf_binary =~ "/DW 500"
    assert pdf_binary =~ "/W [65 [500] 66 [700] 9731 [600]]"

    File.rm(path)
  end

  test "register_ttf_font/3 emits CIDToGIDMap stream for Type0 unicode fonts using cmap glyph IDs" do
    path = write_test_ttf_with_cmap_format4!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeCIDToGIDMap", path)
      |> Tincture.set_font("DemoUnicodeCIDToGIDMap", 12)
      |> Tincture.text_at(50, 700, "☃★")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /CIDFontType2"
    refute pdf_binary =~ "/CIDToGIDMap /Identity"

    cid_to_gid_map = cid_to_gid_map_data_from_pdf!(pdf_binary)
    assert cid_to_gid_for_cid!(cid_to_gid_map, 9731) == 1
    assert cid_to_gid_for_cid!(cid_to_gid_map, 9733) == 2

    File.rm(path)
  end

  test "register_ttf_font/3 handles non-BMP unicode in Type0 ToUnicode and CID widths" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeNonBMP", path)
      |> Tincture.set_font("DemoUnicodeNonBMP", 12)
      |> Tincture.text_at(50, 700, "😀")
      |> Tincture.export()

    assert pdf_binary =~ "<D83DDE00> Tj"
    assert pdf_binary =~ "<D83DDE00> <D83DDE00>"
    assert pdf_binary =~ "<00000000> <FFFFFFFF>"
    assert pdf_binary =~ "/W [55357 [600] 56832 [600]]"

    File.rm(path)
  end

  test "register_ttf_font/3 maps non-BMP surrogate CIDs in CIDToGIDMap from format-12 cmap data" do
    path = write_test_ttf_with_cmap_format12!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeNonBMPCIDToGID", path)
      |> Tincture.set_font("DemoUnicodeNonBMPCIDToGID", 12)
      |> Tincture.text_at(50, 700, "😀")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /CIDFontType2"
    refute pdf_binary =~ "/CIDToGIDMap /Identity"
    assert pdf_binary =~ "/Filter /FlateDecode"

    cid_to_gid_map = cid_to_gid_map_data_from_pdf!(pdf_binary)
    assert cid_to_gid_for_cid!(cid_to_gid_map, 0xD83D) == 1
    assert cid_to_gid_for_cid!(cid_to_gid_map, 0xDE00) == 0

    File.rm(path)
  end

  test "register_ttf_font/3 falls back to CIDToGIDMap /Identity when non-BMP surrogate CIDs are ambiguous" do
    path = write_test_ttf_with_cmap_format12_ambiguous_surrogates!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeNonBMPCIDToGIDAmbiguous", path)
      |> Tincture.set_font("DemoUnicodeNonBMPCIDToGIDAmbiguous", 12)
      |> Tincture.text_at(50, 700, "😀😁")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /CIDFontType2"
    assert pdf_binary =~ "/CIDToGIDMap /Identity"
    refute pdf_binary =~ "/Filter /FlateDecode"

    File.rm(path)
  end

  test "register_ttf_font/3 falls back to base CID widths when non-BMP surrogate widths are ambiguous" do
    path = write_test_ttf_with_cmap_format12_ambiguous_surrogates!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeNonBMPWidthsAmbiguous", path)
      |> Tincture.set_font("DemoUnicodeNonBMPWidthsAmbiguous", 12)
      |> Tincture.text_at(50, 700, "😀😁")
      |> Tincture.export()

    assert pdf_binary =~ "/W [55357 [600] 56832 56833 600]"

    File.rm(path)
  end

  test "register_ttf_font/3 logs warnings when non-BMP surrogate ambiguity triggers Type0 fallbacks" do
    path = write_test_ttf_with_cmap_format12_ambiguous_surrogates!()

    log =
      capture_log(fn ->
        Tincture.new()
        |> Tincture.register_ttf_font("DemoUnicodeNonBMPAmbiguousWarnings", path)
        |> Tincture.set_font("DemoUnicodeNonBMPAmbiguousWarnings", 12)
        |> Tincture.text_at(50, 700, "😀😁")
        |> Tincture.export()
      end)

    assert log =~ "CIDToGIDMap fallback to /Identity"
    assert log =~ "width override fallback"

    File.rm(path)
  end

  test "register_ttf_font/3 compacts ToUnicode contiguous mappings into bfrange" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeToUnicodeCompact", path)
      |> Tincture.set_font("DemoUnicodeToUnicodeCompact", 12)
      |> Tincture.text_at(50, 700, "ABC☃")
      |> Tincture.export()

    assert pdf_binary =~ "beginbfrange"
    assert pdf_binary =~ "<0041> <0043> <0041>"

    File.rm(path)
  end

  test "register_ttf_font/3 compacts contiguous CID widths into range form" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeCIDCompact", path)
      |> Tincture.set_font("DemoUnicodeCIDCompact", 12)
      |> Tincture.text_at(50, 700, "☃☄★")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 9733 600]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 4 mappings for unicode CID widths" do
    path = write_test_ttf_with_cmap_format4!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat4", path)
      |> Tincture.set_font("DemoUnicodeFormat4", 12)
      |> Tincture.text_at(50, 700, "☃★")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 [700] 9733 [700]]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 6 mappings for unicode CID widths" do
    path = write_test_ttf_with_cmap_format6!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat6", path)
      |> Tincture.set_font("DemoUnicodeFormat6", 12)
      |> Tincture.text_at(50, 700, "☃☄")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 [700] 9732 [650]]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 12 mappings for non-BMP CID widths" do
    path = write_test_ttf_with_cmap_format12!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat12", path)
      |> Tincture.set_font("DemoUnicodeFormat12", 12)
      |> Tincture.text_at(50, 700, "😀")
      |> Tincture.export()

    assert pdf_binary =~ "/W [55357 [700] 56832 [0]]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 13 mappings for unicode CID widths" do
    path = write_test_ttf_with_cmap_format13!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat13", path)
      |> Tincture.set_font("DemoUnicodeFormat13", 12)
      |> Tincture.text_at(50, 700, "☃☄★")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 9733 650]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 10 mappings for unicode CID widths" do
    path = write_test_ttf_with_cmap_format10!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat10", path)
      |> Tincture.set_font("DemoUnicodeFormat10", 12)
      |> Tincture.text_at(50, 700, "☃☄")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 [700] 9732 [650]]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 2 mappings for unicode CID widths" do
    path = write_test_ttf_with_cmap_format2!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat2", path)
      |> Tincture.set_font("DemoUnicodeFormat2", 12)
      |> Tincture.text_at(50, 700, "☃☄")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 [700] 9732 [650]]"

    File.rm(path)
  end

  test "register_ttf_font/3 uses parsed cmap format 8 mappings for unicode CID widths" do
    path = write_test_ttf_with_cmap_format8!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat8", path)
      |> Tincture.set_font("DemoUnicodeFormat8", 12)
      |> Tincture.text_at(50, 700, "☃☄")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 [700] 9732 [650]]"

    File.rm(path)
  end

  test "register_ttf_font/3 stores parsed cmap format 14 variation metadata" do
    path = write_test_ttf_with_cmap_format14!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat14", path)

    metrics = pdf.embedded_fonts["DemoUnicodeFormat14"].ttf_metrics
    assert metrics.cmap_var_selectors == [0xFE0F]
    assert metrics.cmap_non_default_uvs[{0x2603, 0xFE0F}] == 1

    File.rm(path)
  end

  test "register_ttf_font/3 applies format-14 variation mapping to Type0 CID widths" do
    path = write_test_ttf_with_cmap_format4_and14!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat4And14Widths", path)
      |> Tincture.set_font("DemoUnicodeFormat4And14Widths", 12)
      |> Tincture.text_at(50, 700, "☃️")
      |> Tincture.export()

    assert pdf_binary =~ "/W [9731 [650] 65039 [0]]"

    File.rm(path)
  end

  test "register_ttf_font/3 applies format-14 variation mapping to Type0 CIDToGIDMap" do
    path = write_test_ttf_with_cmap_format4_and14!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeFormat4And14CIDToGID", path)
      |> Tincture.set_font("DemoUnicodeFormat4And14CIDToGID", 12)
      |> Tincture.text_at(50, 700, "☃️")
      |> Tincture.export()

    refute pdf_binary =~ "/CIDToGIDMap /Identity"
    assert extract_cid_to_gid_value(pdf_binary, 9731) == 2
    assert extract_cid_to_gid_value(pdf_binary, 65_039) == 0

    File.rm(path)
  end

  test "register_ttf_font/3 emits CIDToGID zero mapping for unmapped ZWJ codepoints" do
    path = write_test_ttf_with_cmap_format4!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeZWJCIDToGID", path)
      |> Tincture.set_font("DemoUnicodeZWJCIDToGID", 12)
      |> Tincture.text_at(50, 700, "☃‍★")
      |> Tincture.export()

    refute pdf_binary =~ "/CIDToGIDMap /Identity"
    assert extract_cid_to_gid_value(pdf_binary, 8205) == 0

    File.rm(path)
  end

  test "register_ttf_font/3 emits CIDToGID zero mapping for unmapped combining marks" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeCombiningCIDToGID", path)
      |> Tincture.set_font("DemoUnicodeCombiningCIDToGID", 12)
      |> Tincture.text_at(50, 700, "Á")
      |> Tincture.export()

    refute pdf_binary =~ "/CIDToGIDMap /Identity"
    assert extract_cid_to_gid_value(pdf_binary, 769) == 0

    File.rm(path)
  end

  test "register_ttf_font/3 emits zero CID width for unmapped ZWJ codepoints in Type0 widths" do
    path = write_test_ttf_with_cmap_format4!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeZWJWidth", path)
      |> Tincture.set_font("DemoUnicodeZWJWidth", 12)
      |> Tincture.text_at(50, 700, "☃‍★")
      |> Tincture.export()

    assert pdf_binary =~ "/W [8205 [0] 9731 [700] 9733 [700]]"

    File.rm(path)
  end

  test "register_ttf_font/3 emits zero CID width for unmapped combining marks in Type0 widths" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeCombiningWidth", path)
      |> Tincture.set_font("DemoUnicodeCombiningWidth", 12)
      |> Tincture.text_at(50, 700, "Á")
      |> Tincture.export()

    assert pdf_binary =~ "/W [65 [500] 769 [0]]"

    File.rm(path)
  end

  test "register_ttf_font/3 emits zero CID width for unmapped script-specific combining marks in Type0 widths" do
    path = write_test_ttf_with_cmap!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_ttf_font("DemoUnicodeScriptCombiningWidth", path)
      |> Tincture.set_font("DemoUnicodeScriptCombiningWidth", 12)
      |> Tincture.text_at(50, 700, "Aְ")
      |> Tincture.export()

    assert pdf_binary =~ "/W [65 [500] 1456 [0]]"

    File.rm(path)
  end

  test "register_otf_font/3 emits Type0/CID font objects for unicode text runs" do
    path = write_test_otf_with_cmap_format4!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFUnicodeType0", path)
      |> Tincture.set_font("DemoOTFUnicodeType0", 12)
      |> Tincture.text_at(50, 700, "☃")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Type0"
    assert pdf_binary =~ "/Encoding /Identity-H"
    assert pdf_binary =~ "/Subtype /CIDFontType0"
    assert pdf_binary =~ "/W [9731 [700]]"
    refute pdf_binary =~ "/CIDToGIDMap /Identity"

    File.rm(path)
  end

  test "register_otf_font/4 used-text subset uses Type0/CID objects for non-ASCII text runs" do
    path = write_test_otf_with_cmap_format4!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFUnicodeSubsetType0", path, subset: :used_text)
      |> Tincture.set_font("DemoOTFUnicodeSubsetType0", 12)
      |> Tincture.text_at(50, 700, "☃")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Type0"
    assert pdf_binary =~ "/Subtype /CIDFontType0"
    assert pdf_binary =~ "/Encoding /Identity-H"
    assert pdf_binary =~ "/CIDSet "
    assert pdf_binary =~ "/ToUnicode "

    File.rm(path)
  end

  test "register_otf_font/3 handles non-BMP unicode in Type0 ToUnicode and CID widths" do
    path = write_test_otf_with_cmap_format12!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFUnicodeNonBMP", path)
      |> Tincture.set_font("DemoOTFUnicodeNonBMP", 12)
      |> Tincture.text_at(50, 700, "😀")
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /CIDFontType0"
    assert pdf_binary =~ "<D83DDE00> Tj"
    assert pdf_binary =~ "<D83DDE00> <D83DDE00>"
    assert pdf_binary =~ "<00000000> <FFFFFFFF>"
    assert pdf_binary =~ "/W [55357 [700] 56832 [0]]"

    File.rm(path)
  end

  test "register_otf_font/3 embeds an OpenType font stream and allows set_font/3" do
    path = write_test_otf!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTF", path)
      |> Tincture.set_font("DemoOTF", 12)
      |> Tincture.text_at(50, 700, "Hello OTF")
      |> Tincture.export()

    assert pdf_binary =~ "/BaseFont /DemoOTF"
    assert pdf_binary =~ "/FontFile3 "
    assert pdf_binary =~ "/Subtype /OpenType"
    assert pdf_binary =~ "/F1 12 Tf"

    File.rm(path)
  end

  test "register_otf_font/4 uses parsed sfnt widths for used-text subset ranges when tables exist" do
    path = write_test_otf_with_metrics!()

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFMetrics", path, subset: :used_text)
      |> Tincture.set_font("DemoOTFMetrics", 12)
      |> Tincture.text_at(50, 700, "AB")
      |> Tincture.export()

    assert pdf_binary =~ "/FirstChar 65 /LastChar 66"
    assert pdf_binary =~ "/Widths [500 700]"

    File.rm(path)
  end

  test "register_otf_font/4 used-text subset shrinks CFF charstrings for unused glyphs" do
    path = write_test_otf_with_cmap_cff_charstrings!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFCFFSubset", path, subset: :used_text)
      |> Tincture.set_font("DemoOTFCFFSubset", 12)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    assert byte_size(subset_font_data) < original_length

    charstring_lengths = cff_charstring_lengths_from_sfnt!(subset_font_data)
    assert Enum.at(charstring_lengths, 0) >= 1
    assert Enum.at(charstring_lengths, 1) > 1
    assert Enum.at(charstring_lengths, 2) == 1
    assert Enum.at(charstring_lengths, 3) == 1

    File.rm(path)
  end

  test "register_otf_font/4 used-text subset shrinks CFF charstrings when unreferenced bytes trail CharStrings" do
    path = write_test_otf_with_cmap_cff_charstrings_tail!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFCFFSubsetTail", path, subset: :used_text)
      |> Tincture.set_font("DemoOTFCFFSubsetTail", 12)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    assert byte_size(subset_font_data) < original_length

    charstring_lengths = cff_charstring_lengths_from_sfnt!(subset_font_data)
    assert Enum.at(charstring_lengths, 0) >= 1
    assert Enum.at(charstring_lengths, 1) > 1
    assert Enum.at(charstring_lengths, 2) == 1
    assert Enum.at(charstring_lengths, 3) == 1

    File.rm(path)
  end

  test "register_otf_font/4 used-text subset shrinks CFF charstrings when Top DICT includes real-number operands" do
    path = write_test_otf_with_cmap_cff_charstrings_real_top_dict!()
    original_length = byte_size(File.read!(path))

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFCFFSubsetRealTopDict", path, subset: :used_text)
      |> Tincture.set_font("DemoOTFCFFSubsetRealTopDict", 12)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    assert byte_size(subset_font_data) < original_length

    File.rm(path)
  end

  test "register_otf_font/4 used-text subset updates referenced CFF Private offsets when CharStrings shrink" do
    path = write_test_otf_with_cmap_cff_charstrings_private_tail!()
    original_font_data = File.read!(path)
    original_private_offset = cff_private_offset_from_sfnt!(original_font_data)
    original_length = byte_size(original_font_data)

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFCFFSubsetPrivateTail", path, subset: :used_text)
      |> Tincture.set_font("DemoOTFCFFSubsetPrivateTail", 12)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    subset_private_offset = cff_private_offset_from_sfnt!(subset_font_data)
    subset_private_marker = cff_private_marker_from_sfnt!(subset_font_data)

    assert byte_size(subset_font_data) < original_length
    assert subset_private_offset < original_private_offset
    assert subset_private_marker == "PRIV"

    File.rm(path)
  end

  test "register_otf_font/4 used-text subset updates FDArray Font DICT private offsets when CharStrings shrink" do
    path = write_test_otf_with_cmap_cff_charstrings_fdarray_private_tail!()
    original_font_data = File.read!(path)
    original_private_offset = cff_fdarray_private_offset_from_sfnt!(original_font_data)
    original_length = byte_size(original_font_data)

    pdf_binary =
      Tincture.new()
      |> Tincture.register_otf_font("DemoOTFCFFSubsetFDArrayPrivateTail", path,
        subset: :used_text
      )
      |> Tincture.set_font("DemoOTFCFFSubsetFDArrayPrivateTail", 12)
      |> Tincture.text_at(50, 700, "A")
      |> Tincture.export()

    subset_font_data = font_file_data_from_pdf!(pdf_binary)
    subset_private_offset = cff_fdarray_private_offset_from_sfnt!(subset_font_data)
    subset_private_marker = cff_fdarray_private_marker_from_sfnt!(subset_font_data)

    assert byte_size(subset_font_data) < original_length
    assert subset_private_offset < original_private_offset
    assert subset_private_marker == "FDPV"

    File.rm(path)
  end

  test "register_ttf_font/4 and register_otf_font/4 reject invalid subset options" do
    ttf_path = write_test_ttf!()
    otf_path = write_test_otf!()

    assert_raise ArgumentError, "subset must be :none, :ascii_basic, or :used_text", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("BadSubsetTTF", ttf_path, subset: :full)
    end

    assert_raise ArgumentError, "subset must be :none, :ascii_basic, or :used_text", fn ->
      Tincture.new()
      |> Tincture.register_otf_font("BadSubsetOTF", otf_path, subset: :full)
    end

    File.rm(ttf_path)
    File.rm(otf_path)
  end

  test "register_ttf_font/4 rejects non-boolean enforce_embedding_permissions option values" do
    path = write_test_ttf!()

    assert_raise ArgumentError, "enforce_embedding_permissions must be a boolean", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("BadEnforcementOption", path,
        enforce_embedding_permissions: :strict
      )
    end

    File.rm(path)
  end

  test "register_ttf_font/3 rejects invalid TTF payloads" do
    path = write_test_binary!(".ttf", <<"not-a-ttf">>)

    assert_raise ArgumentError, "invalid TTF file: #{path}", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("BadTTF", path)
    end

    File.rm(path)
  end

  test "register_ttf_font/3 rejects TTF payloads missing required metric tables" do
    path = write_test_binary!(".ttf", test_ttf_missing_required_tables_binary())

    assert_raise ArgumentError, "invalid TTF file: #{path}", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("BadTTFTables", path)
    end

    File.rm(path)
  end

  test "register_otf_font/3 rejects invalid OTF payloads" do
    path = write_test_binary!(".otf", <<"not-an-otf">>)

    assert_raise ArgumentError, "invalid OTF file: #{path}", fn ->
      Tincture.new()
      |> Tincture.register_otf_font("BadOTF", path)
    end

    File.rm(path)
  end

  test "register_ttf_font/3 and register_otf_font/3 reject unreadable files" do
    missing_ttf =
      Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.ttf")

    missing_otf =
      Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.otf")

    assert_raise ArgumentError, "unable to read TTF file: #{missing_ttf}", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("MissingTTF", missing_ttf)
    end

    assert_raise ArgumentError, "unable to read OTF file: #{missing_otf}", fn ->
      Tincture.new()
      |> Tincture.register_otf_font("MissingOTF", missing_otf)
    end
  end

  test "set_font/3 rejects unknown fonts" do
    assert_raise ArgumentError, fn ->
      Tincture.new()
      |> Tincture.set_font("Unknown-Font", 12)
    end
  end

  test "text_at_with_fallback/5 splits text runs across embedded fallback fonts" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "A☃B", ["FallbackSnowman"])

    assert [
             {:text_at, x1, 700, "A", {"PrimaryASCII", 12}},
             {:text_at, x2, 700, "☃", {"FallbackSnowman", 12}},
             {:text_at, x3, 700, "B", {"PrimaryASCII", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001
    assert_in_delta x3, 64.4, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 keeps a single run when primary supports all glyphs" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(10, 600, "AB", ["FallbackSnowman"])

    assert [{:text_at, x, 600, "AB", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 treats unmapped ZWJ as zero-width for cursor advancement" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "A‍B☃", ["FallbackSnowman"])

    assert [
             {:text_at, 50.0, 700, "A‍B", {"PrimaryASCII", 12}},
             {:text_at, x2, 700, "☃", {"FallbackSnowman", 12}}
           ] = pdf.operations

    assert_in_delta x2, 64.4, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 treats unmapped ZWJ as zero-width with built-in primary fonts" do
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.text_at_with_fallback(50, 700, "A‍B☃", ["FallbackSnowman"])

    assert [
             {:text_at, 50.0, 700, "A‍B", {"Helvetica", 12}},
             {:text_at, x2, 700, "☃", {"FallbackSnowman", 12}}
           ] = pdf.operations

    expected_x2 = 50.0 + Tincture.Font.text_width("Helvetica", 12, "AB")
    assert_in_delta x2, expected_x2, 0.001

    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 treats unmapped combining marks as zero-width for cursor advancement" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "ÁB☃", ["FallbackSnowman"])

    assert [
             {:text_at, 50.0, 700, "ÁB", {"PrimaryASCII", 12}},
             {:text_at, x2, 700, "☃", {"FallbackSnowman", 12}}
           ] = pdf.operations

    assert_in_delta x2, 64.4, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 treats unmapped script-specific combining marks as zero-width for cursor advancement" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AְB☃", ["FallbackSnowman"])

    assert [
             {:text_at, 50.0, 700, "AְB", {"PrimaryASCII", 12}},
             {:text_at, x2, 700, "☃", {"FallbackSnowman", 12}}
           ] = pdf.operations

    assert_in_delta x2, 64.4, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 treats unmapped combining marks as zero-width with built-in primary fonts" do
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.text_at_with_fallback(50, 700, "ÁB☃", ["FallbackSnowman"])

    assert [
             {:text_at, 50.0, 700, "ÁB", {"Helvetica", 12}},
             {:text_at, x2, 700, "☃", {"FallbackSnowman", 12}}
           ] = pdf.operations

    expected_x2 = 50.0 + Tincture.Font.text_width("Helvetica", 12, "AB")
    assert_in_delta x2, expected_x2, 0.001

    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 prefers fallback font for ZWJ sequences when primary lacks base glyphs" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_with_cmap_format4!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSymbols", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "☃‍★", ["FallbackSymbols"])

    assert [{:text_at, 50.0, 700, "☃‍★", {"FallbackSymbols", 12}}] = pdf.operations

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 preserves current font after drawing fallback runs" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(10, 600, "A☃", ["FallbackSnowman"])

    assert pdf.current_font == {"PrimaryASCII", 12}

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_rotated_with_fallback/6 preserves current font after drawing fallback runs" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_fallback_snowman!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_rotated_with_fallback(10, 600, 30, "A☃", ["FallbackSnowman"])

    assert pdf.current_font == {"PrimaryASCII", 12}

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/6 preserves current font when shaping uses fallback glyphs" do
    ligature_path = write_test_ttf_ligature_fi!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackLigatureFI", ligature_path)
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at_with_fallback(50, 700, "fi", ["FallbackLigatureFI"],
        shaping: :latin_ligatures
      )

    assert pdf.current_font == {"Helvetica", 12}

    File.rm(ligature_path)
  end

  test "text_at_with_fallback/5 keeps variation-selector graphemes in a single fallback run and advances by variation width" do
    primary_path = write_test_ttf_primary_ascii!()
    fallback_path = write_test_ttf_with_cmap_format4_and14!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowmanVariation", fallback_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "A☃️B", ["FallbackSnowmanVariation"])

    assert [
             {:text_at, x1, 700, "A", {"PrimaryASCII", 12}},
             {:text_at, x2, 700, "☃️", {"FallbackSnowmanVariation", 12}},
             {:text_at, x3, 700, "B", {"PrimaryASCII", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001
    assert_in_delta x3, 63.8, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 prefers fonts with format-14 variation mappings over base-only glyph coverage" do
    primary_path = write_test_ttf_fallback_snowman!()
    fallback_path = write_test_ttf_with_cmap_format4_and14!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimarySnowmanBaseOnly", primary_path)
      |> Tincture.register_ttf_font("FallbackSnowmanVariation", fallback_path)
      |> Tincture.set_font("PrimarySnowmanBaseOnly", 12)
      |> Tincture.text_at_with_fallback(50, 700, "☃️", ["FallbackSnowmanVariation"])

    assert [{:text_at, x, 700, "☃️", {"FallbackSnowmanVariation", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 unicode ranges when embedded cmap is unavailable" do
    primary_path = write_test_ttf_no_cmap_greek_range!()
    fallback_path = write_test_ttf_primary_ascii!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryGreekNoCmap", primary_path)
      |> Tincture.register_ttf_font("FallbackASCII", fallback_path)
      |> Tincture.set_font("PrimaryGreekNoCmap", 12)
      |> Tincture.text_at_with_fallback(10, 600, "A", ["FallbackASCII"])

    assert [{:text_at, x, 600, "A", {"FallbackASCII", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 keeps permissive fallback when embedded cmap and unicode ranges are unavailable" do
    primary_path = write_test_ttf_no_cmap_zero_ranges!()
    fallback_path = write_test_ttf_primary_ascii!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryNoCmapUnknownRanges", primary_path)
      |> Tincture.register_ttf_font("FallbackASCII", fallback_path)
      |> Tincture.set_font("PrimaryNoCmapUnknownRanges", 12)
      |> Tincture.text_at_with_fallback(10, 600, "A", ["FallbackASCII"])

    assert [{:text_at, x, 600, "A", {"PrimaryNoCmapUnknownRanges", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 code page ranges when cmap and unicode ranges are unavailable" do
    primary_path = write_test_ttf_no_cmap_cyrillic_codepage!()
    fallback_path = write_test_ttf_latin1_e_acute!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryCyrillicNoCmap", primary_path)
      |> Tincture.register_ttf_font("FallbackLatin1EAcute", fallback_path)
      |> Tincture.set_font("PrimaryCyrillicNoCmap", 12)
      |> Tincture.text_at_with_fallback(10, 600, "é", ["FallbackLatin1EAcute"])

    assert [{:text_at, x, 600, "é", {"FallbackLatin1EAcute", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Cyrillic code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_cyrillic_codepage!()
    fallback_path = write_test_ttf_cyrillic_zh!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryCyrillicNoCmap", primary_path)
      |> Tincture.register_ttf_font("FallbackCyrillicZh", fallback_path)
      |> Tincture.set_font("PrimaryCyrillicNoCmap", 12)
      |> Tincture.text_at_with_fallback(10, 600, "Ж", ["FallbackCyrillicZh"])

    assert [{:text_at, x, 600, "Ж", {"PrimaryCyrillicNoCmap", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Greek code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_greek_codepage!()
    fallback_path = write_test_ttf_greek_omega!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryGreekNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackGreekOmega", fallback_path)
      |> Tincture.set_font("PrimaryGreekNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "Ω", ["FallbackGreekOmega"])

    assert [{:text_at, x, 600, "Ω", {"PrimaryGreekNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Turkish code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_turkish_codepage!()
    fallback_path = write_test_ttf_turkish_g_breve!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryTurkishNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackTurkishGBreve", fallback_path)
      |> Tincture.set_font("PrimaryTurkishNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "ğ", ["FallbackTurkishGBreve"])

    assert [{:text_at, x, 600, "ğ", {"PrimaryTurkishNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Baltic code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_baltic_codepage!()
    fallback_path = write_test_ttf_baltic_g_cedilla!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryBalticNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackBalticGCedilla", fallback_path)
      |> Tincture.set_font("PrimaryBalticNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "Ģ", ["FallbackBalticGCedilla"])

    assert [{:text_at, x, 600, "Ģ", {"PrimaryBalticNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Vietnamese code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_vietnamese_codepage!()
    fallback_path = write_test_ttf_vietnamese_o_horn!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryVietnameseNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackVietnameseOHorn", fallback_path)
      |> Tincture.set_font("PrimaryVietnameseNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "ơ", ["FallbackVietnameseOHorn"])

    assert [{:text_at, x, 600, "ơ", {"PrimaryVietnameseNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Hebrew code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_hebrew_codepage!()
    fallback_path = write_test_ttf_hebrew_alef!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryHebrewNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackHebrewAlef", fallback_path)
      |> Tincture.set_font("PrimaryHebrewNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "א", ["FallbackHebrewAlef"])

    assert [{:text_at, x, 600, "א", {"PrimaryHebrewNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Arabic code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_arabic_codepage!()
    fallback_path = write_test_ttf_arabic_alef!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryArabicNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackArabicAlef", fallback_path)
      |> Tincture.set_font("PrimaryArabicNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "ا", ["FallbackArabicAlef"])

    assert [{:text_at, x, 600, "ا", {"PrimaryArabicNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Thai code page for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_thai_codepage!()
    fallback_path = write_test_ttf_thai_ko_kai!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryThaiNoCmapCodePage", primary_path)
      |> Tincture.register_ttf_font("FallbackThaiKoKai", fallback_path)
      |> Tincture.set_font("PrimaryThaiNoCmapCodePage", 12)
      |> Tincture.text_at_with_fallback(10, 600, "ก", ["FallbackThaiKoKai"])

    assert [{:text_at, x, 600, "ก", {"PrimaryThaiNoCmapCodePage", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Cyrillic unicode range for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_cyrillic_unicode_range!()
    fallback_path = write_test_ttf_cyrillic_zh!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryCyrillicNoCmapUnicodeRange", primary_path)
      |> Tincture.register_ttf_font("FallbackCyrillicZh", fallback_path)
      |> Tincture.set_font("PrimaryCyrillicNoCmapUnicodeRange", 12)
      |> Tincture.text_at_with_fallback(10, 600, "Ж", ["FallbackCyrillicZh"])

    assert [{:text_at, x, 600, "Ж", {"PrimaryCyrillicNoCmapUnicodeRange", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Hebrew unicode range for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_hebrew_unicode_range!()
    fallback_path = write_test_ttf_hebrew_alef!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryHebrewNoCmapUnicodeRange", primary_path)
      |> Tincture.register_ttf_font("FallbackHebrewAlef", fallback_path)
      |> Tincture.set_font("PrimaryHebrewNoCmapUnicodeRange", 12)
      |> Tincture.text_at_with_fallback(10, 600, "א", ["FallbackHebrewAlef"])

    assert [{:text_at, x, 600, "א", {"PrimaryHebrewNoCmapUnicodeRange", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Arabic unicode range for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_arabic_unicode_range!()
    fallback_path = write_test_ttf_arabic_alef!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryArabicNoCmapUnicodeRange", primary_path)
      |> Tincture.register_ttf_font("FallbackArabicAlef", fallback_path)
      |> Tincture.set_font("PrimaryArabicNoCmapUnicodeRange", 12)
      |> Tincture.text_at_with_fallback(10, 600, "ا", ["FallbackArabicAlef"])

    assert [{:text_at, x, 600, "ا", {"PrimaryArabicNoCmapUnicodeRange", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Armenian unicode range for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_armenian_unicode_range!()
    fallback_path = write_test_ttf_armenian_ayb!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryArmenianNoCmapUnicodeRange", primary_path)
      |> Tincture.register_ttf_font("FallbackArmenianAyb", fallback_path)
      |> Tincture.set_font("PrimaryArmenianNoCmapUnicodeRange", 12)
      |> Tincture.text_at_with_fallback(10, 600, "Ա", ["FallbackArmenianAyb"])

    assert [{:text_at, x, 600, "Ա", {"PrimaryArmenianNoCmapUnicodeRange", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Devanagari unicode range for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_devanagari_unicode_range!()
    fallback_path = write_test_ttf_devanagari_a!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryDevanagariNoCmapUnicodeRange", primary_path)
      |> Tincture.register_ttf_font("FallbackDevanagariA", fallback_path)
      |> Tincture.set_font("PrimaryDevanagariNoCmapUnicodeRange", 12)
      |> Tincture.text_at_with_fallback(10, 600, "अ", ["FallbackDevanagariA"])

    assert [{:text_at, x, 600, "अ", {"PrimaryDevanagariNoCmapUnicodeRange", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/5 uses OS/2 Thai unicode range for cmap-less embedded fonts" do
    primary_path = write_test_ttf_no_cmap_thai_unicode_range!()
    fallback_path = write_test_ttf_thai_ko_kai!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryThaiNoCmapUnicodeRange", primary_path)
      |> Tincture.register_ttf_font("FallbackThaiKoKai", fallback_path)
      |> Tincture.set_font("PrimaryThaiNoCmapUnicodeRange", 12)
      |> Tincture.text_at_with_fallback(10, 600, "ก", ["FallbackThaiKoKai"])

    assert [{:text_at, x, 600, "ก", {"PrimaryThaiNoCmapUnicodeRange", 12}}] = pdf.operations
    assert_in_delta x, 10.0, 0.001

    File.rm(primary_path)
    File.rm(fallback_path)
  end

  test "text_at_with_fallback/6 applies latin ligature shaping when fallback supports glyph" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_fi!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureFI", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "fi", ["FallbackLigatureFI"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "ﬁ", {"FallbackLigatureFI", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 skips latin ligature shaping when fallback GSUB lacks liga feature" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_fi_with_gsub_no_liga!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureFINoLiga", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "fi", ["FallbackLigatureFINoLiga"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "fi", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 skips latin ligature shaping when fallback GSUB lacks latn script" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_fi_with_gsub_no_latn!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureFINoLatn", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "fi", ["FallbackLigatureFINoLatn"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "fi", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 respects OS/2 max context limits for latin ligature shaping" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_fi_max_context_1!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureFIRestricted", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "fi", ["FallbackLigatureFIRestricted"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "fi", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 applies GSUB lookup-defined latin ligatures" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureST", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st", ["FallbackLigatureST"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "ﬆ", {"FallbackLigatureST", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 applies GSUB lookup-defined single substitutions" do
    single_sub_path = write_test_ttf_single_substitution_a_to_b_with_gsub!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("SingleSubAToB", single_sub_path)
      |> Tincture.set_font("SingleSubAToB", 12)
      |> Tincture.text_at_with_fallback(50, 700, "A", [], shaping: :gsub_ligatures)

    assert [{:text_at, x, 700, "B", {"SingleSubAToB", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(single_sub_path)
  end

  test "text_at_with_fallback/6 applies GSUB rlig single substitutions with shaping: :gsub_ligatures" do
    single_sub_path = write_test_ttf_single_substitution_a_to_b_with_rlig_gsub!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("SingleSubAToBRlig", single_sub_path)
      |> Tincture.set_font("SingleSubAToBRlig", 12)
      |> Tincture.text_at_with_fallback(50, 700, "A", [], shaping: :gsub_ligatures)

    assert [{:text_at, x, 700, "B", {"SingleSubAToBRlig", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(single_sub_path)
  end

  test "text_at_with_fallback/6 skips GSUB ligature when liga feature does not link the lookup" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub_liga_without_lookup!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTNoLigaLookup", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st", ["FallbackLigatureSTNoLigaLookup"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "st", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 prefers default GSUB LangSys over named LangSys for liga lookups" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub_default_langsys_without_lookup!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTDefaultLangSys", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st", ["FallbackLigatureSTDefaultLangSys"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "st", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/5 applies embedded GPOS kerning to segment advance widths" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAV", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAV"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAV", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 62.0, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/6 applies opt-in embedded GPOS kerning to rendered fallback glyph positions" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAV", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAV"], kerning: :gpos)

    assert [
             {:text_at, x1, 700, "A", {"FallbackKerningAV", 12}},
             {:text_at, x2, 700, "V", {"FallbackKerningAV", 12}},
             {:text_at, x3, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001
    assert_in_delta x3, 62.0, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_rotated_with_fallback/7 applies opt-in embedded GPOS kerning to rendered fallback glyph positions" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAV", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_rotated_with_fallback(50, 700, 20, "AVX", ["FallbackKerningAV"],
        kerning: :gpos
      )

    assert [
             {:text_at_rotated, x1, 700, 20, "A", {"FallbackKerningAV", 12}},
             {:text_at_rotated, x2, 700, 20, "V", {"FallbackKerningAV", 12}},
             {:text_at_rotated, x3, 700, 20, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001
    assert_in_delta x3, 62.0, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 applies embedded GPOS ValueRecord2 kerning to segment advance widths" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_value2!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVValue2", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVValue2"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVValue2", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 62.0, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips malformed embedded GPOS pair-kerning subtables when coverage count mismatches pair-set count" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_coverage_mismatch!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVCoverageMismatch", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVCoverageMismatch"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVCoverageMismatch", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackKerningAVCoverageMismatch"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when malformed embedded GPOS pair-kerning subtables are skipped due to coverage/pair-set mismatch" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_coverage_mismatch!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackKerningAVCoverageMismatch", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVCoverageMismatch"])

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackKerningAVCoverageMismatch", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS pair subtable skipped"
    assert log =~ "coverage_glyph_count=2"
    assert log =~ "pair_set_count=1"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips oversized embedded GPOS pair-set value records" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_oversized!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVOversized", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVOversized"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVOversized", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001
    assert pdf.embedded_fonts["FallbackKerningAVOversized"].ttf_metrics.gpos_guardrail_skips == 1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 ignores malformed embedded GPOS pair-set with truncated pair-value records" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_truncated!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVTruncated", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVTruncated"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVTruncated", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001
    assert pdf.embedded_fonts["FallbackKerningAVTruncated"].ttf_metrics.gpos_guardrail_skips == 0

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when oversized embedded GPOS pair-set is skipped" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_oversized!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackKerningAVOversized", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVOversized"])

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackKerningAVOversized", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS pair-set skipped"
    assert log =~ "pair_value_count=10001"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 applies embedded GPOS kerning across zero-advance combining marks" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_a_combining_v!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningACombiningV", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "A\u0301VX", ["FallbackKerningACombiningV"])

    assert [
             {:text_at, x1, 700, "A\u0301V", {"FallbackKerningACombiningV", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 62.0, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 applies embedded GPOS class kerning from format-2 lookups" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVX", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackClassKerningAVX"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVX", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 62.0, 0.001
    assert pdf.embedded_fonts["FallbackClassKerningAVX"].ttf_metrics.gpos_guardrail_skips == 0

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips oversized embedded GPOS class kerning matrices" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_oversized!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVXOversized", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackClassKerningAVXOversized"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVXOversized", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackClassKerningAVXOversized"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when oversized embedded GPOS class kerning matrix is skipped" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_oversized!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackClassKerningAVXOversized", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackClassKerningAVXOversized"])

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackClassKerningAVXOversized", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS class-pair matrix skipped"
    assert log =~ "class1_count=128"
    assert log =~ "class2_count=128"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips malformed embedded GPOS class pair-kerning subtables with invalid class counts" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_invalid_class_counts!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVXInvalidClassCounts", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(
        50,
        700,
        "AVX",
        ["FallbackClassKerningAVXInvalidClassCounts"]
      )

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVXInvalidClassCounts", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackClassKerningAVXInvalidClassCounts"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when malformed embedded GPOS class pair-kerning subtables are skipped due to invalid class counts" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_invalid_class_counts!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackClassKerningAVXInvalidClassCounts", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(
            50,
            700,
            "AVX",
            ["FallbackClassKerningAVXInvalidClassCounts"]
          )

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackClassKerningAVXInvalidClassCounts", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS class-pair subtable skipped"
    assert log =~ "class1_count=1"
    assert log =~ "class2_count=0"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips malformed embedded GPOS class pair-kerning subtables with truncated class-adjustment records" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_truncated_records!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVXTruncatedRecords", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(
        50,
        700,
        "AVX",
        ["FallbackClassKerningAVXTruncatedRecords"]
      )

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVXTruncatedRecords", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackClassKerningAVXTruncatedRecords"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when malformed embedded GPOS class pair-kerning subtables are skipped due to truncated class-adjustment records" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_truncated_records!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackClassKerningAVXTruncatedRecords", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(
            50,
            700,
            "AVX",
            ["FallbackClassKerningAVXTruncatedRecords"]
          )

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackClassKerningAVXTruncatedRecords", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS class-pair subtable skipped"
    assert log =~ "malformed class adjustment records"
    assert log =~ "class1_count=2"
    assert log =~ "class2_count=3"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips malformed embedded GPOS class pair-kerning subtables with invalid class-definition offsets" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_invalid_class_def_offsets!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVXInvalidClassDefOffsets", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(
        50,
        700,
        "AVX",
        ["FallbackClassKerningAVXInvalidClassDefOffsets"]
      )

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVXInvalidClassDefOffsets", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackClassKerningAVXInvalidClassDefOffsets"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when malformed embedded GPOS class pair-kerning subtables are skipped due to invalid class-definition offsets" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_invalid_class_def_offsets!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font(
            "FallbackClassKerningAVXInvalidClassDefOffsets",
            kerning_path
          )
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(
            50,
            700,
            "AVX",
            ["FallbackClassKerningAVXInvalidClassDefOffsets"]
          )

        assert [
                 {:text_at, _x1, 700, "AV",
                  {"FallbackClassKerningAVXInvalidClassDefOffsets", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS class-pair subtable skipped"
    assert log =~ "malformed class definition tables"
    assert log =~ "class1_count=2"
    assert log =~ "class2_count=3"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips oversized expanded embedded GPOS class kerning mappings" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_expansion_oversized!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVXExpansionOversized", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", [
        "FallbackClassKerningAVXExpansionOversized"
      ])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVXExpansionOversized", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackClassKerningAVXExpansionOversized"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when oversized expanded embedded GPOS class kerning mappings are skipped" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_expansion_oversized!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackClassKerningAVXExpansionOversized", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(
            50,
            700,
            "AVX",
            ["FallbackClassKerningAVXExpansionOversized"]
          )

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackClassKerningAVXExpansionOversized", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS class-pair expansion skipped"
    assert log =~ "estimated_pairs="

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips oversized embedded GPOS class-definition expansions" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_classdef_oversized!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackClassKerningAVXClassDefOversized", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(
        50,
        700,
        "AVX",
        ["FallbackClassKerningAVXClassDefOversized"]
      )

    assert [
             {:text_at, x1, 700, "AV", {"FallbackClassKerningAVXClassDefOversized", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    assert pdf.embedded_fonts["FallbackClassKerningAVXClassDefOversized"].ttf_metrics.gpos_guardrail_skips ==
             1

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "register_ttf_font/3 logs when oversized embedded GPOS class-definition expansions are skipped" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_class_kerning_avx_classdef_oversized!()

    log =
      capture_log(fn ->
        pdf =
          Tincture.new()
          |> Tincture.register_ttf_font("PrimaryX", primary_path)
          |> Tincture.register_ttf_font("FallbackClassKerningAVXClassDefOversized", kerning_path)
          |> Tincture.set_font("PrimaryX", 12)
          |> Tincture.text_at_with_fallback(
            50,
            700,
            "AVX",
            ["FallbackClassKerningAVXClassDefOversized"]
          )

        assert [
                 {:text_at, _x1, 700, "AV", {"FallbackClassKerningAVXClassDefOversized", 12}},
                 {:text_at, x2, 700, "X", {"PrimaryX", 12}}
               ] = pdf.operations

        assert_in_delta x2, 63.2, 0.001
      end)

    assert log =~ "GPOS class definition skipped"
    assert log =~ "entries=10002"

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 skips embedded GPOS kerning when kern feature does not link lookup" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_kern_without_lookup!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVNoKernLookup", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVNoKernLookup"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVNoKernLookup", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/5 prefers default GPOS LangSys over named LangSys for kern lookups" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_default_langsys_without_lookup!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVDefaultLangSys", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVDefaultLangSys"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVDefaultLangSys", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/6 prefers latn script over arab script for GSUB liga lookups" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub_liga_only_on_arab_script!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTArabOnly", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st", ["FallbackLigatureSTArabOnly"],
        shaping: :latin_ligatures
      )

    assert [{:text_at, x, 700, "st", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 applies GSUB ligatures across non-latin scripts with shaping: :gsub_ligatures" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub_liga_only_on_arab_script!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTArabOnly", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st", ["FallbackLigatureSTArabOnly"],
        shaping: :gsub_ligatures
      )

    assert [{:text_at, x, 700, "ﬆ", {"FallbackLigatureSTArabOnly", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 applies GPOS kerning after GSUB ligature shaping when both modes are enabled" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_kerning_path = write_test_ttf_ligature_st_with_gsub_and_gpos_kerning_x!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTKerningX", ligature_kerning_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st★", ["FallbackLigatureSTKerningX"],
        shaping: :gsub_ligatures,
        kerning: :gpos
      )

    assert [
             {:text_at, x1, 700, "ﬆ", {"FallbackLigatureSTKerningX", 12}},
             {:text_at, x2, 700, "★", {"FallbackLigatureSTKerningX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_kerning_path)
  end

  test "text_at_rotated_with_fallback/7 applies GPOS kerning after GSUB ligature shaping when both modes are enabled" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_kerning_path = write_test_ttf_ligature_st_with_gsub_and_gpos_kerning_x!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTKerningX", ligature_kerning_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_rotated_with_fallback(
        50,
        700,
        20,
        "st★",
        ["FallbackLigatureSTKerningX"],
        shaping: :gsub_ligatures,
        kerning: :gpos
      )

    assert [
             {:text_at_rotated, x1, 700, 20, "ﬆ", {"FallbackLigatureSTKerningX", 12}},
             {:text_at_rotated, x2, 700, 20, "★", {"FallbackLigatureSTKerningX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_kerning_path)
  end

  test "text_at_rotated_with_fallback/7 applies GSUB ligatures across non-latin scripts with shaping: :gsub_ligatures" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub_liga_only_on_arab_script!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTArabOnly", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_rotated_with_fallback(50, 700, 20, "st", ["FallbackLigatureSTArabOnly"],
        shaping: :gsub_ligatures
      )

    assert [
             {:text_at_rotated, x, 700, 20, "ﬆ", {"FallbackLigatureSTArabOnly", 12}}
           ] = pdf.operations

    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/6 keeps GSUB ligature disabled when liga feature is missing in shaping: :gsub_ligatures" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_path = write_test_ttf_ligature_st_with_gsub_liga_without_lookup!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTNoLigaLookup", ligature_path)
      |> Tincture.set_font("PrimaryASCII", 12)
      |> Tincture.text_at_with_fallback(50, 700, "st", ["FallbackLigatureSTNoLigaLookup"],
        shaping: :gsub_ligatures
      )

    assert [{:text_at, x, 700, "st", {"PrimaryASCII", 12}}] = pdf.operations
    assert_in_delta x, 50.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_path)
  end

  test "text_at_with_fallback/5 prefers latn script over arab script for GPOS kern lookups" do
    primary_path = write_test_ttf_primary_x!()
    kerning_path = write_test_ttf_gpos_kerning_av_only_on_arab_script!()

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.register_ttf_font("FallbackKerningAVArabOnly", kerning_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", ["FallbackKerningAVArabOnly"])

    assert [
             {:text_at, x1, 700, "AV", {"FallbackKerningAVArabOnly", 12}},
             {:text_at, x2, 700, "X", {"PrimaryX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 63.2, 0.001

    File.rm(primary_path)
    File.rm(kerning_path)
  end

  test "text_at_with_fallback/6 rejects invalid shaping option" do
    primary_path = write_test_ttf_primary_ascii!()

    assert_raise ArgumentError,
                 "shaping option must be :off, :latin_ligatures, or :gsub_ligatures",
                 fn ->
                   Tincture.new()
                   |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
                   |> Tincture.set_font("PrimaryASCII", 12)
                   |> Tincture.text_at_with_fallback(50, 700, "fi", [], shaping: :full)
                 end

    File.rm(primary_path)
  end

  test "text_at_with_fallback/6 rejects invalid kerning option" do
    primary_path = write_test_ttf_primary_x!()

    assert_raise ArgumentError, "kerning option must be :off or :gpos", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_with_fallback(50, 700, "AVX", [], kerning: :full)
    end

    File.rm(primary_path)
  end

  test "text_at_rotated_with_fallback/7 rejects invalid kerning option" do
    primary_path = write_test_ttf_primary_x!()

    assert_raise ArgumentError, "kerning option must be :off or :gpos", fn ->
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryX", primary_path)
      |> Tincture.set_font("PrimaryX", 12)
      |> Tincture.text_at_rotated_with_fallback(50, 700, 20, "AVX", [], kerning: :full)
    end

    File.rm(primary_path)
  end

  test "set_metadata/2 stores title/author/keywords on pdf state" do
    pdf =
      Tincture.new()
      |> Tincture.set_metadata(
        title: "Quarterly Report",
        author: "Tincture",
        keywords: "pdf,elixir"
      )

    assert pdf.metadata == %{
             title: "Quarterly Report",
             author: "Tincture",
             keywords: "pdf,elixir"
           }
  end

  test "export/1 returns a structurally valid one-page pdf" do
    pdf_binary =
      Tincture.new()
      |> Tincture.export()

    assert is_binary(pdf_binary)
    assert String.starts_with?(pdf_binary, "%PDF-1.4")
    assert pdf_binary =~ "/Type /Catalog"
    assert pdf_binary =~ "/Type /Pages"
    assert pdf_binary =~ "/Type /Page"
    assert pdf_binary =~ "/Count 1"
    assert pdf_binary =~ "xref\n0 5\n"
    assert pdf_binary =~ "trailer\n<< /Size 5 /Root 1 0 R >>\n"
    assert pdf_binary =~ "startxref\n"
    assert String.ends_with?(pdf_binary, "%%EOF\n")
  end

  test "export/1 serializes multiple pages and page tree count" do
    pdf_binary =
      Tincture.new()
      |> Tincture.text_at(10, 700, "page one")
      |> Tincture.add_page()
      |> Tincture.text_at(10, 700, "page two")
      |> Tincture.export()

    assert pdf_binary =~ "/Count 2"
    assert length(Regex.scan(~r|/Type /Page /Parent|, pdf_binary)) == 2
    assert pdf_binary =~ "(page one) Tj"
    assert pdf_binary =~ "(page two) Tj"
  end

  test "export/1 serializes metadata as an Info object" do
    pdf_binary =
      Tincture.new()
      |> Tincture.set_metadata(
        title: "Q1 (Draft)",
        author: "A\\B",
        keywords: "finance,roadmap"
      )
      |> Tincture.export()

    assert pdf_binary =~ "/Info "
    assert pdf_binary =~ "/Title (Q1 \\(Draft\\))"
    assert pdf_binary =~ "/Author (A\\\\B)"
    assert pdf_binary =~ "/Keywords (finance,roadmap)"
  end

  test "add_bookmark/3 serializes outlines and destinations" do
    pdf_binary =
      Tincture.new()
      |> Tincture.text_at(10, 700, "page one")
      |> Tincture.add_page()
      |> Tincture.text_at(10, 700, "page two")
      |> Tincture.add_bookmark("Start", 1)
      |> Tincture.add_bookmark("Second", 2)
      |> Tincture.export()

    assert pdf_binary =~ "/Outlines "
    assert pdf_binary =~ "/Type /Outlines"
    assert pdf_binary =~ "/Title (Start)"
    assert pdf_binary =~ "/Title (Second)"
    assert pdf_binary =~ "/Dest [3 0 R /Fit]"
    assert pdf_binary =~ "/Dest [5 0 R /Fit]"
  end

  test "add_bookmark/3 rejects unknown page numbers" do
    assert_raise ArgumentError, "unknown page: 2", fn ->
      Tincture.new()
      |> Tincture.add_bookmark("Missing", 2)
    end
  end

  test "image_jpeg/6 embeds image object and paints it with a transform matrix" do
    path = write_test_jpeg!()

    pdf_binary =
      Tincture.new()
      |> Tincture.image_jpeg(72, 500, 144, 96, path)
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Filter /DCTDecode"
    assert pdf_binary =~ "/ColorSpace /DeviceRGB"
    assert pdf_binary =~ "/BitsPerComponent 8"
    assert pdf_binary =~ "/Width 1"
    assert pdf_binary =~ "/Height 1"
    assert pdf_binary =~ "/XObject << /Im1 "
    assert pdf_binary =~ "q\n144 0 0 96 72 500 cm\n/Im1 Do\nQ\n"

    File.rm(path)
  end

  test "image_png/6 embeds RGBA PNG with an SMask alpha image" do
    path = write_test_png!()

    pdf_binary =
      Tincture.new()
      |> Tincture.image_png(50, 600, 32, 32, path)
      |> Tincture.export()

    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Filter /FlateDecode"
    assert pdf_binary =~ "/ColorSpace /DeviceRGB"
    assert pdf_binary =~ "/SMask "
    assert pdf_binary =~ "/ColorSpace /DeviceGray"
    assert pdf_binary =~ "/XObject << /Im1 "
    assert pdf_binary =~ "q\n32 0 0 32 50 600 cm\n/Im1 Do\nQ\n"

    File.rm(path)
  end

  test "image_jpeg/6 rejects invalid JPEG payloads" do
    path = write_test_binary!(".jpg", <<"not-a-jpeg">>)

    assert_raise ArgumentError, "invalid JPEG file: #{path}", fn ->
      Tincture.new()
      |> Tincture.image_jpeg(0, 0, 10, 10, path)
    end

    File.rm(path)
  end

  test "image_png/6 rejects invalid PNG payloads" do
    path = write_test_binary!(".png", <<"not-a-png">>)

    assert_raise ArgumentError, "invalid PNG file: #{path}", fn ->
      Tincture.new()
      |> Tincture.image_png(0, 0, 10, 10, path)
    end

    File.rm(path)
  end

  test "image_jpeg/6 and image_png/6 reject unreadable files" do
    missing_jpg =
      Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.jpg")

    missing_png =
      Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.png")

    assert_raise ArgumentError, "unable to read JPEG file: #{missing_jpg}", fn ->
      Tincture.new()
      |> Tincture.image_jpeg(0, 0, 10, 10, missing_jpg)
    end

    assert_raise ArgumentError, "unable to read PNG file: #{missing_png}", fn ->
      Tincture.new()
      |> Tincture.image_png(0, 0, 10, 10, missing_png)
    end
  end

  test "export/1 uses page size in page MediaBox" do
    pdf_binary =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Tincture.export()

    assert pdf_binary =~ "/MediaBox [0 0 612 792]"
  end

  test "export/1 writes text stream and font resources" do
    pdf_binary =
      Tincture.new()
      |> Tincture.set_font("Times-Roman", 16)
      |> Tincture.text_at(50, 700, "Hello (PDF)")
      |> Tincture.export()

    assert pdf_binary =~
             "/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >> >>"

    assert pdf_binary =~ "BT"
    assert pdf_binary =~ "/F1 16 Tf"
    assert pdf_binary =~ "50 700 Td"
    assert pdf_binary =~ "(Hello \\(PDF\\)) Tj"
    assert pdf_binary =~ "ET"
  end

  test "export/1 maps multiple fonts to distinct font resources" do
    pdf_binary =
      Tincture.new()
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(50, 700, "Hello")
      |> Tincture.set_font("Times-Roman", 10)
      |> Tincture.text_at(50, 680, "World")
      |> Tincture.export()

    assert pdf_binary =~ "/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    assert pdf_binary =~ "/F2 << /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>"
    assert pdf_binary =~ "/F1 12 Tf"
    assert pdf_binary =~ "/F2 10 Tf"
  end

  test "export/1 encodes unicode glyphs as UTF-16BE hex text strings" do
    pdf_binary =
      Tincture.new()
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(50, 700, "Snowman ☃")
      |> Tincture.export()

    assert pdf_binary =~ "<#{utf16be_hex_with_bom("Snowman ☃")}> Tj"
  end

  test "export/1 encodes unicode metadata and bookmark titles as UTF-16BE hex strings" do
    pdf_binary =
      Tincture.new()
      |> Tincture.text_at(10, 700, "page one")
      |> Tincture.set_metadata(title: "你好世界")
      |> Tincture.add_bookmark("Résumé", 1)
      |> Tincture.export()

    assert pdf_binary =~ "/Title <#{utf16be_hex_with_bom("你好世界")}>"
    assert pdf_binary =~ "/Title <#{utf16be_hex_with_bom("Résumé")}>"
  end

  test "line/5 appends draw operations and exports stroke commands" do
    pdf =
      Tincture.new()
      |> Tincture.line(50, 695, 200, 695)

    assert pdf.operations == [{:line, 50, 695, 200, 695}]

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "50 695 m\n200 695 l\nS\n"
  end

  test "rectangle/5 appends draw operations and exports rectangle commands" do
    pdf =
      Tincture.new()
      |> Tincture.rectangle(20, 600, 120, 40)

    assert pdf.operations == [{:rectangle, 20, 600, 120, 40}]

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "20 600 120 40 re\nS\n"
  end

  test "set_stroke_color/2 and set_fill_color/2 export rgb color operators" do
    pdf_binary =
      Tincture.new()
      |> Tincture.set_stroke_color({1, 0, 0})
      |> Tincture.set_fill_color({0, 1, 0})
      |> Tincture.export()

    assert pdf_binary =~ "1 0 0 RG\n"
    assert pdf_binary =~ "0 1 0 rg\n"
  end

  test "circle/4 appends operation and exports bezier circle path" do
    pdf =
      Tincture.new()
      |> Tincture.circle(100, 200, 30)

    assert pdf.operations == [{:circle, 100, 200, 30}]

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "130 200 m\n"
    assert length(Regex.scan(~r/ c\n/, pdf_binary)) == 4
    assert pdf_binary =~ "S\n"
  end

  test "path ops export move/line/bezier and stroke commands" do
    pdf =
      Tincture.new()
      |> Tincture.move_to(10, 10)
      |> Tincture.line_to(40, 10)
      |> Tincture.bezier(50, 10, 50, 40, 40, 40)
      |> Tincture.stroke()

    assert pdf.operations == [
             {:move_to, 10, 10},
             {:line_to, 40, 10},
             {:bezier, 50, 10, 50, 40, 40, 40},
             :stroke
           ]

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "10 10 m\n"
    assert pdf_binary =~ "40 10 l\n"
    assert pdf_binary =~ "50 10 50 40 40 40 c\n"
    assert pdf_binary =~ "S\n"
  end

  test "save_state/1 and restore_state/1 export q/Q operators" do
    pdf_binary =
      Tincture.new()
      |> Tincture.save_state()
      |> Tincture.set_stroke_color({0, 0, 1})
      |> Tincture.restore_state()
      |> Tincture.export()

    assert pdf_binary =~ "q\n"
    assert pdf_binary =~ "0 0 1 RG\n"
    assert pdf_binary =~ "Q\n"
  end

  test "line style controls export w/J/j/d operators" do
    pdf_binary =
      Tincture.new()
      |> Tincture.set_line_width(2.5)
      |> Tincture.set_line_cap(1)
      |> Tincture.set_line_join(2)
      |> Tincture.set_dash([3, 2], 1)
      |> Tincture.export()

    assert pdf_binary =~ "2.5 w\n"
    assert pdf_binary =~ "1 J\n"
    assert pdf_binary =~ "2 j\n"
    assert pdf_binary =~ "[3 2] 1 d\n"
  end

  test "fill/1 and clip/1 export f and W n operators" do
    pdf =
      Tincture.new()
      |> Tincture.move_to(10, 10)
      |> Tincture.line_to(40, 10)
      |> Tincture.line_to(40, 40)
      |> Tincture.fill()
      |> Tincture.move_to(50, 50)
      |> Tincture.line_to(80, 50)
      |> Tincture.line_to(80, 80)
      |> Tincture.clip()

    assert pdf.operations == [
             {:move_to, 10, 10},
             {:line_to, 40, 10},
             {:line_to, 40, 40},
             :fill,
             {:move_to, 50, 50},
             {:line_to, 80, 50},
             {:line_to, 80, 80},
             :clip
           ]

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "f\n"
    assert pdf_binary =~ "W\nn\n"
  end

  test "fill_even_odd/1, clip_even_odd/1, and set_miter_limit/2 export f*, W* n, and M operators" do
    pdf =
      Tincture.new()
      |> Tincture.set_miter_limit(7.5)
      |> Tincture.move_to(10, 10)
      |> Tincture.line_to(40, 10)
      |> Tincture.line_to(40, 40)
      |> Tincture.fill_even_odd()
      |> Tincture.move_to(50, 50)
      |> Tincture.line_to(80, 50)
      |> Tincture.line_to(80, 80)
      |> Tincture.clip_even_odd()

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "7.5 M\n"
    assert pdf_binary =~ "f*\n"
    assert pdf_binary =~ "W*\nn\n"
  end

  test "text_paragraph/6 renders wrapped text lines at positioned coordinates" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    pdf =
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 30, line_height: 14)

    assert [
             {:text_at, 50.0, 700.0, "one", {"Courier", 10}},
             {:text_at, 50.0, 686.0, "two", {"Courier", 10}},
             {:text_at, 50.0, 672.0, "three", {"Courier", 10}}
           ] = pdf.operations
  end

  test "text_paragraph/6 renders justified gaps by x positioning words" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    pdf =
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 60, align: :justified)

    assert [
             {:text_at, 50.0, 700.0, "one", {"Courier", 10}},
             {:text_at, 92.0, 700.0, "two", {"Courier", 10}},
             {:text_at, 50.0, 688.0, "three", {"Courier", 10}}
           ] = pdf.operations
  end

  test "text_paragraph/6 supports rotate option for laid-out words" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    pdf =
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 30, line_height: 14, rotate: 45)

    assert [
             {:text_at_rotated, 50.0, 700.0, 45, "one", {"Courier", 10}},
             {:text_at_rotated, 50.0, 686.0, 45, "two", {"Courier", 10}},
             {:text_at_rotated, 50.0, 672.0, 45, "three", {"Courier", 10}}
           ] = pdf.operations
  end

  test "text_paragraph/6 splits mixed-glyph words with fallback_fonts option" do
    fallback_path = write_test_ttf_fallback_snowman!()
    rich = RichText.from_plain("A☃B", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackSnowman", fallback_path)
      |> Tincture.text_paragraph(50, 700, rich, 300, fallback_fonts: ["FallbackSnowman"])

    assert [
             {:text_at, x1, 700.0, "A", {"Helvetica", 12}},
             {:text_at, x2, 700.0, "☃", {"FallbackSnowman", 12}},
             {:text_at, x3, 700.0, "B", {"Helvetica", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert x2 > x1
    assert x3 > x2

    File.rm(fallback_path)
  end

  test "text_paragraph/6 advances cursor by rendered fallback word width for subsequent words" do
    fallback_path = write_test_ttf_fallback_snowman_wide!()
    rich = RichText.from_plain("A☃B C", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackSnowmanWide", fallback_path)
      |> Tincture.text_paragraph(50, 700, rich, 300, fallback_fonts: ["FallbackSnowmanWide"])

    assert [
             {:text_at, _x_a, 700.0, "A", {"Helvetica", 12}},
             {:text_at, _x_snowman, 700.0, "☃", {"FallbackSnowmanWide", 12}},
             {:text_at, x_b, 700.0, "B", {"Helvetica", 12}},
             {:text_at, x_c, 700.0, "C", {"Helvetica", 12}}
           ] = pdf.operations

    expected_x_c =
      x_b +
        Tincture.Font.text_width("Helvetica", 12, "B") +
        Tincture.Font.text_width("Helvetica", 12, " ")

    assert_in_delta x_c, expected_x_c, 0.001

    File.rm(fallback_path)
  end

  test "text_paragraph/6 rotate mode advances cursor by rendered fallback word width for subsequent words" do
    fallback_path = write_test_ttf_fallback_snowman_wide!()
    rich = RichText.from_plain("A☃B C", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackSnowmanWide", fallback_path)
      |> Tincture.text_paragraph(50, 700, rich, 300,
        fallback_fonts: ["FallbackSnowmanWide"],
        rotate: 15
      )

    assert [
             {:text_at_rotated, _x_a, 700.0, 15, "A", {"Helvetica", 12}},
             {:text_at_rotated, _x_snowman, 700.0, 15, "☃", {"FallbackSnowmanWide", 12}},
             {:text_at_rotated, x_b, 700.0, 15, "B", {"Helvetica", 12}},
             {:text_at_rotated, x_c, 700.0, 15, "C", {"Helvetica", 12}}
           ] = pdf.operations

    expected_x_c =
      x_b +
        Tincture.Font.text_width("Helvetica", 12, "B") +
        Tincture.Font.text_width("Helvetica", 12, " ")

    assert_in_delta x_c, expected_x_c, 0.001

    File.rm(fallback_path)
  end

  test "text_paragraph/6 keeps variation-selector graphemes in a single fallback run" do
    fallback_path = write_test_ttf_with_cmap_format4_and14!()
    rich = RichText.from_plain("A☃️B", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackSnowmanVariation", fallback_path)
      |> Tincture.text_paragraph(50, 700, rich, 300, fallback_fonts: ["FallbackSnowmanVariation"])

    assert [
             {:text_at, _x1, 700.0, "A", {"Helvetica", 12}},
             {:text_at, _x2, 700.0, "☃️", {"FallbackSnowmanVariation", 12}},
             {:text_at, _x3, 700.0, "B", {"Helvetica", 12}}
           ] = pdf.operations

    File.rm(fallback_path)
  end

  test "text_paragraph/6 supports shaping: :latin_ligatures with fallback fonts" do
    ligature_path = write_test_ttf_ligature_fi!()
    rich = RichText.from_plain("office", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackLigatureFI", ligature_path)
      |> Tincture.text_paragraph(50, 700, rich, 300,
        fallback_fonts: ["FallbackLigatureFI"],
        shaping: :latin_ligatures
      )

    assert Enum.any?(pdf.operations, fn
             {:text_at, _x, 700.0, text, {"FallbackLigatureFI", 12}} -> text == "ﬁ"
             _ -> false
           end)

    File.rm(ligature_path)
  end

  test "text_paragraph/6 supports shaping: :gsub_ligatures with fallback fonts" do
    ligature_path = write_test_ttf_ligature_st_with_gsub_liga_only_on_arab_script!()
    rich = RichText.from_plain("st", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackLigatureSTArabOnly", ligature_path)
      |> Tincture.text_paragraph(50, 700, rich, 300,
        fallback_fonts: ["FallbackLigatureSTArabOnly"],
        shaping: :gsub_ligatures
      )

    assert Enum.any?(pdf.operations, fn
             {:text_at, _x, 700.0, text, {"FallbackLigatureSTArabOnly", 12}} -> text == "ﬆ"
             _ -> false
           end)

    File.rm(ligature_path)
  end

  test "text_paragraph/6 applies GPOS kerning after GSUB ligature shaping when both modes are enabled" do
    primary_path = write_test_ttf_primary_ascii!()
    ligature_kerning_path = write_test_ttf_ligature_st_with_gsub_and_gpos_kerning_x!()
    rich = RichText.from_plain("st★", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("PrimaryASCII", primary_path)
      |> Tincture.register_ttf_font("FallbackLigatureSTKerningX", ligature_kerning_path)
      |> Tincture.text_paragraph(50, 700, rich, 300,
        fallback_fonts: ["FallbackLigatureSTKerningX"],
        shaping: :gsub_ligatures,
        kerning: :gpos
      )

    assert [
             {:text_at, x1, 700.0, "ﬆ", {"FallbackLigatureSTKerningX", 12}},
             {:text_at, x2, 700.0, "★", {"FallbackLigatureSTKerningX", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001

    File.rm(primary_path)
    File.rm(ligature_kerning_path)
  end

  test "text_paragraph/6 applies opt-in embedded GPOS kerning to rendered fallback glyph positions" do
    kerning_path = write_test_ttf_gpos_kerning_snowman_star!()
    rich = RichText.from_plain("☃★X", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.register_ttf_font("FallbackKerningSnowmanStar", kerning_path)
      |> Tincture.text_paragraph(50, 700, rich, 300,
        fallback_fonts: ["FallbackKerningSnowmanStar"],
        kerning: :gpos
      )

    assert [
             {:text_at, x1, 700.0, "☃", {"FallbackKerningSnowmanStar", 12}},
             {:text_at, x2, 700.0, "★", {"FallbackKerningSnowmanStar", 12}},
             {:text_at, x3, 700.0, "X", {"Helvetica", 12}}
           ] = pdf.operations

    assert_in_delta x1, 50.0, 0.001
    assert_in_delta x2, 56.0, 0.001
    assert_in_delta x3, 62.0, 0.001

    File.rm(kerning_path)
  end

  test "text_paragraph/6 with bidi: :basic applies baseline RTL visual order" do
    rich = RichText.from_plain("ABC אב", font: "Helvetica", size: 12)

    pdf =
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 300, bidi: :basic)

    assert [
             {:text_at, _, 700.0, "ABC", {"Helvetica", 12}},
             {:text_at, _, 700.0, "בא", {"Helvetica", 12}}
           ] = pdf.operations
  end

  test "text_paragraph/6 rejects invalid bidi option" do
    rich = RichText.from_plain("ABC אב", font: "Helvetica", size: 12)

    assert_raise ArgumentError, "bidi option must be :off or :basic", fn ->
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 300, bidi: :full)
    end
  end

  test "text_paragraph/6 rejects invalid kerning option" do
    rich = RichText.from_plain("AVX", font: "Helvetica", size: 12)

    assert_raise ArgumentError, "kerning option must be :off or :gpos", fn ->
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 300, kerning: :full)
    end
  end

  test "text_paragraph/6 rejects non-numeric rotate option" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    assert_raise ArgumentError, "rotate option must be a number of degrees", fn ->
      Tincture.new()
      |> Tincture.text_paragraph(50, 700, rich, 60, rotate: :diagonal)
    end
  end

  test "text_at_rotated/5 emits rotated text matrix in content stream" do
    pdf =
      Tincture.new()
      |> Tincture.set_font("Times-Roman", 24)
      |> Tincture.text_at_rotated(100, 200, 45, "Rotation")

    assert [
             {:text_at_rotated, 100, 200, 45, "Rotation", {"Times-Roman", 24}}
           ] = pdf.operations

    pdf_binary = Tincture.export(pdf)

    assert pdf_binary =~ "/F1 24 Tf"
    assert pdf_binary =~ "0.7071067812 0.7071067812 -0.7071067812 0.7071067812 100 200 Tm"
    assert pdf_binary =~ "(Rotation) Tj"
  end

  defp write_test_jpeg! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.jpg")
    :ok = File.write(path, test_jpeg_binary())
    path
  end

  defp test_jpeg_binary do
    <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00,
      0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03,
      0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01,
      0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0x00, 0xFF, 0xD9>>
  end

  defp write_test_png! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.png")
    :ok = File.write(path, test_png_binary())
    path
  end

  defp test_png_binary do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>
    idat = :zlib.compress(<<0, 255, 0, 0, 128>>)

    signature <>
      png_chunk("IHDR", ihdr) <>
      png_chunk("IDAT", idat) <>
      png_chunk("IEND", "")
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32-big, type::binary-size(4), data::binary, crc::32-big>>
  end

  defp write_test_ttf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_binary())
    path
  end

  defp test_ttf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp test_ttf_missing_required_tables_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 1::16-big>>},
      {"hmtx", <<600::16-big, 0::16-signed-big>>}
    ])
  end

  defp write_test_otf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_binary())
    path
  end

  defp write_test_otf_with_metrics! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_metrics_binary())
    path
  end

  defp write_test_otf_with_cmap_cff_charstrings! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_cff_charstrings_binary())
    path
  end

  defp write_test_otf_with_cmap_cff_charstrings_tail! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_cff_charstrings_tail_binary())
    path
  end

  defp write_test_otf_with_cmap_cff_charstrings_real_top_dict! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_cff_charstrings_real_top_dict_binary())
    path
  end

  defp write_test_otf_with_cmap_cff_charstrings_private_tail! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_cff_charstrings_private_tail_binary())
    path
  end

  defp write_test_otf_with_cmap_cff_charstrings_fdarray_private_tail! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_cff_charstrings_fdarray_private_tail_binary())
    path
  end

  defp write_test_otf_with_cmap_format4! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_format4_binary())
    path
  end

  defp write_test_otf_with_cmap_format12! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cmap_format12_binary())
    path
  end

  defp write_test_otf_with_cff_family_name! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_family_name_binary())
    path
  end

  defp write_test_otf_with_cff_weight! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_weight_binary())
    path
  end

  defp write_test_otf_with_cff_stem_v! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_stem_v_binary())
    path
  end

  defp write_test_otf_with_cff_stem_h! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_stem_h_binary())
    path
  end

  defp write_test_otf_with_cff_force_bold! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_force_bold_binary())
    path
  end

  defp write_test_otf_with_cff_standard_weight! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_standard_weight_binary())
    path
  end

  defp write_test_otf_with_cff_full_name! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_full_name_binary())
    path
  end

  defp write_test_otf_with_cff_standard_family_name! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_standard_family_name_binary())
    path
  end

  defp write_test_otf_with_cff_font_name! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_font_name_binary())
    path
  end

  defp write_test_otf_with_cff_numeric_weight! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_numeric_weight_binary())
    path
  end

  defp write_test_otf_with_cff_hyphen_weight! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_cff_hyphen_weight_binary())
    path
  end

  defp write_test_otf_with_os2_fs_type! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_os2_fs_type_binary())
    path
  end

  defp write_test_otf_with_os2_no_subsetting! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_os2_no_subsetting_binary())
    path
  end

  defp write_test_otf_with_os2_bitmap_only! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_os2_bitmap_only_binary())
    path
  end

  defp write_test_otf_with_os2_bitmap_and_no_subsetting! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.otf")
    :ok = File.write(path, test_otf_with_os2_bitmap_and_no_subsetting_binary())
    path
  end

  defp test_otf_binary do
    <<"OTTO", 0, 1, 0, 16, 0, 1, 0, 0, 67, 70, 70, 32, 0, 0, 0, 0, 0, 0, 0, 24>>
  end

  defp test_otf_with_metrics_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 0}, {66, 1}])}
    ])
  end

  defp test_otf_with_cmap_cff_charstrings_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 1000::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])},
      {"CFF ",
       cff_table_with_charstrings([
         <<14>>,
         :binary.copy(<<139>>, 64),
         :binary.copy(<<140>>, 72),
         :binary.copy(<<141>>, 80)
       ])}
    ])
  end

  defp test_otf_with_cmap_cff_charstrings_tail_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 1000::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])},
      {"CFF ",
       cff_table_with_charstrings(
         [
           <<14>>,
           :binary.copy(<<139>>, 64),
           :binary.copy(<<140>>, 72),
           :binary.copy(<<141>>, 80)
         ],
         :binary.copy(<<0>>, 96)
       )}
    ])
  end

  defp test_otf_with_cmap_cff_charstrings_real_top_dict_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 1000::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])},
      {"CFF ",
       cff_table_with_charstrings(
         [
           <<14>>,
           :binary.copy(<<139>>, 64),
           :binary.copy(<<140>>, 72),
           :binary.copy(<<141>>, 80)
         ],
         <<>>,
         cff_top_dict_font_matrix_prefix()
       )}
    ])
  end

  defp test_otf_with_cmap_cff_charstrings_private_tail_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 1000::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])},
      {"CFF ",
       cff_table_with_charstrings_and_private_tail([
         <<14>>,
         :binary.copy(<<139>>, 64),
         :binary.copy(<<140>>, 72),
         :binary.copy(<<141>>, 80)
       ])}
    ])
  end

  defp test_otf_with_cmap_cff_charstrings_fdarray_private_tail_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 1000::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])},
      {"CFF ",
       cff_table_with_charstrings_and_fdarray_private_tail([
         <<14>>,
         :binary.copy(<<139>>, 64),
         :binary.copy(<<140>>, 72),
         :binary.copy(<<141>>, 80)
       ])}
    ])
  end

  defp test_otf_with_cmap_format4_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x2603, 1}])}
    ])
  end

  defp test_otf_with_cmap_format12_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format12([{0x1F600, 0x1F600, 1}])}
    ])
  end

  defp test_otf_with_cff_family_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_family_name("CFF Demo Family")}
    ])
  end

  defp test_otf_with_cff_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight("Bold")}
    ])
  end

  defp test_otf_with_cff_stem_v_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_stem_v(140)}
    ])
  end

  defp test_otf_with_cff_stem_h_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_stem_h(120)}
    ])
  end

  defp test_otf_with_cff_force_bold_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_force_bold()}
    ])
  end

  defp test_otf_with_cff_standard_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight_sid(384)}
    ])
  end

  defp test_otf_with_cff_full_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_full_name("CFF Demo FullName")}
    ])
  end

  defp test_otf_with_cff_standard_family_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_family_name_sid(388)}
    ])
  end

  defp test_otf_with_cff_font_name_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_font_name("CFF FontName Demo")}
    ])
  end

  defp test_otf_with_cff_numeric_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight("650")}
    ])
  end

  defp test_otf_with_cff_hyphen_weight_binary do
    build_otf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"CFF ", cff_table_with_weight("Semi-Bold")}
    ])
  end

  defp test_otf_with_os2_fs_type_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 2)

    build_otf([
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

  defp test_otf_with_os2_no_subsetting_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 0x0100)

    build_otf([
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

  defp test_otf_with_os2_bitmap_only_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 0x0200)

    build_otf([
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

  defp test_otf_with_os2_bitmap_and_no_subsetting_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 0x0300)

    build_otf([
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

  defp write_test_binary!(ext, bytes) do
    path =
      Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}#{ext}")

    :ok = File.write(path, bytes)
    path
  end

  defp utf16be_hex_with_bom(text) do
    text
    |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
    |> then(fn utf16 -> <<0xFE, 0xFF, utf16::binary>> end)
    |> Base.encode16(case: :upper)
  end

  defp write_test_ttf_with_cmap! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_binary())
    path
  end

  defp write_test_ttf_with_cmap_format4! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format4_binary())
    path
  end

  defp write_test_ttf_with_cmap_format6! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format6_binary())
    path
  end

  defp write_test_ttf_with_cmap_format12! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format12_binary())
    path
  end

  defp write_test_ttf_with_cmap_format13! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format13_binary())
    path
  end

  defp write_test_ttf_with_cmap_format10! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format10_binary())
    path
  end

  defp write_test_ttf_with_cmap_format2! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format2_binary())
    path
  end

  defp write_test_ttf_with_cmap_format8! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format8_binary())
    path
  end

  defp write_test_ttf_with_cmap_format14! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format14_binary())
    path
  end

  defp write_test_ttf_with_cmap_format4_and14! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format4_and14_binary())
    path
  end

  defp write_test_ttf_with_cmap_format12_ambiguous_surrogates! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_format12_ambiguous_surrogates_binary())
    path
  end

  defp write_test_ttf_with_loca_glyf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_loca_glyf_binary())
    path
  end

  defp write_test_ttf_with_cmap_loca_glyf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_cmap_loca_glyf_binary())
    path
  end

  defp write_test_ttf_with_composite_loca_glyf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_composite_loca_glyf_binary())
    path
  end

  defp write_test_ttf_with_composite_invalid_component_loca_glyf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_composite_invalid_component_loca_glyf_binary())
    path
  end

  defp write_test_ttf_with_composite_malformed_component_loca_glyf! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_composite_malformed_component_loca_glyf_binary())
    path
  end

  defp write_test_ttf_with_head_bbox! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_head_bbox_binary())
    path
  end

  defp write_test_ttf_with_os2! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_binary())
    path
  end

  defp write_test_ttf_with_line_gaps! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_line_gaps_binary())
    path
  end

  defp write_test_ttf_with_os2_win_fallback! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_win_fallback_binary())
    path
  end

  defp write_test_ttf_with_os2_selection! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_selection_binary())
    path
  end

  defp write_test_ttf_with_os2_oblique_selection! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_oblique_selection_binary())
    path
  end

  defp write_test_ttf_with_os2_fs_type! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_fs_type_binary())
    path
  end

  defp write_test_ttf_with_os2_no_subsetting! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_no_subsetting_binary())
    path
  end

  defp write_test_ttf_with_os2_bitmap_only! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_bitmap_only_binary())
    path
  end

  defp write_test_ttf_with_os2_bitmap_and_no_subsetting! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_bitmap_and_no_subsetting_binary())
    path
  end

  defp write_test_ttf_with_os2_avg_width! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_avg_width_binary())
    path
  end

  defp write_test_ttf_with_os2_default_char! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_default_char_binary())
    path
  end

  defp write_test_ttf_with_os2_break_char! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_break_char_binary())
    path
  end

  defp write_test_ttf_with_os2_char_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_char_range_binary())
    path
  end

  defp write_test_ttf_with_os2_panose! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_panose_binary())
    path
  end

  defp write_test_ttf_with_os2_weight! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_os2_weight_binary())
    path
  end

  defp write_test_ttf_with_post_italic! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_post_italic_binary())
    path
  end

  defp write_test_ttf_with_post_fixed_pitch! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_post_fixed_pitch_binary())
    path
  end

  defp write_test_ttf_with_name_table! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_name_table_binary())
    path
  end

  defp write_test_ttf_with_head_bold! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_head_bold_binary())
    path
  end

  defp write_test_ttf_with_hhea_advance_width_max! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_with_hhea_advance_width_max_binary())
    path
  end

  defp write_test_ttf_primary_ascii! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_primary_ascii_binary())
    path
  end

  defp write_test_ttf_fallback_snowman! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_fallback_snowman_binary())
    path
  end

  defp write_test_ttf_fallback_snowman_wide! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_fallback_snowman_wide_binary())
    path
  end

  defp write_test_ttf_primary_x! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_primary_x_binary())
    path
  end

  defp write_test_ttf_ligature_fi! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_fi_binary())
    path
  end

  defp write_test_ttf_ligature_fi_with_gsub_no_liga! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_fi_with_gsub_no_liga_binary())
    path
  end

  defp write_test_ttf_ligature_fi_with_gsub_no_latn! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_fi_with_gsub_no_latn_binary())
    path
  end

  defp write_test_ttf_ligature_fi_max_context_1! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_fi_max_context_1_binary())
    path
  end

  defp write_test_ttf_ligature_st_with_gsub! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_st_with_gsub_binary())
    path
  end

  defp write_test_ttf_single_substitution_a_to_b_with_gsub! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_single_substitution_a_to_b_with_gsub_binary())
    path
  end

  defp write_test_ttf_single_substitution_a_to_b_with_rlig_gsub! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_single_substitution_a_to_b_with_rlig_gsub_binary())
    path
  end

  defp write_test_ttf_ligature_st_with_gsub_liga_without_lookup! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_st_with_gsub_liga_without_lookup_binary())
    path
  end

  defp write_test_ttf_ligature_st_with_gsub_default_langsys_without_lookup! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_st_with_gsub_default_langsys_without_lookup_binary())
    path
  end

  defp write_test_ttf_ligature_st_with_gsub_liga_only_on_arab_script! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_st_with_gsub_liga_only_on_arab_script_binary())
    path
  end

  defp write_test_ttf_ligature_st_with_gsub_and_gpos_kerning_x! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_ligature_st_with_gsub_and_gpos_kerning_x_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_value2! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_value2_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_oversized! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_oversized_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_coverage_mismatch! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_coverage_mismatch_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_truncated! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_truncated_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_a_combining_v! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_a_combining_v_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_snowman_star! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_snowman_star_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx_oversized! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_oversized_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx_invalid_class_counts! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_invalid_class_counts_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx_truncated_records! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_truncated_records_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx_invalid_class_def_offsets! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_invalid_class_def_offsets_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx_expansion_oversized! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_expansion_oversized_binary())
    path
  end

  defp write_test_ttf_gpos_class_kerning_avx_classdef_oversized! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_class_kerning_avx_classdef_oversized_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_kern_without_lookup! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_kern_without_lookup_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_default_langsys_without_lookup! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_default_langsys_without_lookup_binary())
    path
  end

  defp write_test_ttf_gpos_kerning_av_only_on_arab_script! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_gpos_kerning_av_only_on_arab_script_binary())
    path
  end

  defp write_test_ttf_no_cmap_greek_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_greek_range_binary())
    path
  end

  defp write_test_ttf_no_cmap_zero_ranges! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_zero_ranges_binary())
    path
  end

  defp write_test_ttf_no_cmap_cyrillic_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_cyrillic_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_greek_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_greek_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_hebrew_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_hebrew_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_arabic_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_arabic_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_thai_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_thai_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_turkish_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_turkish_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_baltic_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_baltic_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_vietnamese_codepage! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_vietnamese_codepage_binary())
    path
  end

  defp write_test_ttf_no_cmap_cyrillic_unicode_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_cyrillic_unicode_range_binary())
    path
  end

  defp write_test_ttf_no_cmap_hebrew_unicode_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_hebrew_unicode_range_binary())
    path
  end

  defp write_test_ttf_no_cmap_arabic_unicode_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_arabic_unicode_range_binary())
    path
  end

  defp write_test_ttf_no_cmap_armenian_unicode_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_armenian_unicode_range_binary())
    path
  end

  defp write_test_ttf_no_cmap_devanagari_unicode_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_devanagari_unicode_range_binary())
    path
  end

  defp write_test_ttf_no_cmap_thai_unicode_range! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_no_cmap_thai_unicode_range_binary())
    path
  end

  defp write_test_ttf_latin1_e_acute! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_latin1_e_acute_binary())
    path
  end

  defp write_test_ttf_cyrillic_zh! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_cyrillic_zh_binary())
    path
  end

  defp write_test_ttf_greek_omega! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_greek_omega_binary())
    path
  end

  defp write_test_ttf_hebrew_alef! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_hebrew_alef_binary())
    path
  end

  defp write_test_ttf_arabic_alef! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_arabic_alef_binary())
    path
  end

  defp write_test_ttf_armenian_ayb! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_armenian_ayb_binary())
    path
  end

  defp write_test_ttf_devanagari_a! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_devanagari_a_binary())
    path
  end

  defp write_test_ttf_thai_ko_kai! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_thai_ko_kai_binary())
    path
  end

  defp write_test_ttf_turkish_g_breve! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_turkish_g_breve_binary())
    path
  end

  defp write_test_ttf_baltic_g_cedilla! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_baltic_g_cedilla_binary())
    path
  end

  defp write_test_ttf_vietnamese_o_horn! do
    path = Path.join(System.tmp_dir!(), "tincture_test_#{System.unique_integer([:positive])}.ttf")
    :ok = File.write(path, test_ttf_vietnamese_o_horn_binary())
    path
  end

  defp test_ttf_with_cmap_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 0}, {66, 1}])}
    ])
  end

  defp test_ttf_with_cmap_format4_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{9731, 1}, {9733, 2}])}
    ])
  end

  defp test_ttf_with_cmap_format6_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format6(9731, [1, 2])}
    ])
  end

  defp test_ttf_with_cmap_format12_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 6::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big, 0::16-signed-big, 0::16-signed-big, 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format12([{0x1F600, 0x1F600, 1}])}
    ])
  end

  defp test_ttf_with_cmap_format13_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format13([{0x2603, 0x2605, 2}])}
    ])
  end

  defp test_ttf_with_cmap_format10_binary do
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

  defp test_ttf_with_cmap_format2_binary do
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

  defp test_ttf_with_cmap_format8_binary do
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

  defp test_ttf_with_cmap_format14_binary do
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

  defp test_ttf_with_cmap_format4_and14_binary do
    cmap =
      cmap_merge_subtables([
        {3, 1, cmap_subtable(cmap_format4([{0x2603, 1}]))},
        {0, 5, cmap_subtable(cmap_format14(0xFE0F, [{0x2603, 2}]))}
      ])

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap}
    ])
  end

  defp test_ttf_with_cmap_format12_ambiguous_surrogates_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 6::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 650::16-big,
         0::16-signed-big, 0::16-signed-big, 0::16-signed-big, 0::16-signed-big, 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format12([{0x1F600, 0x1F600, 1}, {0x1F601, 0x1F601, 2}])}
    ])
  end

  defp test_ttf_with_loca_glyf_binary do
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

  defp test_ttf_with_cmap_loca_glyf_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 2}])},
      {"loca", <<0::16-big, 5::16-big, 10::16-big, 35::16-big, 35::16-big>>},
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
         750::16-signed-big,
         1::16-signed-big,
         0::16-signed-big,
         -30::16-signed-big,
         900::16-signed-big,
         820::16-signed-big,
         0::size(40)-unit(8)
       >>}
    ])
  end

  defp test_ttf_with_composite_loca_glyf_binary do
    glyph0 =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -20::16-signed-big,
        500::16-signed-big,
        700::16-signed-big
      >>

    glyph1_composite =
      <<
        -1::16-signed-big,
        0::16-signed-big,
        -20::16-signed-big,
        500::16-signed-big,
        700::16-signed-big,
        1::16-big,
        2::16-big,
        0::16-signed-big,
        0::16-signed-big
      >>

    glyph2 =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -10::16-signed-big,
        700::16-signed-big,
        760::16-signed-big
      >>

    glyph3_unused =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -30::16-signed-big,
        900::16-signed-big,
        820::16-signed-big,
        0::size(80)-unit(8)
      >>

    glyph4_unused =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -40::16-signed-big,
        920::16-signed-big,
        900::16-signed-big,
        0::size(120)-unit(8)
      >>

    offsets = [
      0,
      byte_size(glyph0),
      byte_size(glyph0) + byte_size(glyph1_composite),
      byte_size(glyph0) + byte_size(glyph1_composite) + byte_size(glyph2),
      byte_size(glyph0) + byte_size(glyph1_composite) + byte_size(glyph2) +
        byte_size(glyph3_unused),
      byte_size(glyph0) + byte_size(glyph1_composite) + byte_size(glyph2) +
        byte_size(glyph3_unused) +
        byte_size(glyph4_unused)
    ]

    loca =
      offsets
      |> Enum.map(&div(&1, 2))
      |> pack_u16()

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 5::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 950::16-big, 0::16-signed-big, 980::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 3}])},
      {"loca", loca},
      {"glyf",
       <<glyph0::binary, glyph1_composite::binary, glyph2::binary, glyph3_unused::binary,
         glyph4_unused::binary>>}
    ])
  end

  defp test_ttf_with_composite_invalid_component_loca_glyf_binary do
    glyph0 =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -20::16-signed-big,
        500::16-signed-big,
        700::16-signed-big
      >>

    glyph1_composite_invalid =
      <<
        -1::16-signed-big,
        0::16-signed-big,
        -20::16-signed-big,
        500::16-signed-big,
        700::16-signed-big,
        0x0000::16-big,
        10::16-big,
        0::16-signed-big,
        0::16-signed-big
      >>

    glyph2 =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -10::16-signed-big,
        700::16-signed-big,
        760::16-signed-big
      >>

    glyph3_unused =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -30::16-signed-big,
        900::16-signed-big,
        820::16-signed-big,
        0::size(80)-unit(8)
      >>

    glyph4_unused =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -40::16-signed-big,
        920::16-signed-big,
        900::16-signed-big,
        0::size(120)-unit(8)
      >>

    offsets = [
      0,
      byte_size(glyph0),
      byte_size(glyph0) + byte_size(glyph1_composite_invalid),
      byte_size(glyph0) + byte_size(glyph1_composite_invalid) + byte_size(glyph2),
      byte_size(glyph0) + byte_size(glyph1_composite_invalid) + byte_size(glyph2) +
        byte_size(glyph3_unused),
      byte_size(glyph0) + byte_size(glyph1_composite_invalid) + byte_size(glyph2) +
        byte_size(glyph3_unused) +
        byte_size(glyph4_unused)
    ]

    loca =
      offsets
      |> Enum.map(&div(&1, 2))
      |> pack_u16()

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 5::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 950::16-big, 0::16-signed-big, 980::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 3}])},
      {"loca", loca},
      {"glyf",
       <<glyph0::binary, glyph1_composite_invalid::binary, glyph2::binary, glyph3_unused::binary,
         glyph4_unused::binary>>}
    ])
  end

  defp test_ttf_with_composite_malformed_component_loca_glyf_binary do
    glyph0 =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -20::16-signed-big,
        500::16-signed-big,
        700::16-signed-big
      >>

    glyph1_composite_malformed =
      <<
        -1::16-signed-big,
        0::16-signed-big,
        -20::16-signed-big,
        500::16-signed-big,
        700::16-signed-big,
        0x0000::16-big,
        2::16-big
      >>

    glyph2 =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -10::16-signed-big,
        700::16-signed-big,
        760::16-signed-big
      >>

    glyph3_unused =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -30::16-signed-big,
        900::16-signed-big,
        820::16-signed-big,
        0::size(80)-unit(8)
      >>

    glyph4_unused =
      <<
        1::16-signed-big,
        0::16-signed-big,
        -40::16-signed-big,
        920::16-signed-big,
        900::16-signed-big,
        0::size(120)-unit(8)
      >>

    offsets = [
      0,
      byte_size(glyph0),
      byte_size(glyph0) + byte_size(glyph1_composite_malformed),
      byte_size(glyph0) + byte_size(glyph1_composite_malformed) + byte_size(glyph2),
      byte_size(glyph0) + byte_size(glyph1_composite_malformed) + byte_size(glyph2) +
        byte_size(glyph3_unused),
      byte_size(glyph0) + byte_size(glyph1_composite_malformed) + byte_size(glyph2) +
        byte_size(glyph3_unused) +
        byte_size(glyph4_unused)
    ]

    loca =
      offsets
      |> Enum.map(&div(&1, 2))
      |> pack_u16()

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 5::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 900::16-big,
         0::16-signed-big, 950::16-big, 0::16-signed-big, 980::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 1}, {66, 3}])},
      {"loca", loca},
      {"glyf",
       <<glyph0::binary, glyph1_composite_malformed::binary, glyph2::binary,
         glyph3_unused::binary, glyph4_unused::binary>>}
    ])
  end

  defp test_ttf_with_head_bbox_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(16)-unit(8), -50::16-signed-big,
         -200::16-signed-big, 1100::16-signed-big, 900::16-signed-big, 0::size(10)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp test_ttf_with_os2_binary do
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

  defp test_ttf_with_line_gaps_binary do
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

  defp test_ttf_with_os2_weight_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(30)-unit(8), 0::16-signed-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::size(26)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(780, -220, 880, 240, 510, 730, 900, 3, 0)}
    ])
  end

  defp test_ttf_with_os2_win_fallback_binary do
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

  defp test_ttf_with_os2_selection_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(0, 0, 840, 260, 510, 730, 500, 5, 33)}
    ])
  end

  defp test_ttf_with_os2_oblique_selection_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2_table(0, 0, 840, 260, 510, 730, 500, 5, 512)}
    ])
  end

  defp test_ttf_with_os2_fs_type_binary do
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

  defp test_ttf_with_os2_no_subsetting_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 0x0100)

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

  defp test_ttf_with_os2_bitmap_only_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 0x0200)

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

  defp test_ttf_with_os2_bitmap_and_no_subsetting_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(8, 0x0300)

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

  defp test_ttf_with_os2_avg_width_binary do
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

  defp test_ttf_with_os2_default_char_binary do
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

  defp test_ttf_with_os2_break_char_binary do
    os2 =
      os2_table(780, -220, 880, 240, 510, 730, 700, 3, 0)
      |> write_u16_at(90, 300)
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

  defp test_ttf_with_os2_char_range_binary do
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
      {"cmap", cmap_format0([{65, 0}, {66, 1}])},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_with_os2_panose_binary do
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

  defp test_ttf_with_post_italic_binary do
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

  defp test_ttf_with_post_fixed_pitch_binary do
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

  defp test_ttf_with_head_bold_binary do
    build_ttf([
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(24)-unit(8), 1::16-big, 0::16-big,
         0::16-signed-big, 0::16-signed-big, 0::16-signed-big>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>}
    ])
  end

  defp test_ttf_with_name_table_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"name", name_table("Demo Family")}
    ])
  end

  defp test_ttf_with_hhea_advance_width_max_binary do
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

  defp test_ttf_primary_ascii_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{65, 0}, {66, 1}])}
    ])
  end

  defp test_ttf_fallback_snowman_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{9731, 1}])}
    ])
  end

  defp test_ttf_fallback_snowman_wide_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 1200::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{9731, 1}])}
    ])
  end

  defp test_ttf_primary_x_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?X, 1}])}
    ])
  end

  defp test_ttf_ligature_fi_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 900::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0xFB01, 1}])}
    ])
  end

  defp test_ttf_ligature_fi_with_gsub_no_liga_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 900::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0xFB01, 1}])},
      {"GSUB", layout_table_with_script_and_feature("latn", "kern")}
    ])
  end

  defp test_ttf_ligature_fi_with_gsub_no_latn_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 900::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0xFB01, 1}])},
      {"GSUB", layout_table_with_script_and_feature("arab", "liga")}
    ])
  end

  defp test_ttf_ligature_fi_max_context_1_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u16_at(94, 1)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 900::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0xFB01, 1}])},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_ligature_st_with_gsub_binary do
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

  defp test_ttf_single_substitution_a_to_b_with_gsub_binary do
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

  defp test_ttf_single_substitution_a_to_b_with_rlig_gsub_binary do
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

  defp test_ttf_ligature_st_with_gsub_liga_without_lookup_binary do
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

  defp test_ttf_ligature_st_with_gsub_default_langsys_without_lookup_binary do
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

  defp test_ttf_ligature_st_with_gsub_liga_only_on_arab_script_binary do
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

  defp test_ttf_ligature_st_with_gsub_and_gpos_kerning_x_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 5::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?s, 1}, {?t, 2}, {0xFB06, 3}, {0x2605, 4}])},
      {"GSUB", gsub_ligature_table(1, [2], 3)},
      {"GPOS", gpos_pair_adjustment_table(3, 4, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_value2_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_value2(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_oversized(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_coverage_mismatch_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 600::16-big,
         0::16-signed-big, 500::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?B, 2}, {?V, 3}, {?X, 4}])},
      {"GPOS", gpos_pair_adjustment_table_coverage_mismatch(1, 2, 3, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_truncated_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_truncated(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_a_combining_v_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 4::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 5::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 0::16-big,
         0::16-signed-big, 500::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {0x0301, 3}, {?X, 4}])},
      {"GPOS", gpos_pair_adjustment_table(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_snowman_star_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x2603, 1}, {0x2605, 2}])},
      {"GPOS", gpos_pair_adjustment_table(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_class_kerning_avx_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table(1, 2, 3, -100, -50)}
    ])
  end

  defp test_ttf_gpos_class_kerning_avx_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_oversized(1, 2, 3, -100, -50)}
    ])
  end

  defp test_ttf_gpos_class_kerning_avx_invalid_class_counts_binary do
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

  defp test_ttf_gpos_class_kerning_avx_truncated_records_binary do
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

  defp test_ttf_gpos_class_kerning_avx_invalid_class_def_offsets_binary do
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

  defp test_ttf_gpos_class_kerning_avx_expansion_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap",
       cmap_format12([{?A, ?A, 1}, {?B, ?B, 4}, {?V, ?V, 2}, {?X, ?X, 3}, {0x1000, 0x370F, 2}])},
      {"GPOS", gpos_pair_adjustment_class_table_expansion_oversized(1, 4, -100)}
    ])
  end

  defp test_ttf_gpos_class_kerning_avx_classdef_oversized_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_class_table_classdef_oversized(1, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_kern_without_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_without_kern_lookup_link(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_default_langsys_without_lookup_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_default_langsys_without_lookup(1, 2, -100)}
    ])
  end

  defp test_ttf_gpos_kerning_av_only_on_arab_script_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 3::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 4::16-big>>},
      {"hmtx",
       <<600::16-big, 0::16-signed-big, 600::16-big, 0::16-signed-big, 500::16-big,
         0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{?A, 1}, {?V, 2}, {?X, 3}])},
      {"GPOS", gpos_pair_adjustment_table_kern_lookup_only_on_arab_script(1, 2, -100)}
    ])
  end

  defp test_ttf_no_cmap_greek_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 128)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_zero_ranges_binary do
    os2 = os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_cyrillic_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 4)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_greek_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 8)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_hebrew_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 32)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_arabic_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 64)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_thai_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(82, 1)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_turkish_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 16)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_baltic_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 128)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_vietnamese_codepage_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(78, 256)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_cyrillic_unicode_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 512)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_hebrew_unicode_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 2048)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_arabic_unicode_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 8192)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_armenian_unicode_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 1024)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_devanagari_unicode_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 32_768)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_no_cmap_thai_unicode_range_binary do
    os2 =
      os2_table(0, 0, 0, 0, 0, 0, 500, 5, 0)
      |> write_u32_at(42, 16_777_216)

    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"OS/2", os2}
    ])
  end

  defp test_ttf_latin1_e_acute_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format0([{233, 1}])}
    ])
  end

  defp test_ttf_cyrillic_zh_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x0416, 1}])}
    ])
  end

  defp test_ttf_greek_omega_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x03A9, 1}])}
    ])
  end

  defp test_ttf_hebrew_alef_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x05D0, 1}])}
    ])
  end

  defp test_ttf_arabic_alef_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x0627, 1}])}
    ])
  end

  defp test_ttf_armenian_ayb_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x0531, 1}])}
    ])
  end

  defp test_ttf_devanagari_a_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x0905, 1}])}
    ])
  end

  defp test_ttf_thai_ko_kai_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x0E01, 1}])}
    ])
  end

  defp test_ttf_turkish_g_breve_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x011F, 1}])}
    ])
  end

  defp test_ttf_baltic_g_cedilla_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x0122, 1}])}
    ])
  end

  defp test_ttf_vietnamese_o_horn_binary do
    build_ttf([
      {"head", <<0::size(18)-unit(8), 1000::16-big, 0::size(34)-unit(8)>>},
      {"hhea", <<0::32-big, 0::size(30)-unit(8), 2::16-big>>},
      {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
      {"hmtx",
       <<500::16-big, 0::16-signed-big, 700::16-big, 0::16-signed-big, 0::16-signed-big>>},
      {"cmap", cmap_format4([{0x01A1, 1}])}
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

  defp cmap_subtable(
         <<_version::16-big, _num_tables::16-big, _platform::16-big, _encoding::16-big,
           offset::32-big, data::binary>>
       ) do
    binary_part(data, offset - 12, byte_size(data) - (offset - 12))
  end

  defp cmap_merge_subtables(subtables) when is_list(subtables) do
    num_tables = length(subtables)
    header_size = 4 + num_tables * 8

    {records, subtable_data, _next_offset} =
      Enum.reduce(subtables, {[], [], header_size}, fn {platform, encoding, subtable},
                                                       {rec_acc, data_acc, next_offset} ->
        record = <<platform::16-big, encoding::16-big, next_offset::32-big>>
        {rec_acc ++ [record], data_acc ++ [subtable], next_offset + byte_size(subtable)}
      end)

    IO.iodata_to_binary([
      <<0::16-big, num_tables::16-big>>,
      records,
      subtable_data
    ])
  end

  defp extract_cid_to_gid_value(pdf_binary, cid)
       when is_binary(pdf_binary) and is_integer(cid) and cid >= 0 do
    ref_prefix = "/CIDToGIDMap "
    {ref_idx, _} = :binary.match(pdf_binary, ref_prefix)
    ref_start = ref_idx + byte_size(ref_prefix)
    rest = binary_part(pdf_binary, ref_start, byte_size(pdf_binary) - ref_start)
    {object_id, _rest_after_id} = parse_leading_integer(rest)
    object_marker = Integer.to_string(object_id) <> " 0 obj"
    {obj_idx, _} = :binary.match(pdf_binary, object_marker)
    stream_search = binary_part(pdf_binary, obj_idx, byte_size(pdf_binary) - obj_idx)
    {stream_idx, _} = :binary.match(stream_search, "stream\n")
    data_start = obj_idx + stream_idx + byte_size("stream\n")
    tail = binary_part(pdf_binary, data_start, byte_size(pdf_binary) - data_start)
    {endstream_idx, _} = :binary.match(tail, "\nendstream")
    compressed = binary_part(pdf_binary, data_start, endstream_idx)
    data = :zlib.uncompress(compressed)
    offset = cid * 2
    <<_prefix::binary-size(offset), gid::16-big, _::binary>> = data
    gid
  end

  defp parse_leading_integer(binary) when is_binary(binary) do
    {digits, rest} =
      binary
      |> :binary.bin_to_list()
      |> Enum.split_while(fn ch -> ch >= ?0 and ch <= ?9 end)

    if digits == [] do
      raise "expected leading integer in binary payload"
    end

    {digits |> to_string() |> String.to_integer(), IO.iodata_to_binary(rest)}
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
    class_1_record_1 = <<0::16-signed-big, -100::16-signed-big, -50::16-signed-big>>
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

  defp name_table(family_name) do
    encoded = :unicode.characters_to_binary(family_name, :utf8, {:utf16, :big})
    string_offset = 6 + 12

    record =
      <<3::16-big, 1::16-big, 0x0409::16-big, 1::16-big, byte_size(encoded)::16-big, 0::16-big>>

    <<0::16-big, 1::16-big, string_offset::16-big, record::binary, encoded::binary>>
  end

  defp cff_table_with_family_name(family_name) when is_binary(family_name) do
    cff_table_with_family_name_sid(391, [family_name])
  end

  defp cff_table_with_weight(weight_name) when is_binary(weight_name) do
    cff_table_with_weight_sid(391, [weight_name])
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

  defp cff_table_with_full_name(full_name) when is_binary(full_name) do
    cff_table_with_full_name_sid(391, [full_name])
  end

  defp cff_table_with_font_name(font_name) when is_binary(font_name) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(391),
        <<12, 38>>
      ])

    IO.iodata_to_binary([
      <<1, 0, 4, 1>>,
      cff_index([<<"A">>]),
      cff_index([top_dict]),
      cff_index([font_name]),
      <<0::16-big>>
    ])
  end

  defp cff_table_with_family_name_sid(sid, string_index_entries \\ [])
       when is_integer(sid) and sid >= 0 and sid <= 65_535 and is_list(string_index_entries) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(sid),
        <<3>>
      ])

    IO.iodata_to_binary([
      <<1, 0, 4, 1>>,
      cff_index([<<"A">>]),
      cff_index([top_dict]),
      cff_index(string_index_entries),
      <<0::16-big>>
    ])
  end

  defp cff_table_with_weight_sid(sid, string_index_entries \\ [])
       when is_integer(sid) and sid >= 0 and sid <= 65_535 and is_list(string_index_entries) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(sid),
        <<4>>
      ])

    IO.iodata_to_binary([
      <<1, 0, 4, 1>>,
      cff_index([<<"A">>]),
      cff_index([top_dict]),
      cff_index(string_index_entries),
      <<0::16-big>>
    ])
  end

  defp cff_table_with_full_name_sid(sid, string_index_entries)
       when is_integer(sid) and sid >= 0 and sid <= 65_535 and is_list(string_index_entries) do
    top_dict =
      IO.iodata_to_binary([
        cff_shortint(sid),
        <<2>>
      ])

    IO.iodata_to_binary([
      <<1, 0, 4, 1>>,
      cff_index([<<"A">>]),
      cff_index([top_dict]),
      cff_index(string_index_entries),
      <<0::16-big>>
    ])
  end

  defp cff_table_with_charstrings(charstrings, trailing_bytes \\ <<>>, top_dict_prefix \\ <<>>)
       when is_list(charstrings) and charstrings != [] and is_binary(trailing_bytes) and
              is_binary(top_dict_prefix) do
    normalized_charstrings =
      Enum.map(charstrings, fn charstring ->
        case charstring do
          data when is_binary(data) and byte_size(data) > 0 ->
            data

          _ ->
            <<14>>
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
      charstrings_index,
      trailing_bytes
    ])
  end

  defp cff_table_with_charstrings_and_private_tail(charstrings)
       when is_list(charstrings) and charstrings != [] do
    normalized_charstrings =
      Enum.map(charstrings, fn charstring ->
        case charstring do
          data when is_binary(data) and byte_size(data) > 0 ->
            data

          _ ->
            <<14>>
        end
      end)

    header = <<1, 0, 4, 1>>
    name_index = cff_index([<<"A">>])
    string_index = cff_index([])
    global_subr_index = cff_index([])
    private_marker = "PRIV"
    private_bytes = <<private_marker::binary, 0::size(80)-unit(8)>>
    private_size = byte_size(private_bytes)
    private_gap = 32

    placeholder_top_dict =
      IO.iodata_to_binary([
        cff_shortint(0),
        <<17>>,
        cff_shortint(private_size),
        cff_shortint(0),
        <<18>>
      ])

    placeholder_top_dict_index = cff_index([placeholder_top_dict])

    charstrings_offset =
      byte_size(header) +
        byte_size(name_index) +
        byte_size(placeholder_top_dict_index) +
        byte_size(string_index) +
        byte_size(global_subr_index)

    charstrings_index = cff_index(normalized_charstrings)
    private_offset = charstrings_offset + byte_size(charstrings_index) + private_gap

    top_dict =
      IO.iodata_to_binary([
        cff_shortint(charstrings_offset),
        <<17>>,
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
      charstrings_index,
      :binary.copy(<<0>>, private_gap),
      private_bytes
    ])
  end

  defp cff_table_with_charstrings_and_fdarray_private_tail(charstrings)
       when is_list(charstrings) and charstrings != [] do
    normalized_charstrings =
      Enum.map(charstrings, fn charstring ->
        case charstring do
          data when is_binary(data) and byte_size(data) > 0 ->
            data

          _ ->
            <<14>>
        end
      end)

    header = <<1, 0, 4, 1>>
    name_index = cff_index([<<"A">>])
    string_index = cff_index([])
    global_subr_index = cff_index([])
    fd_private_marker = "FDPV"
    fd_private_bytes = <<fd_private_marker::binary, 0::size(96)-unit(8)>>
    fd_private_size = byte_size(fd_private_bytes)
    fdarray_gap = 32
    fd_private_gap = 24

    placeholder_top_dict =
      IO.iodata_to_binary([
        cff_shortint(0),
        <<17>>,
        cff_shortint(0),
        <<12, 36>>
      ])

    placeholder_top_dict_index = cff_index([placeholder_top_dict])

    charstrings_offset =
      byte_size(header) +
        byte_size(name_index) +
        byte_size(placeholder_top_dict_index) +
        byte_size(string_index) +
        byte_size(global_subr_index)

    charstrings_index = cff_index(normalized_charstrings)
    fdarray_offset = charstrings_offset + byte_size(charstrings_index) + fdarray_gap

    placeholder_font_dict =
      IO.iodata_to_binary([
        cff_shortint(fd_private_size),
        cff_shortint(0),
        <<18>>
      ])

    placeholder_fdarray_index = cff_index([placeholder_font_dict])
    fd_private_offset = fdarray_offset + byte_size(placeholder_fdarray_index) + fd_private_gap

    font_dict =
      IO.iodata_to_binary([
        cff_shortint(fd_private_size),
        cff_shortint(fd_private_offset),
        <<18>>
      ])

    fdarray_index = cff_index([font_dict])

    top_dict =
      IO.iodata_to_binary([
        cff_shortint(charstrings_offset),
        <<17>>,
        cff_shortint(fdarray_offset),
        <<12, 36>>
      ])

    top_dict_index = cff_index([top_dict])

    IO.iodata_to_binary([
      header,
      name_index,
      top_dict_index,
      string_index,
      global_subr_index,
      charstrings_index,
      :binary.copy(<<0>>, fdarray_gap),
      fdarray_index,
      :binary.copy(<<0>>, fd_private_gap),
      fd_private_bytes
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

  defp cff_top_dict_font_matrix_prefix do
    IO.iodata_to_binary([
      cff_real_0_001(),
      <<139, 139>>,
      cff_real_0_001(),
      <<139, 139, 12, 7>>
    ])
  end

  defp cff_real_0_001 do
    <<30, 0x0A, 0x00, 0x1F>>
  end

  defp cid_to_gid_map_data_from_pdf!(pdf_binary) when is_binary(pdf_binary) do
    case Regex.run(~r/\/CIDToGIDMap\s+(\d+)\s+0\s+R/, pdf_binary) do
      [_, object_id_str] ->
        object_id = String.to_integer(object_id_str)
        object_marker = "\n#{object_id} 0 obj\n<< /Length "

        case :binary.match(pdf_binary, object_marker) do
          {marker_pos, _marker_len} ->
            length_start = marker_pos + byte_size(object_marker)
            tail = binary_part(pdf_binary, length_start, byte_size(pdf_binary) - length_start)

            case Regex.run(~r/^(\d+)/, tail) do
              [_, length_str] ->
                length = String.to_integer(length_str)
                after_length = length_start + byte_size(length_str)
                stream_marker = ">>\nstream\n"

                case :binary.match(pdf_binary, stream_marker, [
                       {:scope, {after_length, byte_size(pdf_binary) - after_length}}
                     ]) do
                  {stream_pos, _stream_len} ->
                    stream_start = stream_pos + byte_size(stream_marker)
                    dict_data_start = marker_pos + byte_size("\n#{object_id} 0 obj\n<<")
                    dict_data_size = stream_pos - dict_data_start

                    dict_data =
                      if dict_data_size >= 0 do
                        binary_part(pdf_binary, dict_data_start, dict_data_size)
                      else
                        ""
                      end

                    if stream_start + length <= byte_size(pdf_binary) do
                      stream_data = binary_part(pdf_binary, stream_start, length)

                      if String.contains?(dict_data, "/Filter /FlateDecode") do
                        :zlib.uncompress(stream_data)
                      else
                        stream_data
                      end
                    else
                      flunk("expected CIDToGIDMap stream payload to fit within PDF binary")
                    end

                  :nomatch ->
                    flunk("expected CIDToGIDMap object stream marker")
                end

              _ ->
                flunk("expected numeric /Length for CIDToGIDMap object")
            end

          :nomatch ->
            flunk("expected CIDToGIDMap object definition")
        end

      _ ->
        flunk("expected CIDToGIDMap object reference in CID font dictionary")
    end
  end

  defp cid_to_gid_for_cid!(cid_to_gid_map_data, cid)
       when is_binary(cid_to_gid_map_data) and is_integer(cid) and cid >= 0 do
    offset = cid * 2

    if offset + 2 <= byte_size(cid_to_gid_map_data) do
      <<_prefix::binary-size(offset), gid::16-big, _rest::binary>> = cid_to_gid_map_data
      gid
    else
      flunk("expected CID #{cid} entry in CIDToGIDMap stream")
    end
  end

  defp font_file_length1_from_pdf!(pdf_binary) when is_binary(pdf_binary) do
    case Regex.run(~r/\/Length1\s+(\d+)/, pdf_binary) do
      [_, length_str] ->
        String.to_integer(length_str)

      _ ->
        flunk("expected PDF to include /Length1 for embedded FontFile stream")
    end
  end

  defp font_file_data_from_pdf!(pdf_binary) when is_binary(pdf_binary) do
    marker = "/Length1 "

    case :binary.match(pdf_binary, marker) do
      {length_pos, _marker_size} ->
        digits_start = length_pos + byte_size(marker)
        tail = binary_part(pdf_binary, digits_start, byte_size(pdf_binary) - digits_start)

        case Regex.run(~r/^(\d+)/, tail) do
          [_, length_str] ->
            length = String.to_integer(length_str)
            after_digits = digits_start + byte_size(length_str)
            stream_marker = ">>\nstream\n"

            case :binary.match(pdf_binary, stream_marker, [
                   {:scope, {after_digits, byte_size(pdf_binary) - after_digits}}
                 ]) do
              {stream_marker_pos, _} ->
                stream_data_start = stream_marker_pos + byte_size(stream_marker)

                if stream_data_start + length <= byte_size(pdf_binary) do
                  binary_part(pdf_binary, stream_data_start, length)
                else
                  flunk("expected /Length1 stream payload to fit within PDF binary")
                end

              :nomatch ->
                flunk("expected /Length1 stream marker in embedded FontFile object")
            end

          _ ->
            flunk("expected numeric /Length1 value in embedded FontFile object")
        end

      :nomatch ->
        flunk("expected embedded FontFile object with /Length1")
    end
  end

  defp sfnt_table_offsets!(
         <<_sfnt_version::binary-size(4), num_tables::16-big, _search_range::16-big,
           _entry_selector::16-big, _range_shift::16-big, rest::binary>>
       ) do
    required_record_bytes = num_tables * 16

    if byte_size(rest) < required_record_bytes do
      flunk("expected complete SFNT table directory")
    else
      <<record_bytes::binary-size(required_record_bytes), _::binary>> = rest

      for <<_tag::binary-size(4), _checksum::32-big, offset::32-big,
            _length::32-big <- record_bytes>> do
        offset
      end
    end
  end

  defp sfnt_table_offsets!(_invalid_sfnt), do: flunk("expected valid SFNT header")

  defp sfnt_head_check_sum_adjustment!(sfnt_binary) when is_binary(sfnt_binary) do
    records = sfnt_table_records!(sfnt_binary)

    case Enum.find(records, fn {tag, _checksum, _offset, _length} -> tag == "head" end) do
      {"head", _checksum, offset, length}
      when is_integer(offset) and is_integer(length) and length >= 12 and
             offset + length <= byte_size(sfnt_binary) ->
        <<_prefix::binary-size(offset + 8), check_sum_adjustment::32-big, _rest::binary>> =
          sfnt_binary

        check_sum_adjustment

      _ ->
        flunk("expected SFNT to include a complete head table with checkSumAdjustment")
    end
  end

  defp sfnt_checksum(sfnt_binary) when is_binary(sfnt_binary) do
    padding =
      case rem(byte_size(sfnt_binary), 4) do
        0 -> 0
        remainder -> 4 - remainder
      end

    padded =
      if padding == 0 do
        sfnt_binary
      else
        <<sfnt_binary::binary, 0::size(padding)-unit(8)>>
      end

    sfnt_checksum_words(padded, 0)
  end

  defp sfnt_checksum_words(<<>>, sum), do: sum

  defp sfnt_checksum_words(<<word::32-big, rest::binary>>, sum) do
    sfnt_checksum_words(rest, rem(sum + word, 4_294_967_296))
  end

  defp sfnt_table_records!(
         <<_sfnt_version::binary-size(4), num_tables::16-big, _search_range::16-big,
           _entry_selector::16-big, _range_shift::16-big, rest::binary>>
       ) do
    required_record_bytes = num_tables * 16

    if byte_size(rest) < required_record_bytes do
      flunk("expected complete SFNT table directory")
    else
      <<record_bytes::binary-size(required_record_bytes), _::binary>> = rest

      for <<tag::binary-size(4), checksum::32-big, offset::32-big,
            length::32-big <- record_bytes>> do
        {tag, checksum, offset, length}
      end
    end
  end

  defp sfnt_table_records!(_invalid_sfnt), do: flunk("expected valid SFNT header")

  defp sfnt_table_data_by_tag!(sfnt_binary, tag)
       when is_binary(sfnt_binary) and is_binary(tag) and byte_size(tag) == 4 do
    case Enum.find(sfnt_table_records!(sfnt_binary), fn {record_tag, _checksum, _offset, _length} ->
           record_tag == tag
         end) do
      {^tag, _checksum, offset, length}
      when is_integer(offset) and is_integer(length) and offset >= 0 and length >= 0 and
             offset + length <= byte_size(sfnt_binary) ->
        binary_part(sfnt_binary, offset, length)

      _ ->
        flunk("expected SFNT table #{inspect(tag)}")
    end
  end

  defp ttf_loca_offsets_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    head_table = sfnt_table_data_by_tag!(sfnt_binary, "head")
    loca_table = sfnt_table_data_by_tag!(sfnt_binary, "loca")

    case head_table do
      <<_prefix::binary-size(50), index_to_loc_format::16-signed-big, _::binary>>
      when index_to_loc_format in [0, 1] ->
        case index_to_loc_format do
          0 ->
            decode_u16_big_values!(loca_table)
            |> Enum.map(&(&1 * 2))

          1 ->
            decode_u32_big_values!(loca_table)
        end

      _ ->
        flunk("expected head.indexToLocFormat in [0,1]")
    end
  end

  defp cff_charstring_lengths_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    cff_table = sfnt_table_data_by_tag!(sfnt_binary, "CFF ")

    case cff_table do
      <<_major::8, _minor::8, header_size::8, _off_size::8, _::binary>>
      when header_size >= 4 and byte_size(cff_table) >= header_size ->
        <<_header::binary-size(header_size), body::binary>> = cff_table

        with {:ok, {_name_index, after_name, _name_size}} <- parse_cff_index_for_test(body),
             {:ok, {top_dict_index, after_top_dict, _top_dict_size}} <-
               parse_cff_index_for_test(after_name),
             {:ok, {_string_index, after_string, _string_size}} <-
               parse_cff_index_for_test(after_top_dict),
             {:ok, {_global_subr_index, _after_global, _global_size}} <-
               parse_cff_index_for_test(after_string),
             [top_dict | _] <- top_dict_index,
             {:ok, charstrings_offset} <- cff_top_dict_operator_operand_for_test(top_dict, 17),
             true <- charstrings_offset < byte_size(cff_table),
             cff_tail <-
               binary_part(
                 cff_table,
                 charstrings_offset,
                 byte_size(cff_table) - charstrings_offset
               ),
             {:ok, {charstrings, _rest, _size}} <- parse_cff_index_for_test(cff_tail) do
          Enum.map(charstrings, &byte_size/1)
        else
          _ -> flunk("expected parseable CFF CharStrings INDEX")
        end

      _ ->
        flunk("expected valid CFF table")
    end
  end

  defp cff_private_offset_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    {_private_size, private_offset, _private_marker} =
      cff_private_dict_info_from_sfnt!(sfnt_binary)

    private_offset
  end

  defp cff_private_marker_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    {_private_size, _private_offset, private_marker} =
      cff_private_dict_info_from_sfnt!(sfnt_binary)

    private_marker
  end

  defp cff_private_dict_info_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    cff_table = sfnt_table_data_by_tag!(sfnt_binary, "CFF ")

    case cff_table do
      <<_major::8, _minor::8, header_size::8, _off_size::8, _::binary>>
      when header_size >= 4 and byte_size(cff_table) >= header_size ->
        <<_header::binary-size(header_size), body::binary>> = cff_table

        with {:ok, {_name_index, after_name, _name_size}} <- parse_cff_index_for_test(body),
             {:ok, {top_dict_index, _after_top_dict, _top_dict_size}} <-
               parse_cff_index_for_test(after_name),
             [top_dict | _] <- top_dict_index,
             {:ok, operands} <- cff_top_dict_operands_for_test(top_dict, 18),
             [private_size, private_offset | _rest] <- operands,
             true <- is_integer(private_size) and private_size > 0,
             true <- is_integer(private_offset) and private_offset >= 0,
             true <- private_offset + private_size <= byte_size(cff_table),
             <<private_marker::binary-size(4), _::binary>> <-
               binary_part(cff_table, private_offset, private_size) do
          {private_size, private_offset, private_marker}
        else
          _ ->
            flunk("expected parseable CFF Private dict info")
        end

      _ ->
        flunk("expected valid CFF table")
    end
  end

  defp cff_fdarray_private_offset_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    {_private_size, private_offset, _private_marker} =
      cff_fdarray_private_dict_info_from_sfnt!(sfnt_binary)

    private_offset
  end

  defp cff_fdarray_private_marker_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    {_private_size, _private_offset, private_marker} =
      cff_fdarray_private_dict_info_from_sfnt!(sfnt_binary)

    private_marker
  end

  defp cff_fdarray_private_dict_info_from_sfnt!(sfnt_binary) when is_binary(sfnt_binary) do
    cff_table = sfnt_table_data_by_tag!(sfnt_binary, "CFF ")

    case cff_table do
      <<_major::8, _minor::8, header_size::8, _off_size::8, _::binary>>
      when header_size >= 4 and byte_size(cff_table) >= header_size ->
        <<_header::binary-size(header_size), body::binary>> = cff_table

        with {:ok, {_name_index, after_name, _name_size}} <- parse_cff_index_for_test(body),
             {:ok, {top_dict_index, _after_top_dict, _top_dict_size}} <-
               parse_cff_index_for_test(after_name),
             [top_dict | _] <- top_dict_index,
             {:ok, fdarray_offset} <-
               cff_top_dict_escaped_operator_operand_for_test(top_dict, 36),
             true <- fdarray_offset >= 0 and fdarray_offset < byte_size(cff_table),
             fdarray_tail <-
               binary_part(
                 cff_table,
                 fdarray_offset,
                 byte_size(cff_table) - fdarray_offset
               ),
             {:ok, {font_dicts, _after_fdarray, _fdarray_size}} <-
               parse_cff_index_for_test(fdarray_tail),
             [font_dict | _] <- font_dicts,
             {:ok, operands} <- cff_top_dict_operands_for_test(font_dict, 18),
             [private_size, private_offset | _rest] <- operands,
             true <- is_integer(private_size) and private_size > 0,
             true <- is_integer(private_offset) and private_offset >= 0,
             true <- private_offset + private_size <= byte_size(cff_table),
             <<private_marker::binary-size(4), _::binary>> <-
               binary_part(cff_table, private_offset, private_size) do
          {private_size, private_offset, private_marker}
        else
          _ ->
            flunk("expected parseable CFF FDArray Private dict info")
        end

      _ ->
        flunk("expected valid CFF table")
    end
  end

  defp parse_cff_index_for_test(<<count::16-big, rest::binary>>) do
    if count == 0 do
      {:ok, {[], rest, 2}}
    else
      case rest do
        <<off_size::8, offset_data::binary>> when off_size >= 1 and off_size <= 4 ->
          offset_count = count + 1
          offset_bytes = offset_count * off_size

          if byte_size(offset_data) < offset_bytes do
            :error
          else
            <<offset_bytes_bin::binary-size(offset_bytes), objects_and_rest::binary>> =
              offset_data

            with {:ok, offsets} <- decode_cff_offsets_for_test(offset_bytes_bin, off_size),
                 {:ok, objects, rest_after, objects_size} <-
                   parse_cff_index_objects_for_test(offsets, count, objects_and_rest) do
              {:ok, {objects, rest_after, 2 + 1 + offset_bytes + objects_size}}
            else
              _ -> :error
            end
          end

        _ ->
          :error
      end
    end
  end

  defp parse_cff_index_for_test(_invalid), do: :error

  defp decode_cff_offsets_for_test(offsets_bin, off_size)
       when is_binary(offsets_bin) and is_integer(off_size) and off_size >= 1 and off_size <= 4 do
    do_decode_cff_offsets_for_test(offsets_bin, off_size, [])
  end

  defp do_decode_cff_offsets_for_test(<<>>, _off_size, acc), do: {:ok, Enum.reverse(acc)}

  defp do_decode_cff_offsets_for_test(bin, off_size, acc) do
    if byte_size(bin) < off_size do
      :error
    else
      <<entry::binary-size(off_size), rest::binary>> = bin
      do_decode_cff_offsets_for_test(rest, off_size, [:binary.decode_unsigned(entry) | acc])
    end
  end

  defp parse_cff_index_objects_for_test(offsets, count, objects_and_rest)
       when is_list(offsets) and is_integer(count) and count > 0 and is_binary(objects_and_rest) do
    cond do
      length(offsets) != count + 1 ->
        :error

      hd(offsets) < 1 or List.last(offsets) < 1 ->
        :error

      not nondecreasing_list?(offsets) ->
        :error

      List.last(offsets) - 1 > byte_size(objects_and_rest) ->
        :error

      true ->
        objects_size = List.last(offsets) - 1
        <<objects_data::binary-size(objects_size), rest_after::binary>> = objects_and_rest

        objects =
          offsets
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [start_offset, end_offset] ->
            size = end_offset - start_offset
            binary_part(objects_data, start_offset - 1, size)
          end)

        {:ok, objects, rest_after, objects_size}
    end
  end

  defp parse_cff_index_objects_for_test(_offsets, _count, _objects_and_rest), do: :error

  defp cff_top_dict_operator_operand_for_test(dict, operator)
       when is_binary(dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_top_dict_for_operator_operand_for_test(dict, operator, [])
  end

  defp scan_cff_top_dict_for_operator_operand_for_test(<<>>, _operator, _operands), do: :error

  defp scan_cff_top_dict_for_operator_operand_for_test(
         <<12, _escaped::8, rest::binary>>,
         operator,
         _operands
       ) do
    scan_cff_top_dict_for_operator_operand_for_test(rest, operator, [])
  end

  defp scan_cff_top_dict_for_operator_operand_for_test(
         <<op::8, rest::binary>>,
         operator,
         operands
       )
       when op <= 21 do
    if op == operator do
      case Enum.reverse(operands) do
        [value | _] when is_integer(value) and value >= 0 -> {:ok, value}
        _ -> :error
      end
    else
      scan_cff_top_dict_for_operator_operand_for_test(rest, operator, [])
    end
  end

  defp scan_cff_top_dict_for_operator_operand_for_test(dict, operator, operands) do
    case parse_cff_number_for_test(dict) do
      {:ok, value, rest} ->
        scan_cff_top_dict_for_operator_operand_for_test(rest, operator, [value | operands])

      :error ->
        :error
    end
  end

  defp cff_top_dict_escaped_operator_operand_for_test(dict, escaped_operator)
       when is_binary(dict) and is_integer(escaped_operator) and escaped_operator >= 0 and
              escaped_operator <= 255 do
    scan_cff_top_dict_for_escaped_operator_operand_for_test(dict, escaped_operator, [])
  end

  defp scan_cff_top_dict_for_escaped_operator_operand_for_test(
         <<>>,
         _escaped_operator,
         _operands
       ),
       do: :error

  defp scan_cff_top_dict_for_escaped_operator_operand_for_test(
         <<12, escaped::8, rest::binary>>,
         escaped_operator,
         operands
       ) do
    if escaped == escaped_operator do
      case Enum.reverse(operands) do
        [value | _] when is_integer(value) and value >= 0 -> {:ok, value}
        _ -> :error
      end
    else
      scan_cff_top_dict_for_escaped_operator_operand_for_test(rest, escaped_operator, [])
    end
  end

  defp scan_cff_top_dict_for_escaped_operator_operand_for_test(
         <<op::8, rest::binary>>,
         escaped_operator,
         _operands
       )
       when op <= 21 do
    scan_cff_top_dict_for_escaped_operator_operand_for_test(rest, escaped_operator, [])
  end

  defp scan_cff_top_dict_for_escaped_operator_operand_for_test(
         dict,
         escaped_operator,
         operands
       ) do
    case parse_cff_number_for_test(dict) do
      {:ok, value, rest} ->
        scan_cff_top_dict_for_escaped_operator_operand_for_test(
          rest,
          escaped_operator,
          [value | operands]
        )

      :error ->
        :error
    end
  end

  defp cff_top_dict_operands_for_test(dict, operator)
       when is_binary(dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_top_dict_for_operands_list_for_test(dict, operator, [])
  end

  defp scan_cff_top_dict_for_operands_list_for_test(<<>>, _operator, _operands), do: :error

  defp scan_cff_top_dict_for_operands_list_for_test(
         <<12, _escaped::8, rest::binary>>,
         operator,
         _operands
       ) do
    scan_cff_top_dict_for_operands_list_for_test(rest, operator, [])
  end

  defp scan_cff_top_dict_for_operands_list_for_test(
         <<op::8, rest::binary>>,
         operator,
         operands
       )
       when op <= 21 do
    if op == operator do
      case Enum.reverse(operands) do
        [] -> :error
        values -> {:ok, values}
      end
    else
      scan_cff_top_dict_for_operands_list_for_test(rest, operator, [])
    end
  end

  defp scan_cff_top_dict_for_operands_list_for_test(dict, operator, operands) do
    case parse_cff_number_for_test(dict) do
      {:ok, value, rest} ->
        scan_cff_top_dict_for_operands_list_for_test(rest, operator, [value | operands])

      :error ->
        :error
    end
  end

  defp parse_cff_number_for_test(<<28, value::16-signed-big, rest::binary>>),
    do: {:ok, value, rest}

  defp parse_cff_number_for_test(<<29, value::32-signed-big, rest::binary>>),
    do: {:ok, value, rest}

  defp parse_cff_number_for_test(<<first::8, second::8, rest::binary>>)
       when first >= 247 and first <= 250 do
    {:ok, (first - 247) * 256 + second + 108, rest}
  end

  defp parse_cff_number_for_test(<<first::8, second::8, rest::binary>>)
       when first >= 251 and first <= 254 do
    {:ok, -((first - 251) * 256 + second + 108), rest}
  end

  defp parse_cff_number_for_test(<<value::8, rest::binary>>) when value >= 32 and value <= 246,
    do: {:ok, value - 139, rest}

  defp parse_cff_number_for_test(_), do: :error

  defp decode_u16_big_values!(bin) when is_binary(bin) and rem(byte_size(bin), 2) == 0 do
    for <<value::16-big <- bin>>, do: value
  end

  defp decode_u16_big_values!(_bin), do: flunk("expected 16-bit aligned binary")

  defp decode_u32_big_values!(bin) when is_binary(bin) and rem(byte_size(bin), 4) == 0 do
    for <<value::32-big <- bin>>, do: value
  end

  defp decode_u32_big_values!(_bin), do: flunk("expected 32-bit aligned binary")

  defp nondecreasing_list?([_single]), do: true
  defp nondecreasing_list?([]), do: true

  defp nondecreasing_list?([a, b | rest]) when a <= b do
    nondecreasing_list?([b | rest])
  end

  defp nondecreasing_list?(_), do: false

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
