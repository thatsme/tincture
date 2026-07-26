defmodule Tincture.Font.CFFTest do
  @moduledoc """
  Direct unit tests for the CFF container primitives.

  Before this module existed these functions were private in two places -
  `Tincture.Font.TTF` and `Tincture.PDF.Serialize` - reachable only through
  `parse_basic_tables/1` or `export/1`. Testing INDEX decoding therefore meant
  constructing a whole font binary or a whole PDF. These tests exercise the
  primitives directly, which is the point of the extraction.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.CFF

  # A CFF INDEX: count (u16), offSize (u8), count+1 offsets, then object data.
  # Offsets are 1-based relative to the byte before the data region.
  defp index(objects, off_size \\ 1) do
    {offsets, _} =
      Enum.reduce(objects, {[1], 1}, fn object, {acc, cursor} ->
        next = cursor + byte_size(object)
        {acc ++ [next], next}
      end)

    offset_bin = for offset <- offsets, into: <<>>, do: <<offset::size(off_size)-unit(8)>>
    data = IO.iodata_to_binary(objects)
    <<length(objects)::16-big, off_size::8, offset_bin::binary, data::binary>>
  end

  describe "parse_index/1" do
    test "decodes objects and reports where the INDEX ends" do
      binary = index(["abc", "de"]) <> "TRAILING"

      assert {:ok, result} = CFF.parse_index(binary)
      assert result.objects == ["abc", "de"]
      assert result.rest == "TRAILING"
      assert result.offsets == [1, 4, 6]
    end

    test "size and objects_data_offset locate the INDEX for offset patching" do
      binary = index(["abc", "de"])

      assert {:ok, result} = CFF.parse_index(binary)
      # count(2) + offSize(1) + 3 offsets * 1 byte = 6 bytes of header
      assert result.objects_data_offset == 6
      assert result.size == 6 + 5
      assert result.size == byte_size(binary)
    end

    test "an empty INDEX is legal and consumes two bytes" do
      assert {:ok, result} = CFF.parse_index(<<0::16-big, "REST">>)
      assert result.objects == []
      assert result.rest == "REST"
      assert result.size == 2
    end

    test "handles every legal offset size" do
      for off_size <- 1..4 do
        assert {:ok, result} = CFF.parse_index(index(["xy", "z"], off_size)),
               "off_size #{off_size} failed"

        assert result.objects == ["xy", "z"]
      end
    end

    test "rejects an out-of-range offset size" do
      # offSize 0 and 5 are outside the spec's 1..4.
      assert CFF.parse_index(<<1::16-big, 0::8, 0, 0>>) == :error
      assert CFF.parse_index(<<1::16-big, 5::8, 0, 0>>) == :error
    end

    test "rejects truncated offset tables and truncated object data" do
      assert CFF.parse_index(<<2::16-big, 1::8, 1>>) == :error
      assert CFF.parse_index(<<1::16-big, 1::8, 1, 9>>) == :error
    end

    test "rejects a non-INDEX binary" do
      assert CFF.parse_index(<<>>) == :error
      assert CFF.parse_index(<<1>>) == :error
    end
  end

  describe "decode_index_offsets/2" do
    test "decodes big-endian offsets at each width" do
      assert CFF.decode_index_offsets(<<1, 2, 3>>, 1) == {:ok, [1, 2, 3]}
      assert CFF.decode_index_offsets(<<0, 1, 0, 2>>, 2) == {:ok, [1, 2]}
      assert CFF.decode_index_offsets(<<0, 0, 1, 0, 0, 2>>, 3) == {:ok, [1, 2]}
      assert CFF.decode_index_offsets(<<0, 0, 0, 1>>, 4) == {:ok, [1]}
    end

    test "an empty run decodes to an empty list" do
      assert CFF.decode_index_offsets(<<>>, 2) == {:ok, []}
    end

    test "rejects a trailing partial offset" do
      assert CFF.decode_index_offsets(<<0, 1, 0>>, 2) == :error
    end

    test "rejects an offset size of zero rather than looping forever" do
      # With off_size == 0 the decoder would consume nothing per iteration.
      # The guard lives on the function, not only on its callers.
      assert CFF.decode_index_offsets(<<1, 2, 3>>, 0) == :error
    end

    test "rejects offset sizes outside the spec's 1..4" do
      assert CFF.decode_index_offsets(<<1>>, 5) == :error
      assert CFF.decode_index_offsets(<<1>>, -1) == :error
    end
  end

  describe "parse_index_objects/3" do
    test "slices objects and returns the data region size" do
      assert {:ok, objects, rest, size} = CFF.parse_index_objects([1, 4, 6], 2, "abcdeREST")
      assert objects == ["abc", "de"]
      assert rest == "REST"
      assert size == 5
    end

    test "rejects an offset list whose length disagrees with the count" do
      assert CFF.parse_index_objects([1, 4], 2, "abcde") == :error
    end

    test "rejects decreasing offsets, which would mean a negative-length object" do
      assert CFF.parse_index_objects([1, 6, 4], 2, "abcde") == :error
    end

    test "rejects zero-based offsets" do
      # CFF INDEX offsets are 1-based; 0 is malformed.
      assert CFF.parse_index_objects([0, 3, 5], 2, "abcde") == :error
    end

    test "rejects object data that runs past the end of the binary" do
      assert CFF.parse_index_objects([1, 4, 99], 2, "abcde") == :error
    end

    test "rejects malformed arguments" do
      assert CFF.parse_index_objects("nope", 2, "abcde") == :error
      assert CFF.parse_index_objects([1, 2], 0, "ab") == :error
    end
  end

  describe "parse_dict_number/1" do
    test "single-byte operands decode with the -139 bias" do
      assert CFF.parse_dict_number(<<139>>) == {:ok, 0, <<>>}
      assert CFF.parse_dict_number(<<32>>) == {:ok, -107, <<>>}
      assert CFF.parse_dict_number(<<246>>) == {:ok, 107, <<>>}
    end

    test "two-byte positive and negative operands" do
      assert CFF.parse_dict_number(<<247, 0>>) == {:ok, 108, <<>>}
      assert CFF.parse_dict_number(<<250, 255>>) == {:ok, 1131, <<>>}
      assert CFF.parse_dict_number(<<251, 0>>) == {:ok, -108, <<>>}
      assert CFF.parse_dict_number(<<254, 255>>) == {:ok, -1131, <<>>}
    end

    test "16-bit and 32-bit signed operands" do
      assert CFF.parse_dict_number(<<28, -1000::16-signed-big>>) == {:ok, -1000, <<>>}
      assert CFF.parse_dict_number(<<29, 100_000::32-signed-big>>) == {:ok, 100_000, <<>>}
    end

    test "operator 255 normalises whole 16.16 fixed values to integers" do
      # This is the drift that prompted the extraction: one copy returned a
      # bare value / 65_536 (always a float), the other normalised.
      assert CFF.parse_dict_number(<<255, 65_536::32-signed-big>>) == {:ok, 1, <<>>}
      assert CFF.parse_dict_number(<<255, -131_072::32-signed-big>>) == {:ok, -2, <<>>}
    end

    test "operator 255 keeps fractional 16.16 values as floats" do
      assert {:ok, value, <<>>} = CFF.parse_dict_number(<<255, 98_304::32-signed-big>>)
      assert value == 1.5
    end

    test "returns the unconsumed remainder" do
      assert CFF.parse_dict_number(<<139, "REST">>) == {:ok, 0, "REST"}
    end

    test "rejects reserved and empty encodings" do
      assert CFF.parse_dict_number(<<>>) == :error
      # 31 is an operator, not an operand.
      assert CFF.parse_dict_number(<<31>>) == :error
    end
  end

  describe "parse_real_number/1" do
    # Real numbers are BCD nibbles: 0-9 digits, A '.', B 'E', C 'E-', E '-',
    # F terminator.
    test "decodes a simple decimal" do
      # 1 . 5 F  ->  "1.5"
      assert {:ok, value, <<>>, consumed} = CFF.parse_real_number(<<0x1A, 0x5F>>)
      assert value == 1.5
      assert consumed == 2
    end

    test "decodes a negative number" do
      # E 2 F  ->  "-2"
      assert {:ok, value, <<>>, _} = CFF.parse_real_number(<<0xE2, 0xFF>>)
      assert value == -2.0
    end

    test "decodes exponent notation" do
      # 1 B 2 F  ->  "1E2"
      assert {:ok, value, <<>>, _} = CFF.parse_real_number(<<0x1B, 0x2F>>)
      assert value == 100.0
    end

    test "decodes a negative exponent" do
      # 1 C 2 F  ->  "1E-2"
      assert {:ok, value, <<>>, _} = CFF.parse_real_number(<<0x1C, 0x2F>>)
      assert value == 0.01
    end

    test "reports bytes consumed and returns the remainder" do
      assert {:ok, _value, "REST", consumed} = CFF.parse_real_number(<<0x1A, 0x5F, "REST">>)
      assert consumed == 2
    end

    test "rejects the reserved nibble D" do
      assert CFF.parse_real_number(<<0xD1, 0xFF>>) == :error
    end

    test "rejects an unterminated or empty encoding" do
      assert CFF.parse_real_number(<<>>) == :error
      assert CFF.parse_real_number(<<0x11>>) == :error
    end

    test "rejects nibbles that do not form a number" do
      # A lone '.' terminator is not parseable as a float.
      assert CFF.parse_real_number(<<0xAF>>) == :error
    end
  end

  describe "fixed_16_16_to_number/1" do
    test "whole values become integers" do
      assert CFF.fixed_16_16_to_number(65_536) === 1
      assert CFF.fixed_16_16_to_number(0) === 0
      assert CFF.fixed_16_16_to_number(-196_608) === -3
    end

    test "fractional values stay floats" do
      assert CFF.fixed_16_16_to_number(32_768) === 0.5
      assert CFF.fixed_16_16_to_number(98_304) === 1.5
    end
  end

  describe "round trip against a realistic INDEX" do
    test "a three-object INDEX with multi-byte offsets survives parsing" do
      objects = [String.duplicate("a", 300), "b", String.duplicate("c", 50)]
      binary = index(objects, 2) <> "AFTER"

      assert {:ok, result} = CFF.parse_index(binary)
      assert result.objects == objects
      assert result.rest == "AFTER"
      assert result.size == byte_size(binary) - byte_size("AFTER")
    end
  end

  # -- DICT accessors and table metadata -------------------------------------
  #
  # These were private in Tincture.Font.TTF until the CFF-dict layer was lifted
  # in, and came across without tests of their own.

  describe "cff_sid_to_string/2" do
    test "resolves standard SIDs from the built-in string table" do
      # 0..390 are predefined by the specification; the weight names at the top
      # of the range are what the font descriptor actually reads.
      assert CFF.cff_sid_to_string([], 383) == "Black"
      assert CFF.cff_sid_to_string([], 384) == "Bold"
      assert CFF.cff_sid_to_string([], 385) == "Book"
      assert CFF.cff_sid_to_string([], 386) == "Light"
      assert CFF.cff_sid_to_string([], 387) == "Medium"
      assert CFF.cff_sid_to_string([], 388) == "Regular"
      assert CFF.cff_sid_to_string([], 389) == "Roman"
      assert CFF.cff_sid_to_string([], 390) == "Semibold"
    end

    test "resolves custom SIDs from the font's own string index" do
      # SIDs from 391 index into the string INDEX, zero-based.
      assert CFF.cff_sid_to_string(["Inter", "Condensed"], 391) == "Inter"
      assert CFF.cff_sid_to_string(["Inter", "Condensed"], 392) == "Condensed"
    end

    test "returns nil for a custom SID past the end of the string index" do
      assert CFF.cff_sid_to_string(["Inter"], 500) == nil
      assert CFF.cff_sid_to_string([], 391) == nil
    end

    test "returns nil for a standard SID with no assigned string" do
      # The predefined table has gaps and stops at 390.
      assert CFF.cff_sid_to_string([], 380) == nil
    end

    test "returns nil for a malformed SID or string index" do
      assert CFF.cff_sid_to_string([], -1) == nil
      assert CFF.cff_sid_to_string([], nil) == nil
      assert CFF.cff_sid_to_string(nil, 391) == nil
    end

    test "trims a custom string and treats a blank one as absent" do
      assert CFF.cff_sid_to_string(["  Inter  "], 391) == "Inter"
      assert CFF.cff_sid_to_string(["   "], 391) == nil
    end
  end

  describe "normalize_name_value/1" do
    test "trims surrounding whitespace" do
      assert CFF.normalize_name_value("  Inter  ") == "Inter"
    end

    test "returns nil for a blank or empty string" do
      assert CFF.normalize_name_value("") == nil
      assert CFF.normalize_name_value("   ") == nil
    end

    test "leaves an ordinary name untouched" do
      assert CFF.normalize_name_value("Helvetica-Bold") == "Helvetica-Bold"
    end
  end

  describe "DICT operand extraction" do
    # A DICT entry is its operands followed by the operator byte.
    defp dict_int(value) when value >= 108 and value <= 1131 do
      <<div(value - 108, 256) + 247::8, rem(value - 108, 256)::8>>
    end

    defp dict_int(value) when value >= -107 and value <= 107, do: <<value + 139::8>>

    test "extract_cff_operator_operand/2 reads the last operand of an entry" do
      dict = dict_int(42) <> <<4::8>>
      assert CFF.extract_cff_operator_operand(dict, 4) == {:ok, 42}
    end

    test "finds an entry among several" do
      dict = dict_int(1) <> <<2::8>> <> dict_int(700) <> <<4::8>> <> dict_int(3) <> <<5::8>>
      assert CFF.extract_cff_operator_operand(dict, 4) == {:ok, 700}
    end

    test "returns :error when the operator is absent" do
      assert CFF.extract_cff_operator_operand(dict_int(42) <> <<4::8>>, 7) == :error
    end

    test "returns :error for an empty dict" do
      assert CFF.extract_cff_operator_operand(<<>>, 4) == :error
    end

    test "rejects an operator outside the single-byte range" do
      dict = dict_int(42) <> <<4::8>>
      assert CFF.extract_cff_operator_operand(dict, 22) == :error
      assert CFF.extract_cff_operator_operand(dict, -1) == :error
    end

    test "rejects a non-binary dict" do
      assert CFF.extract_cff_operator_operand(nil, 4) == :error
    end

    test "extract_cff_operator_operands/2 reads every operand of an entry" do
      # FontBBox (operator 5) carries four operands.
      dict = dict_int(0) <> dict_int(-100) <> dict_int(500) <> dict_int(700) <> <<5::8>>
      assert CFF.extract_cff_operator_operands(dict, 5) == {:ok, [0, -100, 500, 700]}
    end

    test "extract_cff_operator_operands/2 returns :error when absent" do
      assert CFF.extract_cff_operator_operands(dict_int(1) <> <<2::8>>, 5) == :error
      assert CFF.extract_cff_operator_operands(nil, 5) == :error
    end

    test "extract_cff_escaped_operator_operand/2 reads a two-byte operator" do
      # Escaped operators are the byte 12 followed by a second byte.
      dict = dict_int(120) <> <<12::8, 8::8>>
      assert CFF.extract_cff_escaped_operator_operand(dict, 8) == {:ok, 120}
    end

    test "escaped and unescaped operators with the same number are distinct" do
      # `12 8` must not be found by a search for plain operator 8.
      dict = dict_int(120) <> <<12::8, 8::8>>
      assert CFF.extract_cff_operator_operand(dict, 8) == :error
    end

    test "extract_cff_escaped_operator_operand/2 returns :error when absent" do
      assert CFF.extract_cff_escaped_operator_operand(dict_int(1) <> <<12::8, 9::8>>, 8) == :error
      assert CFF.extract_cff_escaped_operator_operand(nil, 8) == :error
      assert CFF.extract_cff_escaped_operator_operand(<<>>, 8) == :error
    end
  end

  describe "fetch_cff_metadata/2" do
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

    defp cff_table(opts \\ []) do
      name = Keyword.get(opts, :name, "FontName")
      top_dict = Keyword.get(opts, :top_dict, <<>>)
      strings = Keyword.get(opts, :strings, [])
      header_size = Keyword.get(opts, :header_size, 4)

      <<1::8, 0::8, header_size::8, 1::8>> <>
        String.duplicate(<<0>>, header_size - 4) <>
        cff_index([name]) <> cff_index([top_dict]) <> cff_index(strings) <> cff_index([])
    end

    defp font_with(cff), do: {<<0xAA, 0xBB>> <> cff, %{"CFF " => {2, byte_size(cff)}}}

    test "reads the name, top dict and string index" do
      {data, records} = font_with(cff_table(name: "Inter", strings: ["Custom"]))

      assert {:ok, metadata} = CFF.fetch_cff_metadata(data, records)
      assert metadata.cff_name == "Inter"
      assert metadata.string_index == ["Custom"]
      assert is_binary(metadata.top_dict)
    end

    test "tolerates a header larger than the minimum" do
      {data, records} = font_with(cff_table(header_size: 8))
      assert {:ok, _metadata} = CFF.fetch_cff_metadata(data, records)
    end

    test "fetch_cff_top_dict/2 returns just the top dict" do
      {data, records} = font_with(cff_table(top_dict: <<139::8, 4::8>>))
      assert {:ok, <<139, 4>>} = CFF.fetch_cff_top_dict(data, records)
    end

    test "returns :error when the font has no CFF table" do
      assert CFF.fetch_cff_metadata(<<0, 0>>, %{}) == :error
      assert CFF.fetch_cff_top_dict(<<0, 0>>, %{}) == :error
    end

    test "returns :error when the record points outside the font" do
      assert CFF.fetch_cff_metadata(<<0, 0>>, %{"CFF " => {900, 40}}) == :error
    end

    test "returns :error for a header shorter than four bytes" do
      {data, records} = font_with(<<1::8, 0::8>>)
      assert CFF.fetch_cff_metadata(data, records) == :error
    end

    test "returns :error when the declared header size exceeds the table" do
      {data, records} = font_with(<<1::8, 0::8, 40::8, 1::8>>)
      assert CFF.fetch_cff_metadata(data, records) == :error
    end

    test "returns :error when an index is malformed" do
      {data, records} = font_with(<<1::8, 0::8, 4::8, 1::8, 0xFF, 0xFF, 0xFF>>)
      assert CFF.fetch_cff_metadata(data, records) == :error
    end
  end

  describe "nondecreasing?/1" do
    test "an empty list is nondecreasing" do
      assert CFF.nondecreasing?([])
    end

    test "equal neighbours are allowed" do
      assert CFF.nondecreasing?([1, 1, 2, 2])
    end

    test "any decrease disqualifies the list" do
      refute CFF.nondecreasing?([1, 3, 2])
      refute CFF.nondecreasing?([2, 1])
    end
  end
end
