defmodule Tincture.Font.CFF do
  @moduledoc """
  Primitives for the Compact Font Format container.

  CFF (Adobe TN#5176) is the PostScript-outline format carried inside an
  OpenType font's `CFF ` table. This module owns the *container*: INDEX
  structures and DICT operand encoding. It deliberately does not interpret what
  those operands mean — that is the caller's job, and the two callers want
  different things:

    * `Tincture.Font.TTF` reads a CFF table for metadata (font name, FontBBox,
      StemV, weight).
    * `Tincture.PDF.Serialize` rewrites a CFF table when subsetting an embedded
      OpenType font, which additionally needs byte offsets and sizes so it can
      patch the top DICT.

  Both previously carried their own copy of these primitives, in modules that
  never referenced each other. Five of the eight duplicated functions had
  already drifted — most consequentially `parse_dict_number/1`, where operator
  255 (16.16 fixed) produced a bare float in one copy and a normalised integer
  in the other for the same input bytes. The reconciled behaviour is documented
  per function below.

  Every function returns `:error` rather than raising: font files are untrusted
  input and a malformed table must degrade, not crash the render.
  """

  import Bitwise

  @typedoc """
  A decoded INDEX.

  `size` is the INDEX's total byte length and `objects_data_offset` the offset
  from the start of the INDEX to the first object's data. Both are needed to
  patch offsets when rewriting a CFF table; readers can ignore them.
  """
  @type index :: %{
          objects: [binary()],
          rest: binary(),
          size: non_neg_integer(),
          offsets: [non_neg_integer()],
          objects_data_offset: non_neg_integer()
        }

  @doc """
  Parse a CFF INDEX from the start of `data`.

  An INDEX is a count, an offset size, `count + 1` offsets, then the object
  data. A zero count is legal and yields no objects.
  """
  @spec parse_index(binary()) :: {:ok, index()} | :error
  def parse_index(<<0::16-big, rest::binary>>) do
    {:ok, %{objects: [], rest: rest, size: 2, offsets: [], objects_data_offset: 2}}
  end

  def parse_index(<<count::16-big, off_size::8, offset_data::binary>>)
      when off_size >= 1 and off_size <= 4 do
    offset_bytes = (count + 1) * off_size

    if byte_size(offset_data) < offset_bytes do
      :error
    else
      <<offset_bytes_bin::binary-size(offset_bytes), objects_and_rest::binary>> = offset_data

      with {:ok, offsets} <- decode_index_offsets(offset_bytes_bin, off_size),
           {:ok, objects, rest_after, objects_size} <-
             parse_index_objects(offsets, count, objects_and_rest) do
        {:ok,
         %{
           objects: objects,
           rest: rest_after,
           size: 2 + 1 + offset_bytes + objects_size,
           offsets: offsets,
           objects_data_offset: 2 + 1 + offset_bytes
         }}
      else
        _ -> :error
      end
    end
  end

  def parse_index(_data), do: :error

  @doc """
  Decode a packed run of INDEX offsets, each `off_size` bytes wide.

  `off_size` is bounded to 1..4 by the CFF specification. The bound is enforced
  here rather than left to callers: with `off_size == 0` the decode loop would
  consume nothing per iteration and never terminate.
  """
  @spec decode_index_offsets(binary(), 1..4) :: {:ok, [non_neg_integer()]} | :error
  def decode_index_offsets(bin, off_size)
      when is_binary(bin) and is_integer(off_size) and off_size >= 1 and off_size <= 4 do
    decode_index_offsets(bin, off_size, [])
  end

  def decode_index_offsets(_bin, _off_size), do: :error

  defp decode_index_offsets(<<>>, _off_size, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_index_offsets(bin, off_size, acc) do
    if byte_size(bin) < off_size do
      :error
    else
      <<entry::binary-size(off_size), rest::binary>> = bin
      decode_index_offsets(rest, off_size, [:binary.decode_unsigned(entry) | acc])
    end
  end

  @doc """
  Slice INDEX object data using an already-decoded offset list.

  Returns the objects, the remaining binary after the INDEX, and the size of
  the object data region.

  CFF INDEX offsets are 1-based, so the first must be at least 1 and the list
  must be nondecreasing. Those two conditions together also guarantee every
  object has a non-negative length, so no per-object check is needed.
  """
  @spec parse_index_objects([non_neg_integer()], pos_integer(), binary()) ::
          {:ok, [binary()], binary(), non_neg_integer()} | :error
  def parse_index_objects(offsets, count, objects_and_rest)
      when is_list(offsets) and is_integer(count) and count > 0 and is_binary(objects_and_rest) do
    cond do
      length(offsets) != count + 1 ->
        :error

      hd(offsets) < 1 or List.last(offsets) < 1 ->
        :error

      not nondecreasing?(offsets) ->
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
            binary_part(objects_data, start_offset - 1, end_offset - start_offset)
          end)

        {:ok, objects, rest_after, objects_size}
    end
  end

  def parse_index_objects(_offsets, _count, _objects_and_rest), do: :error

  @doc """
  Parse a single DICT operand from the head of `data`.

  Handles every CFF DICT number encoding: single-byte (32..246), two-byte
  positive (247..250) and negative (251..254), 16-bit (28), 32-bit (29),
  16.16 fixed (255) and real/BCD (30).

  Operator 255 is normalised through `fixed_16_16_to_number/1`, so a whole
  value comes back as an integer rather than a float. The other historical
  copy returned a bare `value / 65_536`, which made `1` and `1.0` depend on
  which module happened to parse the byte.
  """
  @spec parse_dict_number(binary()) :: {:ok, number(), binary()} | :error
  def parse_dict_number(<<28, value::16-signed-big, rest::binary>>), do: {:ok, value, rest}
  def parse_dict_number(<<29, value::32-signed-big, rest::binary>>), do: {:ok, value, rest}

  def parse_dict_number(<<30, rest::binary>>) do
    case parse_real_number(rest) do
      {:ok, value, remaining, _consumed} -> {:ok, value, remaining}
      :error -> :error
    end
  end

  def parse_dict_number(<<255, raw_value::32-signed-big, rest::binary>>),
    do: {:ok, fixed_16_16_to_number(raw_value), rest}

  def parse_dict_number(<<first::8, second::8, rest::binary>>)
      when first >= 247 and first <= 250,
      do: {:ok, (first - 247) * 256 + second + 108, rest}

  def parse_dict_number(<<first::8, second::8, rest::binary>>)
      when first >= 251 and first <= 254,
      do: {:ok, -((first - 251) * 256 + second + 108), rest}

  def parse_dict_number(<<value::8, rest::binary>>) when value >= 32 and value <= 246,
    do: {:ok, value - 139, rest}

  def parse_dict_number(_data), do: :error

  @doc """
  Parse a CFF real (BCD) number, the payload following operator 30.

  Returns the value, the remaining binary, and how many bytes the encoding
  consumed. The byte count matters when rewriting a DICT in place, where an
  operand's span has to be known to patch around it.
  """
  @spec parse_real_number(binary()) :: {:ok, number(), binary(), pos_integer()} | :error
  def parse_real_number(data) when is_binary(data), do: parse_real_number(data, [])

  defp parse_real_number(<<>>, _acc), do: :error

  defp parse_real_number(<<byte::8, rest::binary>>, acc) do
    high_nibble = byte >>> 4
    low_nibble = byte &&& 0x0F

    case real_nibble(high_nibble, acc) do
      {:continue, after_high} ->
        case real_nibble(low_nibble, after_high) do
          {:continue, after_low} ->
            case parse_real_number(rest, after_low) do
              {:ok, value, remaining, consumed} -> {:ok, value, remaining, consumed + 1}
              :error -> :error
            end

          {:done, done_acc} ->
            finalize_real_number(done_acc, rest, 1)

          :error ->
            :error
        end

      {:done, done_acc} ->
        finalize_real_number(done_acc, rest, 1)

      :error ->
        :error
    end
  end

  # Nibble alphabet from the CFF spec: 0-9 digits, A '.', B 'E', C 'E-',
  # E '-', F terminator. D is reserved and therefore an error.
  defp real_nibble(nibble, acc) when nibble >= 0 and nibble <= 9,
    do: {:continue, [Integer.to_string(nibble) | acc]}

  defp real_nibble(0xA, acc), do: {:continue, ["." | acc]}
  defp real_nibble(0xB, acc), do: {:continue, ["E" | acc]}
  defp real_nibble(0xC, acc), do: {:continue, ["E-" | acc]}
  defp real_nibble(0xE, acc), do: {:continue, ["-" | acc]}
  defp real_nibble(0xF, acc), do: {:done, acc}
  defp real_nibble(_nibble, _acc), do: :error

  defp finalize_real_number(acc, rest, consumed_bytes)
       when is_list(acc) and is_binary(rest) and is_integer(consumed_bytes) and
              consumed_bytes > 0 do
    number = acc |> Enum.reverse() |> IO.iodata_to_binary()

    case Float.parse(number) do
      {value, ""} -> {:ok, value, rest, consumed_bytes}
      _ -> :error
    end
  end

  @doc """
  Convert a raw 16.16 fixed-point integer to a number.

  Whole values come back as integers so that a FontBBox of `1` does not become
  `1.0` purely because of how it was encoded.
  """
  @spec fixed_16_16_to_number(integer()) :: number()
  def fixed_16_16_to_number(raw_value) when is_integer(raw_value) do
    if rem(raw_value, 65_536) == 0 do
      div(raw_value, 65_536)
    else
      raw_value / 65_536
    end
  end

  @doc """
  Returns true when `list` never decreases.

  Used to validate INDEX offset tables, where a decrease would mean an object
  with negative length.
  """
  @spec nondecreasing?([number()]) :: boolean()
  def nondecreasing?([]), do: true
  def nondecreasing?([_single]), do: true
  def nondecreasing?([left, right | rest]) when left <= right, do: nondecreasing?([right | rest])
  def nondecreasing?(_list), do: false
end
