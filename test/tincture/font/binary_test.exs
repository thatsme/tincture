defmodule Tincture.Font.BinaryTest do
  @moduledoc """
  Direct tests for the bounds-checked font table readers.

  Font files supply their own table offsets, and those offsets are untrusted:
  a malformed or hostile font can point anywhere. These readers are the only
  thing standing between a bad offset and a crash, so the out-of-range cases
  matter more than the happy path.
  """
  use ExUnit.Case, async: true

  alias Tincture.Font.Binary

  @data <<0x00, 0x01, 0x80, 0xFF, 0xAB, 0xCD>>

  describe "slice/3" do
    test "reads an in-range span" do
      assert Binary.slice(@data, 0, 2) == {:ok, <<0x00, 0x01>>}
      assert Binary.slice(@data, 4, 2) == {:ok, <<0xAB, 0xCD>>}
    end

    test "a zero-length slice at the very end is legal" do
      assert Binary.slice(@data, byte_size(@data), 0) == {:ok, <<>>}
    end

    test "rejects a span running past the end" do
      assert Binary.slice(@data, 5, 2) == :error
      assert Binary.slice(@data, 0, 7) == :error
    end

    test "rejects an offset past the end" do
      assert Binary.slice(@data, 99, 1) == :error
    end

    test "does not overflow on a huge length" do
      # The naive check offset + length <= size can overflow in languages with
      # fixed-width integers; this one must simply say no.
      assert Binary.slice(@data, 1, 1_000_000_000) == :error
    end
  end

  describe "u16/2" do
    test "reads big-endian unsigned values" do
      assert Binary.u16(@data, 0) == {:ok, 1}
      assert Binary.u16(@data, 2) == {:ok, 0x80FF}
    end

    test "the high bit is not treated as a sign" do
      assert Binary.u16(<<0xFF, 0xFF>>, 0) == {:ok, 65_535}
    end

    test "rejects reads that would run past the end" do
      assert Binary.u16(@data, 5) == :error
      assert Binary.u16(<<1>>, 0) == :error
    end

    test "rejects a negative or non-integer offset" do
      assert Binary.u16(@data, -1) == :error
      assert Binary.u16(@data, :nope) == :error
    end
  end

  describe "s16/2" do
    test "reads big-endian signed values" do
      assert Binary.s16(<<0xFF, 0xFF>>, 0) == {:ok, -1}
      assert Binary.s16(<<0x80, 0x00>>, 0) == {:ok, -32_768}
      assert Binary.s16(<<0x7F, 0xFF>>, 0) == {:ok, 32_767}
    end

    test "differs from u16 exactly where the sign bit is set" do
      assert Binary.u16(<<0xFF, 0xFF>>, 0) == {:ok, 65_535}
      assert Binary.s16(<<0xFF, 0xFF>>, 0) == {:ok, -1}
    end

    test "rejects out-of-range and malformed offsets" do
      assert Binary.s16(@data, 5) == :error
      assert Binary.s16(@data, -1) == :error
    end
  end

  describe "u32/2" do
    test "reads big-endian 32-bit values" do
      assert Binary.u32(<<0x00, 0x01, 0x00, 0x00>>, 0) == {:ok, 65_536}
      assert Binary.u32(<<0xFF, 0xFF, 0xFF, 0xFF>>, 0) == {:ok, 4_294_967_295}
    end

    test "rejects out-of-range and malformed offsets" do
      assert Binary.u32(<<1, 2, 3>>, 0) == :error
      assert Binary.u32(@data, -1) == :error
    end
  end

  describe "bytes/3" do
    test "returns the span, or nil when it does not fit" do
      assert Binary.bytes(@data, 0, 3) == <<0x00, 0x01, 0x80>>
      assert Binary.bytes(@data, 5, 2) == nil
      assert Binary.bytes(@data, 99, 1) == nil
    end

    test "returns nil rather than :error, since callers pattern match on absence" do
      refute Binary.bytes(@data, 99, 1) == :error
      assert Binary.bytes(@data, 99, 1) == nil
    end

    test "rejects a non-positive length" do
      assert Binary.bytes(@data, 0, 0) == nil
      assert Binary.bytes(@data, 0, -1) == nil
    end
  end

  describe "list decoders" do
    test "u16_list decodes a whole binary" do
      assert Binary.u16_list(<<0, 1, 0, 2, 0, 3>>) == [1, 2, 3]
      assert Binary.u16_list(<<>>) == []
    end

    test "s16_list applies the sign" do
      assert Binary.s16_list(<<0xFF, 0xFF, 0x00, 0x01>>) == [-1, 1]
    end

    test "u32_list decodes 32-bit values" do
      assert Binary.u32_list(<<0, 0, 0, 1, 0, 0, 0, 2>>) == [1, 2]
    end

    test "a trailing partial element raises rather than truncating silently" do
      # Callers slice exactly count * width bytes, so a partial element means
      # the slice was computed wrongly. Surfacing that is deliberate — see the
      # module docs. This pins the behaviour so it is not "fixed" by accident.
      assert_raise FunctionClauseError, fn -> Binary.u16_list(<<0, 1, 2>>) end
      assert_raise FunctionClauseError, fn -> Binary.u32_list(<<0, 0, 0, 1, 9>>) end
    end
  end
end
