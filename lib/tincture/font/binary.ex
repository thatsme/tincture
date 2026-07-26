defmodule Tincture.Font.Binary do
  @moduledoc """
  Bounds-checked readers for big-endian font table data.

  Every sfnt-based format — TrueType, OpenType, CFF — stores its tables as
  big-endian integers at offsets that the file itself supplies. Those offsets
  are untrusted: a malformed or hostile font can point anywhere. These readers
  return `:error` (or `nil`, for the `read_bytes/3` shape) rather than raising,
  so a bad offset degrades one table instead of crashing the render.

  They were previously private to `Tincture.Font.TTF`, which meant every table
  parser had to live in the same module to reach them.
  """

  @doc """
  Read `length` bytes at `offset`, or `:error` if that range is not fully
  inside `data`.
  """
  @spec slice(binary(), non_neg_integer(), non_neg_integer()) :: {:ok, binary()} | :error
  def slice(data, offset, length) do
    data_size = byte_size(data)

    if offset <= data_size and length <= data_size - offset do
      {:ok, binary_part(data, offset, length)}
    else
      :error
    end
  end

  @doc "Read an unsigned 16-bit big-endian integer at `offset`."
  @spec u16(binary(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  def u16(data, offset) when is_integer(offset) and offset >= 0 do
    if offset + 2 <= byte_size(data) do
      <<value::16-big>> = binary_part(data, offset, 2)
      {:ok, value}
    else
      :error
    end
  end

  def u16(_data, _offset), do: :error

  @doc "Read a signed 16-bit big-endian integer at `offset`."
  @spec s16(binary(), non_neg_integer()) :: {:ok, integer()} | :error
  def s16(data, offset) when is_integer(offset) and offset >= 0 do
    if offset + 2 <= byte_size(data) do
      <<value::16-signed-big>> = binary_part(data, offset, 2)
      {:ok, value}
    else
      :error
    end
  end

  def s16(_data, _offset), do: :error

  @doc "Read an unsigned 32-bit big-endian integer at `offset`."
  @spec u32(binary(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  def u32(data, offset) when is_integer(offset) and offset >= 0 do
    if offset + 4 <= byte_size(data) do
      <<value::32-big>> = binary_part(data, offset, 4)
      {:ok, value}
    else
      :error
    end
  end

  def u32(_data, _offset), do: :error

  @doc """
  Read `len` bytes at `offset`, or `nil` if the range does not fit.

  Returns `nil` rather than `:error` because its callers thread the result
  straight into pattern matches where a nil is the natural "absent" case.
  """
  @spec bytes(binary(), non_neg_integer(), pos_integer()) :: binary() | nil
  def bytes(data, offset, len)
      when is_integer(offset) and offset >= 0 and is_integer(len) and len > 0 do
    if offset + len <= byte_size(data) do
      binary_part(data, offset, len)
    else
      nil
    end
  end

  def bytes(_data, _offset, _len), do: nil

  @doc """
  Decode a whole binary as a list of unsigned 16-bit big-endian integers.

  Deliberately has no clause for a trailing odd byte: callers slice exactly
  `count * 2` bytes, so an odd length means the slice was computed wrongly and
  should surface rather than silently truncate. Preserved from the original
  implementation; changing it is a behaviour decision, not a refactor.
  """
  @spec u16_list(binary()) :: [non_neg_integer()]
  def u16_list(bin), do: u16_list(bin, [])

  defp u16_list(<<>>, acc), do: Enum.reverse(acc)
  defp u16_list(<<value::16-big, rest::binary>>, acc), do: u16_list(rest, [value | acc])

  @doc "Decode a whole binary as a list of signed 16-bit big-endian integers."
  @spec s16_list(binary()) :: [integer()]
  def s16_list(bin), do: s16_list(bin, [])

  defp s16_list(<<>>, acc), do: Enum.reverse(acc)
  defp s16_list(<<value::16-signed-big, rest::binary>>, acc), do: s16_list(rest, [value | acc])

  @doc "Decode a whole binary as a list of unsigned 32-bit big-endian integers."
  @spec u32_list(binary()) :: [non_neg_integer()]
  def u32_list(bin), do: u32_list(bin, [])

  defp u32_list(<<>>, acc), do: Enum.reverse(acc)
  defp u32_list(<<value::32-big, rest::binary>>, acc), do: u32_list(rest, [value | acc])
end
