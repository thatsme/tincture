defmodule Tincture.Font.TTF.Cmap do
  @moduledoc """
  Parser for the TrueType/OpenType `cmap` table.

  `cmap` maps Unicode codepoints to glyph indices. It is the table that decides
  whether a font can render a given character at all, and it comes in several
  incompatible subtable formats - format 0 (byte), 2 (high-byte mapping for
  legacy CJK encodings), 4 (segmented, the common BMP case), 6 (trimmed), 12
  (segmented 32-bit, needed for anything outside the BMP) and 14 (Unicode
  variation sequences).

  Each format is a separate on-disk layout, which is why this is 30 functions
  rather than one. Extracted from `Tincture.Font.TTF`, where it was reachable
  only through `parse_basic_tables/1`.
  """

  import Bitwise

  alias Tincture.Font.Binary

  def parse_cmap_by_code(data, table_records) do
    case Map.fetch(table_records, "cmap") do
      {:ok, {offset, length}} ->
        with {:ok, cmap_table} <- Binary.slice(data, offset, length) do
          case parse_cmap_table(cmap_table) do
            {:ok, cmap_by_code} -> {:ok, cmap_by_code}
            :error -> {:ok, %{}}
          end
        else
          _ -> {:ok, %{}}
        end

      :error ->
        {:ok, %{}}
    end
  end

  def parse_cmap_variation_metadata(data, table_records) do
    default = %{cmap_var_selectors: [], cmap_non_default_uvs: %{}}

    case Map.fetch(table_records, "cmap") do
      {:ok, {offset, length}} ->
        with {:ok, cmap_table} <- Binary.slice(data, offset, length),
             {:ok, metadata} <- parse_cmap_format14_metadata(cmap_table) do
          {:ok, metadata}
        else
          _ -> {:ok, default}
        end

      :error ->
        {:ok, default}
    end
  end

  defp parse_cmap_format14_metadata(
         <<_version::16-big, num_tables::16-big, rest::binary>> = cmap_table
       ) do
    required_bytes = num_tables * 8

    if byte_size(rest) < required_bytes do
      :error
    else
      <<records::binary-size(required_bytes), _::binary>> = rest

      records
      |> parse_cmap_records([])
      |> Enum.reduce(
        %{cmap_var_selectors: [], cmap_non_default_uvs: %{}},
        fn {_platform_id, _encoding_id, offset}, acc ->
          case extract_subtable(cmap_table, offset) do
            {:ok, subtable} ->
              case parse_cmap_format14_subtable(subtable) do
                {:ok, %{selectors: selectors, non_default_uvs: non_default_uvs}} ->
                  merged_selectors =
                    (acc.cmap_var_selectors ++ selectors)
                    |> Enum.uniq()
                    |> Enum.sort()

                  merged_non_defaults = Map.merge(acc.cmap_non_default_uvs, non_default_uvs)

                  %{
                    cmap_var_selectors: merged_selectors,
                    cmap_non_default_uvs: merged_non_defaults
                  }

                :error ->
                  acc
              end

            :error ->
              acc
          end
        end
      )
      |> then(&{:ok, &1})
    end
  end

  defp parse_cmap_format14_metadata(_), do: :error

  defp parse_cmap_format14_subtable(
         <<14::16-big, length::32-big, num_records::32-big, record_data::binary>> = data
       )
       when length >= 10 do
    required_record_bytes = num_records * 11

    if byte_size(data) < length or byte_size(record_data) < required_record_bytes do
      :error
    else
      <<records_bin::binary-size(required_record_bytes), _::binary>> = record_data

      records = parse_format14_selector_records(records_bin, [])

      if records == :error do
        :error
      else
        parse_format14_selector_tables(data, records)
      end
    end
  end

  defp parse_cmap_format14_subtable(_), do: :error
  defp parse_format14_selector_records(<<>>, acc), do: Enum.reverse(acc)

  defp parse_format14_selector_records(
         <<selector::24-big, default_uvs_offset::32-big, non_default_uvs_offset::32-big,
           rest::binary>>,
         acc
       ) do
    parse_format14_selector_records(
      rest,
      [{selector, default_uvs_offset, non_default_uvs_offset} | acc]
    )
  end

  defp parse_format14_selector_records(_invalid, _acc), do: :error

  defp parse_format14_selector_tables(subtable, records) do
    records
    |> Enum.reduce_while({:ok, [], %{}}, fn {selector, _default_offset, non_default_offset},
                                            {:ok, selectors_acc, non_defaults_acc} ->
      selectors_next = [selector | selectors_acc]

      case parse_format14_non_default_uvs(subtable, selector, non_default_offset) do
        {:ok, mappings} ->
          {:cont, {:ok, selectors_next, Map.merge(non_defaults_acc, mappings)}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, selectors, non_default_uvs} ->
        {:ok, %{selectors: Enum.reverse(selectors), non_default_uvs: non_default_uvs}}

      :error ->
        :error
    end
  end

  defp parse_format14_non_default_uvs(_subtable, _selector, 0), do: {:ok, %{}}

  defp parse_format14_non_default_uvs(subtable, selector, non_default_offset)
       when is_integer(non_default_offset) and non_default_offset > 0 do
    with {:ok, non_default_table} <- extract_subtable(subtable, non_default_offset),
         <<num_mappings::32-big, mapping_data::binary>> <- non_default_table do
      required_bytes = num_mappings * 5

      if byte_size(mapping_data) < required_bytes do
        :error
      else
        <<mappings_bin::binary-size(required_bytes), _::binary>> = mapping_data

        mappings =
          parse_format14_non_default_records(mappings_bin, selector, %{})

        if mappings == :error do
          :error
        else
          {:ok, mappings}
        end
      end
    else
      _ -> :error
    end
  end

  defp parse_format14_non_default_uvs(_subtable, _selector, _invalid_offset), do: :error
  defp parse_format14_non_default_records(<<>>, _selector, acc), do: acc

  defp parse_format14_non_default_records(
         <<unicode_value::24-big, glyph_id::16-big, rest::binary>>,
         selector,
         acc
       ) do
    parse_format14_non_default_records(
      rest,
      selector,
      Map.put(acc, {unicode_value, selector}, glyph_id)
    )
  end

  defp parse_format14_non_default_records(_invalid, _selector, _acc), do: :error

  defp parse_cmap_table(<<_version::16-big, num_tables::16-big, rest::binary>> = cmap_table) do
    required_bytes = num_tables * 8

    if byte_size(rest) < required_bytes do
      :error
    else
      <<records::binary-size(required_bytes), _::binary>> = rest

      records
      |> parse_cmap_records([])
      |> Enum.sort_by(&cmap_record_priority/1)
      |> Enum.reduce_while(:error, fn {_platform_id, _encoding_id, offset}, _acc ->
        case extract_subtable(cmap_table, offset) do
          {:ok, subtable} ->
            case parse_cmap_subtable(subtable) do
              {:ok, cmap_by_code} -> {:halt, {:ok, cmap_by_code}}
              :error -> {:cont, :error}
            end

          :error ->
            {:cont, :error}
        end
      end)
      |> case do
        {:ok, cmap_by_code} -> {:ok, cmap_by_code}
        :error -> {:ok, %{}}
      end
    end
  end

  defp parse_cmap_table(_), do: :error
  defp parse_cmap_records(<<>>, acc), do: acc

  defp parse_cmap_records(
         <<platform_id::16-big, encoding_id::16-big, offset::32-big, rest::binary>>,
         acc
       ) do
    parse_cmap_records(rest, [{platform_id, encoding_id, offset} | acc])
  end

  defp parse_cmap_records(_invalid, _acc), do: []

  defp extract_subtable(cmap_table, offset) when is_integer(offset) and offset >= 0 do
    table_size = byte_size(cmap_table)

    if offset < table_size do
      {:ok, binary_part(cmap_table, offset, table_size - offset)}
    else
      :error
    end
  end

  defp extract_subtable(_cmap_table, _offset), do: :error

  defp parse_cmap_subtable(
         <<8::16-big, _reserved::16-big, length::32-big, _language::32-big, _::binary>> = data
       )
       when length >= 20 do
    if byte_size(data) < length do
      :error
    else
      subtable = binary_part(data, 0, length)
      parse_cmap_format8(subtable)
    end
  end

  defp parse_cmap_subtable(
         <<10::16-big, _reserved::16-big, length::32-big, _language::32-big, _::binary>> = data
       )
       when length >= 20 do
    if byte_size(data) < length do
      :error
    else
      subtable = binary_part(data, 0, length)
      parse_cmap_format10(subtable)
    end
  end

  defp parse_cmap_subtable(
         <<12::16-big, _reserved::16-big, length::32-big, _language::32-big, _::binary>> = data
       )
       when length >= 16 do
    if byte_size(data) < length do
      :error
    else
      subtable = binary_part(data, 0, length)
      parse_cmap_format12(subtable)
    end
  end

  defp parse_cmap_subtable(
         <<13::16-big, _reserved::16-big, length::32-big, _language::32-big, _::binary>> = data
       )
       when length >= 16 do
    if byte_size(data) < length do
      :error
    else
      subtable = binary_part(data, 0, length)
      parse_cmap_format13(subtable)
    end
  end

  defp parse_cmap_subtable(
         <<format::16-big, length::16-big, _language::16-big, _::binary>> = data
       )
       when length >= 6 do
    if byte_size(data) < length do
      :error
    else
      subtable = binary_part(data, 0, length)

      case format do
        0 -> parse_cmap_format0(subtable)
        2 -> parse_cmap_format2(subtable)
        4 -> parse_cmap_format4(subtable)
        6 -> parse_cmap_format6(subtable)
        _ -> :error
      end
    end
  end

  defp parse_cmap_subtable(_), do: :error

  defp parse_cmap_format0(
         <<0::16-big, 262::16-big, _language::16-big, glyph_ids::binary-size(256)>>
       ) do
    cmap_by_code =
      glyph_ids
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.into(%{}, fn {glyph_id, code} -> {code, glyph_id} end)

    {:ok, cmap_by_code}
  end

  defp parse_cmap_format0(_), do: :error

  defp parse_cmap_format2(
         <<2::16-big, _length::16-big, _language::16-big, subheader_keys::binary-size(512),
           rest::binary>> = subtable
       ) do
    keys = Binary.u16_list(subheader_keys)
    max_key = Enum.max(keys)

    if rem(max_key, 8) != 0 do
      :error
    else
      subheader_count = div(max_key, 8) + 1
      subheaders_bytes = subheader_count * 8

      if byte_size(rest) < subheaders_bytes do
        :error
      else
        <<subheaders_bin::binary-size(subheaders_bytes), _::binary>> = rest

        subheaders =
          subheaders_bin
          |> parse_cmap_format2_subheaders([])
          |> Enum.reverse()

        build_cmap_format2(subtable, keys, subheaders)
      end
    end
  end

  defp parse_cmap_format2(_), do: :error

  defp parse_cmap_format4(
         <<4::16-big, _length::16-big, _language::16-big, seg_count_x2::16-big,
           _search_range::16-big, _entry_selector::16-big, _range_shift::16-big, rest::binary>> =
           subtable
       )
       when rem(seg_count_x2, 2) == 0 do
    seg_count = div(seg_count_x2, 2)
    segment_bytes = seg_count * 2

    if seg_count == 0 or byte_size(rest) < segment_bytes * 4 + 2 do
      :error
    else
      <<end_codes_bin::binary-size(segment_bytes), _reserved_pad::16-big,
        start_codes_bin::binary-size(segment_bytes), id_deltas_bin::binary-size(segment_bytes),
        id_range_offsets_bin::binary-size(segment_bytes), _glyph_id_array::binary>> = rest

      end_codes = Binary.u16_list(end_codes_bin)
      start_codes = Binary.u16_list(start_codes_bin)
      id_deltas = Binary.s16_list(id_deltas_bin)
      id_range_offsets = Binary.u16_list(id_range_offsets_bin)

      if lengths_match?(end_codes, start_codes, id_deltas, id_range_offsets) do
        {:ok,
         build_format4_cmap(
           subtable,
           end_codes,
           start_codes,
           id_deltas,
           id_range_offsets
         )}
      else
        :error
      end
    end
  end

  defp parse_cmap_format4(_), do: :error

  defp parse_cmap_format6(
         <<6::16-big, _length::16-big, _language::16-big, first_code::16-big, entry_count::16-big,
           glyph_data::binary>>
       ) do
    required_bytes = entry_count * 2

    if byte_size(glyph_data) < required_bytes do
      :error
    else
      <<glyph_ids_bin::binary-size(required_bytes), _::binary>> = glyph_data
      glyph_ids = Binary.u16_list(glyph_ids_bin)

      cmap_by_code =
        glyph_ids
        |> Enum.with_index(first_code)
        |> Enum.into(%{}, fn {glyph_id, code} -> {code, glyph_id} end)

      {:ok, cmap_by_code}
    end
  end

  defp parse_cmap_format6(_), do: :error

  defp parse_cmap_format8(
         <<8::16-big, _reserved::16-big, _length::32-big, _language::32-big,
           _is32::binary-size(8192), n_groups::32-big, group_data::binary>>
       ) do
    required_bytes = n_groups * 12

    if byte_size(group_data) < required_bytes do
      :error
    else
      <<groups::binary-size(required_bytes), _::binary>> = group_data
      parse_format8_groups(groups, %{})
    end
  end

  defp parse_cmap_format8(_), do: :error

  defp parse_cmap_format10(
         <<10::16-big, _reserved::16-big, _length::32-big, _language::32-big,
           start_char_code::32-big, num_chars::32-big, glyph_data::binary>>
       ) do
    required_bytes = num_chars * 2

    if byte_size(glyph_data) < required_bytes do
      :error
    else
      <<glyph_ids_bin::binary-size(required_bytes), _::binary>> = glyph_data
      glyph_ids = Binary.u16_list(glyph_ids_bin)

      cmap_by_code =
        glyph_ids
        |> Enum.with_index(start_char_code)
        |> Enum.into(%{}, fn {glyph_id, code} -> {code, glyph_id} end)

      {:ok, cmap_by_code}
    end
  end

  defp parse_cmap_format10(_), do: :error

  defp parse_cmap_format12(
         <<12::16-big, _reserved::16-big, _length::32-big, _language::32-big, n_groups::32-big,
           group_data::binary>>
       ) do
    required_bytes = n_groups * 12

    if byte_size(group_data) < required_bytes do
      :error
    else
      <<groups::binary-size(required_bytes), _::binary>> = group_data
      parse_format12_groups(groups, %{})
    end
  end

  defp parse_cmap_format12(_), do: :error

  defp parse_cmap_format13(
         <<13::16-big, _reserved::16-big, _length::32-big, _language::32-big, n_groups::32-big,
           group_data::binary>>
       ) do
    required_bytes = n_groups * 12

    if byte_size(group_data) < required_bytes do
      :error
    else
      <<groups::binary-size(required_bytes), _::binary>> = group_data
      parse_format13_groups(groups, %{})
    end
  end

  defp parse_cmap_format13(_), do: :error
  defp parse_format12_groups(<<>>, acc), do: {:ok, acc}

  defp parse_format12_groups(
         <<start_code::32-big, end_code::32-big, start_glyph_id::32-big, rest::binary>>,
         acc
       )
       when start_code <= end_code do
    updated_acc =
      Enum.reduce(start_code..end_code, acc, fn codepoint, map_acc ->
        glyph_id = start_glyph_id + (codepoint - start_code)
        Map.put(map_acc, codepoint, glyph_id)
      end)

    parse_format12_groups(rest, updated_acc)
  end

  defp parse_format12_groups(_invalid, _acc), do: :error
  defp parse_format13_groups(<<>>, acc), do: {:ok, acc}

  defp parse_format13_groups(
         <<start_code::32-big, end_code::32-big, glyph_id::32-big, rest::binary>>,
         acc
       )
       when start_code <= end_code do
    updated_acc =
      Enum.reduce(start_code..end_code, acc, fn codepoint, map_acc ->
        Map.put(map_acc, codepoint, glyph_id)
      end)

    parse_format13_groups(rest, updated_acc)
  end

  defp parse_format13_groups(_invalid, _acc), do: :error
  defp parse_format8_groups(<<>>, acc), do: {:ok, acc}

  defp parse_format8_groups(
         <<start_code::32-big, end_code::32-big, start_glyph_id::32-big, rest::binary>>,
         acc
       )
       when start_code <= end_code do
    updated_acc =
      Enum.reduce(start_code..end_code, acc, fn codepoint, map_acc ->
        glyph_id = start_glyph_id + (codepoint - start_code)
        Map.put(map_acc, codepoint, glyph_id)
      end)

    parse_format8_groups(rest, updated_acc)
  end

  defp parse_format8_groups(_invalid, _acc), do: :error
  defp parse_cmap_format2_subheaders(<<>>, acc), do: acc

  defp parse_cmap_format2_subheaders(
         <<first_code::16-big, entry_count::16-big, id_delta::16-signed-big,
           id_range_offset::16-big, rest::binary>>,
         acc
       ) do
    parse_cmap_format2_subheaders(
      rest,
      [{first_code, entry_count, id_delta, id_range_offset} | acc]
    )
  end

  defp build_cmap_format2(subtable, keys, subheaders) do
    0..255
    |> Enum.reduce_while({:ok, %{}}, fn high_byte, {:ok, acc} ->
      subheader_key = Enum.at(keys, high_byte, -1)

      if subheader_key < 0 or rem(subheader_key, 8) != 0 do
        {:halt, :error}
      else
        subheader_index = div(subheader_key, 8)

        case Enum.at(subheaders, subheader_index) do
          nil ->
            {:halt, :error}

          subheader ->
            case build_cmap_format2_high_byte(subtable, high_byte, subheader_index, subheader) do
              {:ok, high_byte_map} -> {:cont, {:ok, Map.merge(acc, high_byte_map)}}
              :error -> {:halt, :error}
            end
        end
      end
    end)
    |> case do
      {:ok, cmap_by_code} -> {:ok, cmap_by_code}
      :error -> :error
    end
  end

  defp build_cmap_format2_high_byte(
         _subtable,
         _high_byte,
         _subheader_index,
         {_first_code, 0, _id_delta, _id_range_offset}
       ) do
    {:ok, %{}}
  end

  defp build_cmap_format2_high_byte(
         subtable,
         high_byte,
         subheader_index,
         {first_code, entry_count, id_delta, id_range_offset}
       ) do
    0..(entry_count - 1)
    |> Enum.reduce_while({:ok, %{}}, fn offset, {:ok, acc} ->
      low_byte = first_code + offset

      if low_byte > 0xFF do
        {:halt, :error}
      else
        codepoint = (high_byte <<< 8) + low_byte

        case cmap_format2_glyph_id(
               subtable,
               subheader_index,
               low_byte,
               first_code,
               id_delta,
               id_range_offset
             ) do
          {:ok, glyph_id} ->
            {:cont, {:ok, Map.put(acc, codepoint, glyph_id)}}

          :error ->
            {:halt, :error}
        end
      end
    end)
  end

  defp cmap_format2_glyph_id(
         _subtable,
         _subheader_index,
         low_byte,
         _first_code,
         id_delta,
         0
       ) do
    {:ok, Integer.mod(low_byte + id_delta, 65_536)}
  end

  defp cmap_format2_glyph_id(
         subtable,
         subheader_index,
         low_byte,
         first_code,
         id_delta,
         id_range_offset
       )
       when id_range_offset > 0 do
    id_range_offset_field = 6 + 512 + subheader_index * 8 + 6
    glyph_offset = id_range_offset_field + id_range_offset + (low_byte - first_code) * 2

    case Binary.u16(subtable, glyph_offset) do
      {:ok, 0} ->
        {:ok, 0}

      {:ok, raw_glyph_id} ->
        {:ok, Integer.mod(raw_glyph_id + id_delta, 65_536)}

      :error ->
        :error
    end
  end

  defp build_format4_cmap(subtable, end_codes, start_codes, id_deltas, id_range_offsets) do
    seg_count = length(end_codes)
    id_range_offsets_base = 16 + seg_count * 6

    segments = Enum.zip([end_codes, start_codes, id_deltas, id_range_offsets])

    segments
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{end_code, start_code, _id_delta, _id_range_offset}, idx}, acc ->
      if start_code > end_code or start_code == 0xFFFF do
        acc
      else
        Enum.reduce(start_code..end_code, acc, fn code, range_acc ->
          glyph_id =
            format4_glyph_id(
              code,
              subtable,
              end_codes,
              start_codes,
              id_deltas,
              id_range_offsets,
              id_range_offsets_base,
              idx
            )

          if glyph_id > 0 do
            Map.put(range_acc, code, glyph_id)
          else
            range_acc
          end
        end)
      end
    end)
  end

  defp format4_glyph_id(
         code,
         subtable,
         _end_codes,
         start_codes,
         id_deltas,
         id_range_offsets,
         id_range_offsets_base,
         idx
       ) do
    id_delta = Enum.at(id_deltas, idx)
    id_range_offset = Enum.at(id_range_offsets, idx)

    if id_range_offset == 0 do
      Integer.mod(code + id_delta, 65_536)
    else
      start_code = Enum.at(start_codes, idx)

      word_offset =
        id_range_offsets_base + idx * 2 + id_range_offset + (code - start_code) * 2

      case Binary.u16(subtable, word_offset) do
        {:ok, 0} ->
          0

        {:ok, glyph_index} ->
          Integer.mod(glyph_index + id_delta, 65_536)

        :error ->
          0
      end
    end
  end

  defp lengths_match?(a, b, c, d) do
    length(a) == length(b) and length(b) == length(c) and length(c) == length(d)
  end

  defp cmap_record_priority({3, 10, _offset}), do: 0
  defp cmap_record_priority({3, 1, _offset}), do: 1
  defp cmap_record_priority({3, 0, _offset}), do: 2
  defp cmap_record_priority({0, _encoding, _offset}), do: 3
  defp cmap_record_priority({1, 0, _offset}), do: 4
  defp cmap_record_priority({_platform, _encoding, _offset}), do: 10
end
