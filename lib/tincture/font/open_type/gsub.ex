defmodule Tincture.Font.OpenType.GSUB do
  @moduledoc """
  Parser for the OpenType `GSUB` table: glyph substitution.

  Tincture reads two kinds of substitution:

    * ligatures (lookup type 4) - a sequence of glyphs replaced by one, which
      is how "fi" becomes a single glyph.
    * single substitutions (lookup type 1) - one glyph replaced by one other,
      used for small caps, oldstyle figures and similar stylistic sets.

  Results are mapped back from glyph indices to codepoints via the `cmap`, so
  the typography layer can work in text rather than glyph ids.
  """

  alias Tincture.Font.Binary
  alias Tincture.Font.OpenType.Common

  def parse_gsub_ligatures(data, table_records, cmap_by_code)
      when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    parse_gsub_substitutions(data, table_records, cmap_by_code, :preferred, ["liga"])
  end

  def parse_gsub_ligatures_all_scripts(data, table_records, cmap_by_code)
      when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    parse_gsub_substitutions(data, table_records, cmap_by_code, :all, ["liga"])
  end

  def parse_gsub_substitutions_all_scripts(data, table_records, cmap_by_code)
      when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    parse_gsub_substitutions(data, table_records, cmap_by_code, :all, ["liga", "rlig", "ccmp"])
  end

  defp parse_gsub_substitutions(data, table_records, cmap_by_code, script_scope, feature_tags)
       when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) and
              script_scope in [:preferred, :all] and is_list(feature_tags) do
    case Map.fetch(table_records, "GSUB") do
      {:ok, {offset, length}} ->
        with {:ok, layout_table} <- Binary.slice(data, offset, length),
             {:ok, _scripts, _features, lookup_list_offset} <-
               Common.parse_open_type_layout_table(layout_table) do
          lookup_entries =
            Common.parse_open_type_lookup_entries(layout_table, lookup_list_offset)
            |> then(
              &Common.filter_open_type_lookup_entries_by_features(
                layout_table,
                &1,
                feature_tags,
                script_scope
              )
            )

          layout_table
          |> parse_gsub_ligature_lookup_entries(lookup_entries)
          |> map_gsub_ligatures_to_codepoint_strings(cmap_by_code)
        else
          _ -> %{}
        end

      :error ->
        %{}
    end
  end

  defp parse_gsub_ligature_lookup_entries(layout_table, lookup_entries)
       when is_binary(layout_table) and is_list(lookup_entries) do
    lookup_entries
    |> Enum.flat_map(fn
      %{type: 1, subtable_offsets: subtable_offsets} when is_list(subtable_offsets) ->
        parse_gsub_single_substitution_subtables(layout_table, subtable_offsets)

      %{type: 4, subtable_offsets: subtable_offsets} when is_list(subtable_offsets) ->
        parse_gsub_ligature_subtables(layout_table, subtable_offsets)

      _ ->
        []
    end)
  end

  defp parse_gsub_ligature_subtables(layout_table, subtable_offsets)
       when is_binary(layout_table) and is_list(subtable_offsets) do
    Enum.flat_map(subtable_offsets, fn subtable_offset ->
      parse_gsub_ligature_subtable(layout_table, subtable_offset)
    end)
  end

  defp parse_gsub_ligature_subtable(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    with {:ok, 1} <- Binary.u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- Binary.u16(layout_table, subtable_offset + 2),
         {:ok, ligature_set_count} <- Binary.u16(layout_table, subtable_offset + 4),
         ligature_set_offsets_bin when not is_nil(ligature_set_offsets_bin) <-
           Binary.bytes(layout_table, subtable_offset + 6, ligature_set_count * 2) do
      coverage_glyph_ids =
        Common.parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      ligature_set_offsets =
        ligature_set_offsets_bin
        |> Binary.u16_list()
        |> Enum.map(&(&1 + subtable_offset))

      coverage_glyph_ids
      |> Enum.zip(ligature_set_offsets)
      |> Enum.flat_map(fn {coverage_glyph_id, ligature_set_offset} ->
        parse_gsub_ligature_set(layout_table, ligature_set_offset, coverage_glyph_id)
      end)
    else
      _ -> []
    end
  end

  defp parse_gsub_ligature_subtable(_layout_table, _subtable_offset), do: []

  defp parse_gsub_single_substitution_subtables(layout_table, subtable_offsets)
       when is_binary(layout_table) and is_list(subtable_offsets) do
    Enum.flat_map(subtable_offsets, fn subtable_offset ->
      parse_gsub_single_substitution_subtable(layout_table, subtable_offset)
    end)
  end

  defp parse_gsub_single_substitution_subtable(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    case Binary.u16(layout_table, subtable_offset) do
      {:ok, 1} -> parse_gsub_single_substitution_subtable_format_1(layout_table, subtable_offset)
      {:ok, 2} -> parse_gsub_single_substitution_subtable_format_2(layout_table, subtable_offset)
      _ -> []
    end
  end

  defp parse_gsub_single_substitution_subtable(_layout_table, _subtable_offset), do: []

  defp parse_gsub_single_substitution_subtable_format_1(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    with {:ok, 1} <- Binary.u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- Binary.u16(layout_table, subtable_offset + 2),
         {:ok, delta_glyph_id} <- Binary.s16(layout_table, subtable_offset + 4) do
      coverage_glyph_ids =
        Common.parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      Enum.flat_map(coverage_glyph_ids, fn coverage_glyph_id ->
        substitute_glyph_id = coverage_glyph_id + delta_glyph_id

        if coverage_glyph_id >= 0 and substitute_glyph_id >= 0 do
          [{[coverage_glyph_id], substitute_glyph_id}]
        else
          []
        end
      end)
    else
      _ -> []
    end
  end

  defp parse_gsub_single_substitution_subtable_format_1(_layout_table, _subtable_offset), do: []

  defp parse_gsub_single_substitution_subtable_format_2(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    with {:ok, 2} <- Binary.u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- Binary.u16(layout_table, subtable_offset + 2),
         {:ok, glyph_count} <- Binary.u16(layout_table, subtable_offset + 4),
         substitute_glyph_ids_bin when not is_nil(substitute_glyph_ids_bin) <-
           Binary.bytes(layout_table, subtable_offset + 6, glyph_count * 2) do
      coverage_glyph_ids =
        Common.parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      if length(coverage_glyph_ids) == glyph_count do
        substitute_glyph_ids = Binary.u16_list(substitute_glyph_ids_bin)

        coverage_glyph_ids
        |> Enum.zip(substitute_glyph_ids)
        |> Enum.flat_map(fn
          {coverage_glyph_id, substitute_glyph_id}
          when is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 and
                 is_integer(substitute_glyph_id) and substitute_glyph_id >= 0 ->
            [{[coverage_glyph_id], substitute_glyph_id}]

          _ ->
            []
        end)
      else
        []
      end
    else
      _ -> []
    end
  end

  defp parse_gsub_single_substitution_subtable_format_2(_layout_table, _subtable_offset), do: []

  defp parse_gsub_ligature_set(layout_table, ligature_set_offset, coverage_glyph_id)
       when is_binary(layout_table) and is_integer(ligature_set_offset) and
              ligature_set_offset >= 0 and
              is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 do
    with {:ok, ligature_count} <- Binary.u16(layout_table, ligature_set_offset),
         ligature_offsets_bin when not is_nil(ligature_offsets_bin) <-
           Binary.bytes(layout_table, ligature_set_offset + 2, ligature_count * 2) do
      ligature_offsets_bin
      |> Binary.u16_list()
      |> Enum.flat_map(fn ligature_offset ->
        parse_gsub_ligature(
          layout_table,
          ligature_set_offset + ligature_offset,
          coverage_glyph_id
        )
      end)
    else
      _ -> []
    end
  end

  defp parse_gsub_ligature_set(_layout_table, _ligature_set_offset, _coverage_glyph_id), do: []

  defp parse_gsub_ligature(layout_table, ligature_offset, coverage_glyph_id)
       when is_binary(layout_table) and is_integer(ligature_offset) and ligature_offset >= 0 and
              is_integer(coverage_glyph_id) and coverage_glyph_id >= 0 do
    with {:ok, ligature_glyph_id} <- Binary.u16(layout_table, ligature_offset),
         {:ok, component_count} <- Binary.u16(layout_table, ligature_offset + 2),
         true <- component_count >= 2,
         components_bin when not is_nil(components_bin) <-
           Binary.bytes(layout_table, ligature_offset + 4, (component_count - 1) * 2) do
      source_glyph_ids = [coverage_glyph_id | Binary.u16_list(components_bin)]
      [{source_glyph_ids, ligature_glyph_id}]
    else
      _ -> []
    end
  end

  defp parse_gsub_ligature(_layout_table, _ligature_offset, _coverage_glyph_id), do: []

  defp map_gsub_ligatures_to_codepoint_strings(gsub_ligatures, cmap_by_code)
       when is_list(gsub_ligatures) and is_map(cmap_by_code) do
    glyph_to_codepoint = Common.invert_cmap_by_code(cmap_by_code)

    Enum.reduce(gsub_ligatures, %{}, fn {source_glyph_ids, ligature_glyph_id}, acc ->
      with {:ok, source_codepoints} <-
             glyph_ids_to_codepoints(source_glyph_ids, glyph_to_codepoint),
           {:ok, ligature_codepoint} <- Map.fetch(glyph_to_codepoint, ligature_glyph_id),
           true <- Common.valid_unicode_codepoint?(ligature_codepoint),
           source when is_binary(source) and byte_size(source) > 0 <-
             codepoints_to_string(source_codepoints) do
        Map.put_new(acc, source, <<ligature_codepoint::utf8>>)
      else
        _ -> acc
      end
    end)
  end

  defp map_gsub_ligatures_to_codepoint_strings(_gsub_ligatures, _cmap_by_code), do: %{}

  defp glyph_ids_to_codepoints(glyph_ids, glyph_to_codepoint)
       when is_list(glyph_ids) and is_map(glyph_to_codepoint) do
    glyph_ids
    |> Enum.reduce_while([], fn glyph_id, acc ->
      case Map.fetch(glyph_to_codepoint, glyph_id) do
        {:ok, codepoint} ->
          if Common.valid_unicode_codepoint?(codepoint) do
            {:cont, [codepoint | acc]}
          else
            {:halt, :error}
          end

        _ ->
          {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      reverse_codepoints -> {:ok, Enum.reverse(reverse_codepoints)}
    end
  end

  defp glyph_ids_to_codepoints(_glyph_ids, _glyph_to_codepoint), do: :error

  defp codepoints_to_string(codepoints) when is_list(codepoints) do
    Enum.map_join(codepoints, fn codepoint -> <<codepoint::utf8>> end)
  end
end
