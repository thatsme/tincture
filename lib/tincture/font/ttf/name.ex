defmodule Tincture.Font.TTF.Name do
  @moduledoc """
  Parser for the OpenType `name` table.

  The `name` table carries the human-readable strings a font exposes: family,
  subfamily, PostScript name, version. The same logical name appears several
  times under different platform, encoding and language IDs, so reading it is
  mostly a matter of picking the best-encoded record rather than the first one.

  A CFF-flavoured OpenType font can also carry its family name in the CFF top
  DICT, so this falls back to `Tincture.Font.CFF` when the `name` table does
  not supply one.

  Extracted from `Tincture.Font.TTF`.
  """

  alias Tincture.Font.Binary
  alias Tincture.Font.CFF

  def parse_name_metadata(data, table_records) do
    case Map.fetch(table_records, "name") do
      {:ok, {offset, length}} ->
        with {:ok, name_table} <- Binary.slice(data, offset, length) do
          case parse_name_family(name_table) do
            family when is_binary(family) ->
              {:ok, %{font_family: family}}

            _ ->
              {:ok, %{font_family: parse_cff_family_name(data, table_records)}}
          end
        else
          _ -> {:ok, %{font_family: parse_cff_family_name(data, table_records)}}
        end

      :error ->
        {:ok, %{font_family: parse_cff_family_name(data, table_records)}}
    end
  end

  defp parse_name_family(
         <<_format::16-big, count::16-big, string_offset::16-big, _::binary>> = name_table
       ) do
    record_bytes = count * 12
    table_size = byte_size(name_table)

    if count == 0 or table_size < 6 + record_bytes or string_offset >= table_size do
      nil
    else
      records = binary_part(name_table, 6, record_bytes)

      records
      |> parse_name_records([])
      |> Enum.filter(fn {_platform, _encoding, _language, name_id, _length, _offset} ->
        name_id == 1
      end)
      |> Enum.sort_by(&name_record_priority/1)
      |> Enum.find_value(fn {platform_id, encoding_id, _language_id, _name_id, length, offset} ->
        read_name_string(name_table, string_offset, offset, length, platform_id, encoding_id)
      end)
    end
  end

  defp parse_name_family(_), do: nil

  defp parse_cff_family_name(data, table_records) do
    with {:ok, %{top_dict: top_dict, cff_name: cff_name, string_index: string_index}} <-
           CFF.fetch_cff_metadata(data, table_records) do
      family_name =
        case CFF.extract_cff_operator_operand(top_dict, 3) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            CFF.cff_sid_to_string(string_index, sid)

          _ ->
            nil
        end

      full_name =
        case CFF.extract_cff_operator_operand(top_dict, 2) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            CFF.cff_sid_to_string(string_index, sid)

          _ ->
            nil
        end

      font_name =
        case CFF.extract_cff_escaped_operator_operand(top_dict, 38) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            CFF.cff_sid_to_string(string_index, sid)

          _ ->
            nil
        end

      family_name || full_name || font_name || CFF.normalize_name_value(cff_name)
    else
      _ -> nil
    end
  end

  defp parse_name_records(<<>>, acc), do: Enum.reverse(acc)

  defp parse_name_records(
         <<platform_id::16-big, encoding_id::16-big, language_id::16-big, name_id::16-big,
           length::16-big, offset::16-big, rest::binary>>,
         acc
       ) do
    parse_name_records(
      rest,
      [{platform_id, encoding_id, language_id, name_id, length, offset} | acc]
    )
  end

  defp parse_name_records(_invalid, acc), do: Enum.reverse(acc)

  defp read_name_string(name_table, string_offset, offset, length, platform_id, encoding_id) do
    start = string_offset + offset
    table_size = byte_size(name_table)

    if length == 0 or start < 0 or start + length > table_size do
      nil
    else
      raw = binary_part(name_table, start, length)
      decode_name_string(raw, platform_id, encoding_id)
    end
  end

  defp decode_name_string(raw, 3, _encoding_id) when is_binary(raw) do
    case safe_unicode_decode(raw, {:utf16, :big}) do
      nil -> nil
      value -> CFF.normalize_name_value(value)
    end
  end

  defp decode_name_string(raw, 0, _encoding_id) when is_binary(raw) do
    case safe_unicode_decode(raw, {:utf16, :big}) do
      nil -> nil
      value -> CFF.normalize_name_value(value)
    end
  end

  defp decode_name_string(raw, 1, _encoding_id) when is_binary(raw) do
    case safe_unicode_decode(raw, :latin1) do
      nil -> nil
      value -> CFF.normalize_name_value(value)
    end
  end

  defp decode_name_string(_raw, _platform_id, _encoding_id), do: nil

  defp safe_unicode_decode(raw, source_encoding) do
    :unicode.characters_to_binary(raw, source_encoding, :utf8)
  rescue
    _ -> nil
  end

  defp name_record_priority({3, 1, 0x0409, 1, _length, _offset}), do: 0
  defp name_record_priority({3, _encoding, _language, 1, _length, _offset}), do: 1
  defp name_record_priority({0, _encoding, _language, 1, _length, _offset}), do: 2
  defp name_record_priority({1, _encoding, _language, 1, _length, _offset}), do: 3
  defp name_record_priority(_), do: 10
end
