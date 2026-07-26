defmodule Tincture.Font.OpenType.Common do
  @moduledoc """
  The OpenType Layout common table formats, shared by `GPOS` and `GSUB`.

  Both tables have the same outer structure - a script list, a feature list and
  a lookup list - and both reach glyphs through coverage tables. Only the
  innermost subtables differ: `GSUB` substitutes glyphs, `GPOS` positions them.
  That shared outer structure is what lives here.

  The indirection is deep because the format is: a script tag selects a
  language system, which selects feature indices, which select lookup indices,
  which select lookup subtables. A parser that wants "the kerning pairs" has to
  walk all five levels.
  """

  alias Tincture.Font.Binary

  def parse_layout_table_metadata(data, table_records, tag)
      when is_binary(data) and is_map(table_records) and is_binary(tag) do
    case Map.fetch(table_records, tag) do
      {:ok, {offset, length}} ->
        with {:ok, layout_table} <- Binary.slice(data, offset, length),
             {:ok, scripts, features, _lookup_list_offset} <-
               parse_open_type_layout_table(layout_table) do
          {scripts, features}
        else
          _ -> {[], []}
        end

      :error ->
        {[], []}
    end
  end

  def parse_open_type_layout_table(
        <<_major::16-big, _minor::16-big, _script_list_offset::16-big,
          _feature_list_offset::16-big, _lookup_list_offset::16-big, _::binary>> = layout_table
      ) do
    with {:ok, script_list_offset, feature_list_offset, lookup_list_offset} <-
           parse_open_type_layout_offsets(layout_table) do
      scripts = parse_open_type_tag_records(layout_table, script_list_offset)
      features = parse_open_type_tag_records(layout_table, feature_list_offset)
      {:ok, scripts, features, lookup_list_offset}
    else
      _ -> :error
    end
  end

  def parse_open_type_layout_table(_), do: :error

  defp parse_open_type_layout_offsets(
         <<_major::16-big, _minor::16-big, script_list_offset::16-big,
           feature_list_offset::16-big, lookup_list_offset::16-big, _::binary>>
       ) do
    {:ok, script_list_offset, feature_list_offset, lookup_list_offset}
  end

  defp parse_open_type_layout_offsets(_layout_table), do: :error
  def parse_open_type_lookup_entries(layout_table, 0) when is_binary(layout_table), do: []

  def parse_open_type_lookup_entries(layout_table, lookup_list_offset)
      when is_binary(layout_table) and is_integer(lookup_list_offset) and lookup_list_offset > 0 do
    case Binary.u16(layout_table, lookup_list_offset) do
      {:ok, lookup_count} ->
        offsets_offset = lookup_list_offset + 2
        required_bytes = lookup_count * 2

        case Binary.bytes(layout_table, offsets_offset, required_bytes) do
          nil ->
            []

          offsets_bin ->
            offsets_bin
            |> Binary.u16_list()
            |> Enum.reduce([], fn lookup_offset, acc ->
              case parse_open_type_lookup_entry(layout_table, lookup_list_offset, lookup_offset) do
                {:ok, lookup_entry} -> [lookup_entry | acc]
                :error -> acc
              end
            end)
            |> Enum.reverse()
        end

      :error ->
        []
    end
  end

  def parse_open_type_lookup_entries(_layout_table, _lookup_list_offset), do: []

  defp parse_open_type_lookup_entry(layout_table, lookup_list_offset, lookup_offset)
       when is_binary(layout_table) and is_integer(lookup_list_offset) and lookup_list_offset > 0 and
              is_integer(lookup_offset) and lookup_offset > 0 do
    lookup_table_offset = lookup_list_offset + lookup_offset

    with {:ok, lookup_type} <- Binary.u16(layout_table, lookup_table_offset),
         {:ok, _lookup_flag} <- Binary.u16(layout_table, lookup_table_offset + 2),
         {:ok, subtable_count} <- Binary.u16(layout_table, lookup_table_offset + 4),
         subtable_offsets_bin when not is_nil(subtable_offsets_bin) <-
           Binary.bytes(layout_table, lookup_table_offset + 6, subtable_count * 2) do
      subtable_offsets =
        subtable_offsets_bin
        |> Binary.u16_list()
        |> Enum.reduce([], fn subtable_offset, acc ->
          if subtable_offset > 0 do
            [lookup_table_offset + subtable_offset | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      {:ok, %{type: lookup_type, subtable_offsets: subtable_offsets}}
    else
      _ -> :error
    end
  end

  defp parse_open_type_lookup_entry(_layout_table, _lookup_list_offset, _lookup_offset),
    do: :error

  def filter_open_type_lookup_entries_by_features(
        layout_table,
        lookup_entries,
        feature_tags,
        script_scope
      )
      when is_binary(layout_table) and is_list(lookup_entries) and is_list(feature_tags) and
             script_scope in [:preferred, :all] do
    lookup_indices =
      feature_tags
      |> Enum.filter(&(is_binary(&1) and byte_size(&1) == 4))
      |> Enum.flat_map(
        &parse_open_type_feature_linked_lookup_indices(layout_table, &1, script_scope)
      )
      |> Enum.uniq()
      |> Enum.sort()

    case lookup_indices do
      [] ->
        []

      _ ->
        lookup_entries_by_index =
          lookup_entries
          |> Enum.with_index()
          |> Enum.reduce(%{}, fn {lookup_entry, index}, acc ->
            Map.put(acc, index, lookup_entry)
          end)

        lookup_indices
        |> Enum.reduce([], fn lookup_index, acc ->
          case Map.fetch(lookup_entries_by_index, lookup_index) do
            {:ok, lookup_entry} -> [lookup_entry | acc]
            :error -> acc
          end
        end)
        |> Enum.reverse()
    end
  end

  def filter_open_type_lookup_entries_by_features(
        _layout_table,
        lookup_entries,
        _feature_tags,
        _script_scope
      ),
      do: lookup_entries

  defp parse_open_type_feature_linked_lookup_indices(layout_table, feature_tag, script_scope)
       when is_binary(layout_table) and is_binary(feature_tag) and byte_size(feature_tag) == 4 and
              script_scope in [:preferred, :all] do
    with {:ok, script_list_offset, feature_list_offset, _lookup_list_offset} <-
           parse_open_type_layout_offsets(layout_table) do
      script_entries =
        parse_open_type_tag_record_entries(layout_table, script_list_offset)
        |> maybe_select_preferred_script_entries(feature_tag, script_scope)

      feature_indices =
        parse_open_type_feature_indices_for_script_entries(
          layout_table,
          script_list_offset,
          script_entries
        )
        |> Enum.uniq()
        |> Enum.sort()

      parse_open_type_lookup_indices_for_feature_indices(
        layout_table,
        feature_list_offset,
        feature_indices,
        feature_tag
      )
      |> Enum.uniq()
      |> Enum.sort()
    else
      _ -> []
    end
  end

  defp parse_open_type_feature_linked_lookup_indices(_layout_table, _feature_tag, _script_scope),
    do: []

  defp maybe_select_preferred_script_entries(script_entries, feature_tag, :preferred) do
    select_preferred_script_entries(script_entries, feature_tag)
  end

  defp maybe_select_preferred_script_entries(script_entries, _feature_tag, :all),
    do: script_entries

  defp select_preferred_script_entries(script_entries, feature_tag)
       when is_list(script_entries) and is_binary(feature_tag) and byte_size(feature_tag) == 4 do
    preferred_tags = preferred_script_tags_for_feature(feature_tag)

    case pick_first_script_entry_by_tags(script_entries, preferred_tags) do
      nil -> script_entries
      script_entry -> [script_entry]
    end
  end

  defp select_preferred_script_entries(script_entries, _feature_tag), do: script_entries
  defp preferred_script_tags_for_feature("liga"), do: ["latn", "DFLT"]
  defp preferred_script_tags_for_feature("rlig"), do: ["latn", "DFLT"]
  defp preferred_script_tags_for_feature("ccmp"), do: ["latn", "DFLT"]
  defp preferred_script_tags_for_feature("kern"), do: ["latn", "DFLT"]
  defp preferred_script_tags_for_feature(_feature_tag), do: []
  defp pick_first_script_entry_by_tags(_script_entries, []), do: nil

  defp pick_first_script_entry_by_tags(script_entries, [preferred_tag | rest_tags])
       when is_list(script_entries) and is_binary(preferred_tag) do
    case Enum.find(script_entries, fn
           {^preferred_tag, _offset} -> true
           _other -> false
         end) do
      nil -> pick_first_script_entry_by_tags(script_entries, rest_tags)
      script_entry -> script_entry
    end
  end

  defp parse_open_type_feature_indices_for_script_entries(
         layout_table,
         script_list_offset,
         script_entries
       )
       when is_binary(layout_table) and is_integer(script_list_offset) and script_list_offset > 0 and
              is_list(script_entries) do
    Enum.flat_map(script_entries, fn {_script_tag, script_offset} ->
      if is_integer(script_offset) and script_offset > 0 do
        parse_open_type_script_feature_indices(layout_table, script_list_offset + script_offset)
      else
        []
      end
    end)
  end

  defp parse_open_type_feature_indices_for_script_entries(
         _layout_table,
         _script_list_offset,
         _script_entries
       ),
       do: []

  defp parse_open_type_script_feature_indices(layout_table, script_table_offset)
       when is_binary(layout_table) and is_integer(script_table_offset) and
              script_table_offset >= 0 do
    with {:ok, default_lang_sys_offset} <- Binary.u16(layout_table, script_table_offset),
         {:ok, lang_sys_count} <- Binary.u16(layout_table, script_table_offset + 2) do
      named_lang_sys_offsets =
        if lang_sys_count == 0 do
          []
        else
          case Binary.bytes(layout_table, script_table_offset + 4, lang_sys_count * 6) do
            nil -> []
            lang_sys_records_bin -> parse_open_type_lang_sys_offsets(lang_sys_records_bin)
          end
        end

      parse_open_type_preferred_lang_sys_feature_indices(
        layout_table,
        script_table_offset,
        default_lang_sys_offset,
        named_lang_sys_offsets
      )
    else
      _ -> []
    end
  end

  defp parse_open_type_script_feature_indices(_layout_table, _script_table_offset), do: []

  defp parse_open_type_preferred_lang_sys_feature_indices(
         layout_table,
         script_table_offset,
         default_lang_sys_offset,
         named_lang_sys_offsets
       )
       when is_binary(layout_table) and is_integer(script_table_offset) and
              script_table_offset >= 0 and
              is_integer(default_lang_sys_offset) and default_lang_sys_offset >= 0 and
              is_list(named_lang_sys_offsets) do
    default_features =
      parse_open_type_script_lang_sys_feature_indices(
        layout_table,
        script_table_offset,
        default_lang_sys_offset
      )

    if default_features != [] do
      Enum.uniq(default_features)
    else
      named_lang_sys_offsets
      |> Enum.reduce_while([], fn lang_sys_offset, _acc ->
        features =
          parse_open_type_script_lang_sys_feature_indices(
            layout_table,
            script_table_offset,
            lang_sys_offset
          )

        if features == [] do
          {:cont, []}
        else
          {:halt, Enum.uniq(features)}
        end
      end)
    end
  end

  defp parse_open_type_preferred_lang_sys_feature_indices(
         _layout_table,
         _script_table_offset,
         _default_lang_sys_offset,
         _named_lang_sys_offsets
       ),
       do: []

  defp parse_open_type_script_lang_sys_feature_indices(
         layout_table,
         script_table_offset,
         lang_sys_offset
       )
       when is_binary(layout_table) and is_integer(script_table_offset) and
              script_table_offset >= 0 and
              is_integer(lang_sys_offset) and lang_sys_offset > 0 do
    parse_open_type_lang_sys_feature_indices(layout_table, script_table_offset + lang_sys_offset)
  end

  defp parse_open_type_script_lang_sys_feature_indices(
         _layout_table,
         _script_table_offset,
         _lang_sys_offset
       ),
       do: []

  defp parse_open_type_lang_sys_offsets(<<>>), do: []

  defp parse_open_type_lang_sys_offsets(
         <<_lang_sys_tag::binary-size(4), lang_sys_offset::16-big, rest::binary>>
       ) do
    [lang_sys_offset | parse_open_type_lang_sys_offsets(rest)]
  end

  defp parse_open_type_lang_sys_offsets(_invalid_lang_sys_records), do: []

  defp parse_open_type_lang_sys_feature_indices(layout_table, lang_sys_offset)
       when is_binary(layout_table) and is_integer(lang_sys_offset) and lang_sys_offset >= 0 do
    with {:ok, req_feature_index} <- Binary.u16(layout_table, lang_sys_offset + 2),
         {:ok, feature_index_count} <- Binary.u16(layout_table, lang_sys_offset + 4) do
      feature_indices =
        if feature_index_count == 0 do
          []
        else
          case Binary.bytes(layout_table, lang_sys_offset + 6, feature_index_count * 2) do
            nil -> []
            feature_indices_bin -> Binary.u16_list(feature_indices_bin)
          end
        end

      case req_feature_index do
        0xFFFF -> feature_indices
        required_index -> [required_index | feature_indices]
      end
    else
      _ -> []
    end
  end

  defp parse_open_type_lang_sys_feature_indices(_layout_table, _lang_sys_offset), do: []

  defp parse_open_type_lookup_indices_for_feature_indices(
         layout_table,
         feature_list_offset,
         feature_indices,
         feature_tag
       )
       when is_binary(layout_table) and is_integer(feature_list_offset) and
              feature_list_offset > 0 and
              is_list(feature_indices) and is_binary(feature_tag) and byte_size(feature_tag) == 4 do
    feature_indices_set = MapSet.new(feature_indices)

    layout_table
    |> parse_open_type_tag_record_entries(feature_list_offset)
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{^feature_tag, feature_offset}, feature_index} ->
        if MapSet.member?(feature_indices_set, feature_index) and is_integer(feature_offset) and
             feature_offset > 0 do
          parse_open_type_feature_lookup_indices(
            layout_table,
            feature_list_offset + feature_offset
          )
        else
          []
        end

      _other ->
        []
    end)
  end

  defp parse_open_type_lookup_indices_for_feature_indices(
         _layout_table,
         _feature_list_offset,
         _feature_indices,
         _feature_tag
       ),
       do: []

  defp parse_open_type_feature_lookup_indices(layout_table, feature_table_offset)
       when is_binary(layout_table) and is_integer(feature_table_offset) and
              feature_table_offset >= 0 do
    with {:ok, lookup_index_count} <- Binary.u16(layout_table, feature_table_offset + 2),
         lookup_indices_bin when not is_nil(lookup_indices_bin) <-
           Binary.bytes(layout_table, feature_table_offset + 4, lookup_index_count * 2) do
      Binary.u16_list(lookup_indices_bin)
    else
      _ -> []
    end
  end

  defp parse_open_type_feature_lookup_indices(_layout_table, _feature_table_offset), do: []

  def parse_open_type_coverage_table(layout_table, coverage_offset)
      when is_binary(layout_table) and is_integer(coverage_offset) and coverage_offset >= 0 do
    case Binary.u16(layout_table, coverage_offset) do
      {:ok, 1} ->
        with {:ok, glyph_count} <- Binary.u16(layout_table, coverage_offset + 2),
             glyph_ids_bin when not is_nil(glyph_ids_bin) <-
               Binary.bytes(layout_table, coverage_offset + 4, glyph_count * 2) do
          Binary.u16_list(glyph_ids_bin)
        else
          _ -> []
        end

      {:ok, 2} ->
        with {:ok, range_count} <- Binary.u16(layout_table, coverage_offset + 2),
             range_records_bin when not is_nil(range_records_bin) <-
               Binary.bytes(layout_table, coverage_offset + 4, range_count * 6) do
          parse_open_type_coverage_ranges(range_records_bin, [])
        else
          _ -> []
        end

      _ ->
        []
    end
  end

  def parse_open_type_coverage_table(_layout_table, _coverage_offset), do: []
  defp parse_open_type_coverage_ranges(<<>>, acc), do: Enum.reverse(acc)

  defp parse_open_type_coverage_ranges(
         <<start_glyph_id::16-big, end_glyph_id::16-big, _start_coverage_index::16-big,
           rest::binary>>,
         acc
       )
       when start_glyph_id <= end_glyph_id do
    parse_open_type_coverage_ranges(
      rest,
      Enum.reverse(start_glyph_id..end_glyph_id, acc)
    )
  end

  defp parse_open_type_coverage_ranges(_range_records_bin, acc), do: Enum.reverse(acc)

  def invert_cmap_by_code(cmap_by_code) when is_map(cmap_by_code) do
    Enum.reduce(cmap_by_code, %{}, fn {codepoint, glyph_id}, acc ->
      case Map.get(acc, glyph_id) do
        nil ->
          Map.put(acc, glyph_id, codepoint)

        existing_codepoint when codepoint < existing_codepoint ->
          Map.put(acc, glyph_id, codepoint)

        _existing_codepoint ->
          acc
      end
    end)
  end

  def valid_unicode_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0 and codepoint <= 0x10FFFF,
      do: true

  def valid_unicode_codepoint?(_codepoint), do: false
  defp parse_open_type_tag_records(layout_table, 0) when is_binary(layout_table), do: []

  defp parse_open_type_tag_records(layout_table, list_offset)
       when is_binary(layout_table) and is_integer(list_offset) and list_offset > 0 do
    layout_table
    |> parse_open_type_tag_record_entries(list_offset)
    |> Enum.map(&elem(&1, 0))
  end

  defp parse_open_type_tag_records(_layout_table, _list_offset), do: []
  defp parse_open_type_tag_record_entries(layout_table, 0) when is_binary(layout_table), do: []

  defp parse_open_type_tag_record_entries(layout_table, list_offset)
       when is_binary(layout_table) and is_integer(list_offset) and list_offset > 0 do
    table_size = byte_size(layout_table)

    if list_offset + 2 > table_size do
      []
    else
      count_offset = list_offset
      <<_prefix::binary-size(count_offset), count::16-big, after_count::binary>> = layout_table
      required_record_bytes = count * 6

      if byte_size(after_count) < required_record_bytes do
        []
      else
        <<record_bytes::binary-size(required_record_bytes), _::binary>> = after_count

        record_bytes
        |> parse_open_type_tag_record_entries_from_bytes([])
        |> Enum.reverse()
      end
    end
  end

  defp parse_open_type_tag_record_entries(_layout_table, _list_offset), do: []
  defp parse_open_type_tag_record_entries_from_bytes(<<>>, acc), do: acc

  defp parse_open_type_tag_record_entries_from_bytes(
         <<tag::binary-size(4), offset::16-big, rest::binary>>,
         acc
       ) do
    parse_open_type_tag_record_entries_from_bytes(rest, [{tag, offset} | acc])
  end
end
