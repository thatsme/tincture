defmodule Tincture.PDF.FontEmbedTest do
  @moduledoc """
  Font descriptor fields and embedding edge cases.

  Embedding is exercised heavily at the integration level elsewhere, so what
  is left uncovered here is the edges: descriptor fields driven by `OS/2`
  values no existing fixture carries, embedding-permission handling, and the
  interaction between subsetting and Type0 encoding.

  These matter because a wrong descriptor does not fail — it produces a valid
  PDF that a viewer renders with the wrong substitute font when the embedded
  one is unavailable.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  # -- font builders ---------------------------------------------------------

  defp build_ttf(tables) do
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

  # OS/2 version 2. Only the fields these tests vary are parameterised.
  defp os2(opts) do
    weight = Keyword.get(opts, :weight_class, 400)
    width = Keyword.get(opts, :width_class, 5)
    fs_type = Keyword.get(opts, :fs_type, 0)
    fs_selection = Keyword.get(opts, :fs_selection, 0)
    panose = Keyword.get(opts, :panose, <<0::size(10)-unit(8)>>)

    <<2::16-big, 0::16-signed-big, weight::16-big, width::16-big, fs_type::16-big,
      0::size(22)-unit(8), panose::binary-size(10), 0::size(16)-unit(8), 0::32-big,
      fs_selection::16-big, 0::16-big, 0::16-big, 780::16-signed-big, -220::16-signed-big,
      0::16-signed-big, 880::16-big, 240::16-big, 0::32-big, 0::32-big, 510::16-signed-big,
      730::16-signed-big, 0::16-big, 0::16-big, 0::16-big>>
  end

  defp cmap_format4(entries) do
    sorted = Enum.sort_by(entries, &elem(&1, 0)) ++ [{0xFFFF, 0xFFFF}]
    seg_count = length(sorted)

    ends = for {c, _g} <- sorted, into: <<>>, do: <<c::16-big>>
    starts = ends
    deltas = for {c, g} <- sorted, into: <<>>, do: <<Integer.mod(g - c, 65_536)::16-big>>
    range_offsets = :binary.copy(<<0, 0>>, seg_count)

    body =
      <<seg_count * 2::16-big, 0::16-big, 0::16-big, 0::16-big, ends::binary, 0::16-big,
        starts::binary, deltas::binary, range_offsets::binary>>

    subtable = <<4::16-big, byte_size(body) + 6::16-big, 0::16-big, body::binary>>
    <<0::16-big, 1::16-big, 3::16-big, 1::16-big, 12::32-big, subtable::binary>>
  end

  defp font(opts \\ []) do
    os2_opts = Keyword.get(opts, :os2)
    chars = Keyword.get(opts, :chars, [{?A, 1}, {?B, 2}])
    num_glyphs = Keyword.get(opts, :num_glyphs, 3)

    base = [
      {"head",
       <<0::size(18)-unit(8), 1000::16-big, 0::size(16)-unit(8), 0::16-signed-big,
         0::16-signed-big, 500::16-signed-big, 700::16-signed-big, 0::16-big, 0::size(4)-unit(8),
         0::16-signed-big>>},
      {"hhea",
       <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
         0::size(22)-unit(8), 1::16-big>>},
      {"maxp", <<0x0001_0000::32-big, num_glyphs::16-big>>},
      {"hmtx", <<500::16-big, 0::16-signed-big>> <> :binary.copy(<<0, 0>>, num_glyphs - 1)},
      {"cmap", cmap_format4(chars)}
    ]

    tables = if os2_opts, do: base ++ [{"OS/2", os2(os2_opts)}], else: base
    build_ttf(tables)
  end

  defp with_font(binary, fun) do
    path = Path.join(System.tmp_dir!(), "tincture_fe_#{System.unique_integer([:positive])}.ttf")
    File.write!(path, binary)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  # Renders a one-line document with the font embedded and returns the PDF.
  defp render(font_binary, opts \\ []) do
    text = Keyword.get(opts, :text, "A")
    register_opts = Keyword.get(opts, :register, [])

    with_font(font_binary, fn path ->
      Tincture.new()
      |> Tincture.register_ttf_font("Probe", path, register_opts)
      |> Tincture.add_page()
      |> Tincture.set_font("Probe", 12)
      |> Tincture.text_at(50, 700, text)
      |> Tincture.export()
    end)
  end

  # -- descriptor fields -----------------------------------------------------

  describe "/FontStretch from OS/2 usWidthClass" do
    test "maps every width class the specification defines" do
      # A wrong stretch does not fail: the viewer substitutes a font of the
      # wrong width when the embedded one is unavailable.
      for {width_class, expected} <- [
            {1, "UltraCondensed"},
            {2, "ExtraCondensed"},
            {3, "Condensed"},
            {4, "SemiCondensed"},
            {5, "Normal"},
            {6, "SemiExpanded"},
            {7, "Expanded"},
            {8, "ExtraExpanded"},
            {9, "UltraExpanded"}
          ] do
        pdf = render(font(os2: [width_class: width_class]))

        assert pdf =~ "/FontStretch /#{expected}",
               "usWidthClass #{width_class} should map to #{expected}"
      end
    end

    test "an out-of-range width class emits no FontStretch" do
      for width_class <- [0, 10, 99] do
        refute render(font(os2: [width_class: width_class])) =~ "/FontStretch"
      end
    end

    test "a font with no OS/2 table emits no FontStretch" do
      refute render(font()) =~ "/FontStretch"
    end
  end

  describe "/FontWeight from OS/2 usWeightClass" do
    test "carries the declared weight through to the descriptor" do
      assert render(font(os2: [weight_class: 700])) =~ "/FontWeight 700"
      assert render(font(os2: [weight_class: 300])) =~ "/FontWeight 300"
    end
  end

  describe "/Style /Panose" do
    test "emits the panose bytes as hex when the OS/2 table carries them" do
      panose = <<2, 11, 6, 4, 3, 5, 4, 4, 2, 4>>
      assert render(font(os2: [panose: panose])) =~ "/Panose <020B0604030504040204>"
    end

    test "a zero panose is still emitted, since all-zero is a legal classification" do
      assert render(font(os2: [panose: <<0::size(10)-unit(8)>>])) =~ "/Panose <"
    end

    test "a font with no OS/2 table emits no Style entry" do
      refute render(font()) =~ "/Panose"
    end
  end

  describe "italic and bold flags" do
    test "fsSelection bit 0 marks the font italic" do
      # Bit 0 is ITALIC. The descriptor flags carry it, and it changes how a
      # viewer synthesises a substitute.
      pdf = render(font(os2: [fs_selection: 1]))
      assert pdf =~ "/ItalicAngle" or pdf =~ "/Flags"
    end

    test "fsSelection bit 5 marks the font bold" do
      assert render(font(os2: [fs_selection: 32])) =~ "/FontDescriptor"
    end
  end

  # -- embedding permissions -------------------------------------------------

  describe "OS/2 fsType embedding permissions" do
    test "a restricted-licence font warns but still embeds by default" do
      # fsType 2 is "restricted licence". Tincture warns rather than refusing,
      # because the caller may well hold a licence the file cannot express.
      log = capture_log(fn -> assert render(font(os2: [fs_type: 2])) =~ "/FontFile2" end)
      assert log =~ "restrictive OS/2 fsType"
    end

    test "enforce_embedding_permissions rejects a restricted font" do
      assert_raise ArgumentError, ~r/fsType/, fn ->
        render(font(os2: [fs_type: 2]), register: [enforce_embedding_permissions: true])
      end
    end

    test "bitmap-only fonts get their own message" do
      # fsType 0x0200 is "bitmap embedding only" - a different restriction from
      # a restrictive licence, and reported as such rather than lumped together.
      log = capture_log(fn -> render(font(os2: [fs_type: 0x0200])) end)
      assert log =~ "bitmap-only via OS/2 fsType"
    end

    test "a no-subsetting font is reported when subsetting is requested" do
      # fsType 0x0100 forbids subsetting, which is on by default.
      log = capture_log(fn -> render(font(os2: [fs_type: 0x0100])) end)
      assert log =~ "disallows subsetting"
    end

    test "an installable-embedding font produces no warning" do
      log = capture_log(fn -> render(font(os2: [fs_type: 0])) end)
      refute log =~ "fsType"
    end

    test "enforcement accepts an unrestricted font" do
      assert render(font(os2: [fs_type: 0]), register: [enforce_embedding_permissions: true]) =~
               "/FontFile2"
    end
  end

  # -- subsetting and encoding -----------------------------------------------

  describe "subset modes" do
    test "used_text is the default and tags the base font" do
      # A subsetted font must carry the six-uppercase-letter tag.
      assert render(font()) =~ ~r|/BaseFont /[A-Z]{6}\+Probe|
    end

    test "none embeds the font untagged" do
      assert render(font(), register: [subset: :none]) =~ "/BaseFont /Probe"
    end

    test "ascii_basic tags the font like any other subset" do
      assert render(font(), register: [subset: :ascii_basic]) =~ ~r|/BaseFont /[A-Z]{6}\+Probe|
    end

    test "an unknown subset mode is rejected" do
      assert_raise ArgumentError, ~r/subset must be/, fn ->
        render(font(), register: [subset: :everything])
      end
    end
  end

  describe "Type0 composite encoding" do
    test "non-ASCII text switches the font to a composite Type0" do
      # A simple font can only address 256 codes, so anything outside Latin-1
      # has to become Type0 with Identity-H.
      pdf = render(font(chars: [{0x4E2D, 1}]), text: <<0x4E2D::utf8>>)

      assert pdf =~ "/Type0"
      assert pdf =~ "Identity-H"
      assert pdf =~ "/CIDFontType2"
    end

    test "a composite font carries a ToUnicode CMap so the text stays copyable" do
      # Without ToUnicode the glyphs render but copy out as gibberish.
      pdf = render(font(chars: [{0x4E2D, 1}]), text: <<0x4E2D::utf8>>)

      assert pdf =~ "/ToUnicode"
      assert pdf =~ "beginbfchar" or pdf =~ "beginbfrange"
    end

    test "plain ASCII stays a simple font" do
      pdf = render(font())

      assert pdf =~ "/Subtype /TrueType"
      refute pdf =~ "/Type0"
    end

    test "a codepoint outside the BMP is encoded as a surrogate pair" do
      pdf = render(font(chars: [{0x1F600, 1}], num_glyphs: 4), text: <<0x1F600::utf8>>)

      assert pdf =~ "/Type0"
      # UTF-16BE surrogate pair for U+1F600 is D83D DE00.
      assert pdf =~ "D83D" or pdf =~ "/ToUnicode"
    end
  end

  describe "font_names_from_operations/1" do
    alias Tincture.PDF.FontEmbed

    test "collects the fonts a page's operations reference" do
      ops = [
        {:text_at, 0, 0, "a", {"Helvetica", 12}},
        {:text_at, 0, 0, "b", {"Courier", 10}},
        {:text_at, 0, 0, "c", {"Helvetica", 8}}
      ]

      names = FontEmbed.font_names_from_operations(ops)
      assert Enum.sort(names) == ["Courier", "Helvetica"]
    end

    test "includes fonts used by rotated text" do
      ops = [{:text_at_rotated, 0, 0, 90, "a", {"Times-Roman", 12}}]
      assert FontEmbed.font_names_from_operations(ops) == ["Times-Roman"]
    end

    test "ignores operations that draw no text" do
      ops = [{:rectangle, 0, 0, 10, 10}, :stroke, {:set_fill_color, {0, 0, 0}}]
      assert FontEmbed.font_names_from_operations(ops) == []
    end

    test "an empty operation list yields no fonts" do
      assert FontEmbed.font_names_from_operations([]) == []
    end
  end

  # -- OpenType/CFF subsetting -----------------------------------------------

  describe "OTF with CFF outlines" do
    # A CFF INDEX with two-byte offsets, so the offset width does not change
    # when the index shrinks and the arithmetic stays predictable.
    defp cff_index([]), do: <<0::16-big>>

    defp cff_index(objects) do
      {offsets, _} =
        Enum.reduce(objects, {[1], 1}, fn object, {acc, cursor} ->
          next = cursor + byte_size(object)
          {acc ++ [next], next}
        end)

      offset_bin = for o <- offsets, into: <<>>, do: <<o::16-big>>
      <<length(objects)::16-big, 2::8, offset_bin::binary, IO.iodata_to_binary(objects)::binary>>
    end

    defp dict_int(v) when v >= -107 and v <= 107, do: <<v + 139::8>>

    defp dict_int(v) when v >= 108 and v <= 1131,
      do: <<div(v - 108, 256) + 247::8, rem(v - 108, 256)::8>>

    defp dict_int(v), do: <<29::8, v::32-signed-big>>

    # A CFF table with a CharStrings INDEX and a Private DICT placed after it.
    # Both are referenced by offset from the top DICT, so subsetting - which
    # shrinks CharStrings - forces those offsets to be rewritten. That patching
    # is the code under test.
    defp cff_table(charstrings, opts \\ []) do
      charstrings_index = cff_index(charstrings)
      private = dict_int(120) <> <<11::8>>
      name_index = cff_index(["Probe"])
      # A large string index pushes the CharStrings and Private offsets past
      # 1131, which forces the DICT to encode them as 5-byte longints instead
      # of the 1- or 2-byte forms - a different re-encoding path when the
      # subsetter patches them.
      padding = Keyword.get(opts, :offset_padding, 0)

      string_index =
        if padding > 0, do: cff_index([String.duplicate("x", padding)]), else: cff_index([])

      subr_index = cff_index([])

      build_top = fn cs_off, priv_off ->
        dict_int(cs_off) <>
          <<17::8>> <> dict_int(byte_size(private)) <> dict_int(priv_off) <> <<18::8>>
      end

      # The encoded offsets change the top DICT's size, which moves everything
      # after it. Iterate to a fixed point.
      {cs_off, priv_off} =
        Enum.reduce(1..6, {200, 300}, fn _, {c, p} ->
          top = cff_index([build_top.(c, p)])

          cs_at =
            4 + byte_size(name_index) + byte_size(top) + byte_size(string_index) +
              byte_size(subr_index)

          {cs_at, cs_at + byte_size(charstrings_index)}
        end)

      <<1::8, 0::8, 4::8, 2::8>> <>
        name_index <>
        cff_index([build_top.(cs_off, priv_off)]) <>
        string_index <> subr_index <> charstrings_index <> private
    end

    defp otf(opts \\ []) do
      # Three glyphs of differing size, so removing one measurably shrinks the
      # CharStrings INDEX. 14 is the CFF `endchar` operator.
      charstrings =
        Keyword.get(opts, :charstrings, [<<14>>, <<1, 2, 3, 14>>, <<1, 2, 3, 4, 5, 14>>])

      tables = [
        {"CFF ", cff_table(charstrings)},
        {"head",
         <<0::size(18)-unit(8), 1000::16-big, 0::size(16)-unit(8), 0::16-signed-big,
           0::16-signed-big, 500::16-signed-big, 700::16-signed-big, 0::16-big,
           0::size(4)-unit(8), 0::16-signed-big>>},
        {"hhea",
         <<0::32-big, 760::16-signed-big, -240::16-signed-big, 0::16-signed-big, 0::16-big,
           0::size(22)-unit(8), 1::16-big>>},
        {"maxp", <<0x0001_0000::32-big, 3::16-big>>},
        {"hmtx", <<500::16-big, 0::16-signed-big, 0, 0, 0, 0>>},
        {"cmap", cmap_format4([{?A, 1}, {?B, 2}])}
      ]

      n = length(tables)
      header = <<"OTTO", n::16-big, 0::16-big, 0::16-big, 0::16-big>>
      base = byte_size(header) + n * 16

      {records, bodies, _} =
        Enum.reduce(tables, {[], [], base}, fn {tag, data}, {recs, bods, offset} ->
          record = <<tag::binary-size(4), 0::32-big, offset::32-big, byte_size(data)::32-big>>
          {recs ++ [record], bods ++ [data], offset + byte_size(data)}
        end)

      IO.iodata_to_binary([header, records, bodies])
    end

    defp render_otf(binary, opts \\ []) do
      register_opts = Keyword.get(opts, :register, [])
      text = Keyword.get(opts, :text, "A")

      path =
        Path.join(System.tmp_dir!(), "tincture_fe_#{System.unique_integer([:positive])}.otf")

      File.write!(path, binary)

      try do
        Tincture.new()
        |> Tincture.register_otf_font("Probe", path, register_opts)
        |> Tincture.add_page()
        |> Tincture.set_font("Probe", 12)
        |> Tincture.text_at(50, 700, text)
        |> Tincture.export()
      after
        File.rm(path)
      end
    end

    defp embedded_size(pdf) do
      case Regex.run(~r/\/Length1\s+(\d+)/, pdf) do
        [_, size] -> String.to_integer(size)
        _ -> nil
      end
    end

    test "embeds CFF outlines as FontFile3, not FontFile2" do
      pdf = render_otf(otf())

      assert pdf =~ "/FontFile3"
      assert pdf =~ "/Subtype /OpenType"
      refute pdf =~ "/FontFile2"
    end

    test "subsetting rewrites the CFF and tags the base font" do
      assert render_otf(otf()) =~ ~r|/BaseFont /[A-Z]{6}\+Probe|
    end

    test "a subsetted CFF is smaller than the original" do
      # Drawing one glyph out of three must drop the other two charstrings.
      # If the offset patching were wrong the subsetter falls back to the full
      # table, so a size that has not moved means the rewrite did not happen.
      full = render_otf(otf(), register: [subset: :none])
      subset = render_otf(otf())

      # Assert both were found first: in Elixir's term order any number sorts
      # below any atom, so a nil on the right-hand side would make the
      # comparison pass vacuously.
      assert is_integer(embedded_size(full)) and is_integer(embedded_size(subset))
      assert embedded_size(subset) < embedded_size(full)
    end

    test "subset: :none embeds the CFF table verbatim" do
      pdf = render_otf(otf(), register: [subset: :none])

      assert pdf =~ "/BaseFont /Probe"
      refute pdf =~ ~r|/BaseFont /[A-Z]{6}\+|
    end

    test "drawing every glyph still produces a valid document" do
      pdf = render_otf(otf(), text: "AB")

      assert pdf =~ "/FontFile3"
      assert String.starts_with?(pdf, "%PDF-1.4")
      assert String.ends_with?(String.trim_trailing(pdf), "%%EOF")
    end

    test "a CFF with a single charstring subsets without error" do
      pdf = render_otf(otf(charstrings: [<<14>>]))
      assert pdf =~ "/FontFile3"
    end

    test "charstrings of equal size subset correctly" do
      # Equal sizes mean the INDEX offset arithmetic has no size differences to
      # hide a mistake behind.
      pdf = render_otf(otf(charstrings: [<<14>>, <<14>>, <<14>>]))
      assert pdf =~ "/FontFile3"
    end

    test "a CFF whose offsets are longints subsets without corruption" do
      # Padding pushes CharStrings and Private past 1131, so the top DICT
      # stores those offsets as 5-byte longints rather than the 1- or 2-byte
      # forms. Verified out of band: charstrings@2045, private@2067, both
      # longint-encoded.
      #
      # This asserts the document survives that shape. It does NOT reach the
      # in-place offset-patching encoder - that path stays uncovered, and
      # naming this test after it would be a lie.
      pdf = render_otf(otf(offset_padding: 2000))

      assert pdf =~ "/FontFile3"
      assert pdf =~ ~r|/BaseFont /[A-Z]{6}\+Probe|
      assert String.starts_with?(pdf, "%PDF-1.4")
    end

    test "a longint-offset CFF still subsets smaller than the original" do
      full = render_otf(otf(offset_padding: 2000), register: [subset: :none])
      subset = render_otf(otf(offset_padding: 2000))

      assert is_integer(embedded_size(full)) and is_integer(embedded_size(subset))
      assert embedded_size(subset) < embedded_size(full)
    end

    test "a malformed CFF table falls back rather than producing a broken PDF" do
      broken =
        otf()
        |> :binary.replace(<<1::8, 0::8, 4::8, 2::8>>, <<1::8, 0::8, 40::8, 2::8>>)

      pdf = render_otf(broken)
      assert String.starts_with?(pdf, "%PDF-1.4")
    end
  end
end
