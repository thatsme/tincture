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

  alias Tincture.Font.Binary

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

  @doc false
  # Older TTF-side callers want just the objects and the trailing binary, not
  # the offsets and sizes the subsetting path needs.
  def parse_index_pair(data) do
    case parse_index(data) do
      {:ok, %{objects: objects, rest: rest}} -> {:ok, {objects, rest}}
      :error -> :error
    end
  end

  def cff_sid_to_string(string_index, sid) when is_integer(sid) and sid >= 0 do
    if sid < 391 do
      cff_standard_sid_to_string(sid)
    else
      cff_string_index_sid_to_string(string_index, sid)
    end
  end

  def cff_sid_to_string(_string_index, _sid), do: nil
  defp cff_standard_sid_to_string(383), do: "Black"
  defp cff_standard_sid_to_string(384), do: "Bold"
  defp cff_standard_sid_to_string(385), do: "Book"
  defp cff_standard_sid_to_string(386), do: "Light"
  defp cff_standard_sid_to_string(387), do: "Medium"
  defp cff_standard_sid_to_string(388), do: "Regular"
  defp cff_standard_sid_to_string(389), do: "Roman"
  defp cff_standard_sid_to_string(390), do: "Semibold"
  defp cff_standard_sid_to_string(_sid), do: nil

  defp cff_string_index_sid_to_string(string_index, sid)
       when is_list(string_index) and is_integer(sid) and sid >= 391 do
    index = sid - 391

    case Enum.at(string_index, index) do
      value when is_binary(value) ->
        normalize_name_value(value)

      _ ->
        nil
    end
  end

  defp cff_string_index_sid_to_string(_string_index, _sid), do: nil

  def fetch_cff_top_dict(data, table_records) do
    with {:ok, %{top_dict: top_dict}} <- fetch_cff_metadata(data, table_records) do
      {:ok, top_dict}
    else
      _ -> :error
    end
  end

  def fetch_cff_metadata(data, table_records) do
    case Map.fetch(table_records, "CFF ") do
      {:ok, {offset, length}} ->
        with {:ok, cff_table} <- Binary.slice(data, offset, length),
             {:ok, cff_metadata} <- parse_cff_metadata(cff_table) do
          {:ok, cff_metadata}
        else
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp parse_cff_metadata(
         <<_major::8, _minor::8, header_size::8, _off_size::8, _::binary>> = cff_table
       )
       when header_size >= 4 do
    if byte_size(cff_table) < header_size do
      :error
    else
      <<_header::binary-size(header_size), body::binary>> = cff_table

      with {:ok, {name_index, after_name}} <- parse_index_pair(body),
           {:ok, {top_dict_index, after_top_dict}} <- parse_index_pair(after_name),
           {:ok, {string_index, _after_string}} <- parse_index_pair(after_top_dict),
           [top_dict | _rest] <- top_dict_index do
        cff_name =
          case name_index do
            [first_name | _] when is_binary(first_name) -> first_name
            _ -> nil
          end

        {:ok,
         %{
           top_dict: top_dict,
           cff_name: cff_name,
           string_index: string_index,
           cff_table: cff_table
         }}
      else
        _ -> :error
      end
    end
  end

  defp parse_cff_metadata(_), do: :error

  # Delegates to Tincture.Font.CFF, which owns the INDEX container format and
  # is shared with the subsetting path in Tincture.PDF.Serialize. Reading only
  # needs the objects and the trailing binary; the byte offsets CFF also
  # returns matter when rewriting a table, not when parsing one.
  def extract_cff_operator_operand(top_dict, operator)
      when is_binary(top_dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_dict_for_operator_operand(top_dict, operator, [])
  end

  def extract_cff_operator_operand(_top_dict, _operator), do: :error

  def extract_cff_operator_operands(top_dict, operator)
      when is_binary(top_dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_dict_for_operator_operands(top_dict, operator, [])
  end

  def extract_cff_operator_operands(_top_dict, _operator), do: :error

  def extract_cff_escaped_operator_operand(top_dict, escaped_operator)
      when is_binary(top_dict) and is_integer(escaped_operator) and escaped_operator >= 0 and
             escaped_operator <= 255 do
    scan_cff_dict_for_escaped_operator_operand(top_dict, escaped_operator, [])
  end

  def extract_cff_escaped_operator_operand(_top_dict, _escaped_operator), do: :error
  defp scan_cff_dict_for_operator_operand(<<>>, _operator, _operands), do: :error

  defp scan_cff_dict_for_operator_operand(
         <<12, _escaped_op::8, rest::binary>>,
         operator,
         _operands
       ) do
    scan_cff_dict_for_operator_operand(rest, operator, [])
  end

  defp scan_cff_dict_for_operator_operand(<<op::8, rest::binary>>, operator, operands)
       when op <= 21 do
    if op == operator do
      case Enum.reverse(operands) do
        [value | _] -> {:ok, value}
        _ -> :error
      end
    else
      scan_cff_dict_for_operator_operand(rest, operator, [])
    end
  end

  defp scan_cff_dict_for_operator_operand(dict_data, operator, operands) do
    case parse_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_for_operator_operand(rest, operator, [number | operands])

      :error ->
        :error
    end
  end

  defp scan_cff_dict_for_operator_operands(<<>>, _operator, _operands), do: :error

  defp scan_cff_dict_for_operator_operands(
         <<12, _escaped_op::8, rest::binary>>,
         operator,
         _operands
       ) do
    scan_cff_dict_for_operator_operands(rest, operator, [])
  end

  defp scan_cff_dict_for_operator_operands(<<op::8, rest::binary>>, operator, operands)
       when op <= 21 do
    if op == operator do
      case Enum.reverse(operands) do
        [] -> :error
        values -> {:ok, values}
      end
    else
      scan_cff_dict_for_operator_operands(rest, operator, [])
    end
  end

  defp scan_cff_dict_for_operator_operands(dict_data, operator, operands) do
    case parse_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_for_operator_operands(rest, operator, [number | operands])

      :error ->
        :error
    end
  end

  defp scan_cff_dict_for_escaped_operator_operand(<<>>, _escaped_operator, _operands), do: :error

  defp scan_cff_dict_for_escaped_operator_operand(
         <<12, escaped_op::8, rest::binary>>,
         escaped_operator,
         operands
       ) do
    if escaped_op == escaped_operator do
      case Enum.reverse(operands) do
        [value | _] -> {:ok, value}
        _ -> :error
      end
    else
      scan_cff_dict_for_escaped_operator_operand(rest, escaped_operator, [])
    end
  end

  defp scan_cff_dict_for_escaped_operator_operand(
         <<operator::8, rest::binary>>,
         escaped_operator,
         _operands
       )
       when operator <= 21 do
    scan_cff_dict_for_escaped_operator_operand(rest, escaped_operator, [])
  end

  defp scan_cff_dict_for_escaped_operator_operand(dict_data, escaped_operator, operands) do
    case parse_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_for_escaped_operator_operand(rest, escaped_operator, [number | operands])

      :error ->
        :error
    end
  end

  @doc """
  Trim a string value read from a font table, returning nil when it is empty.

  Font tables routinely carry padded or blank strings where a field is
  unset; nil is more useful downstream than an empty binary.
  """
  @spec normalize_name_value(term()) :: String.t() | nil
  def normalize_name_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
