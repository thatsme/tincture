defmodule Tincture.Font.TTF.Layout do
  @moduledoc """
  Parsers for the OpenType advanced typography tables, `GPOS` and `GSUB`.

  `GSUB` substitutes glyphs (ligatures, alternates); `GPOS` positions them
  (kerning pairs, class-based adjustments). They are separate tables but share
  the same machinery - script and feature lists, lookup tables, coverage tables
  and class definitions - which is why they live together here rather than in
  two modules that would each need half of it.

  Extracted from `Tincture.Font.TTF`, where these functions were the largest
  single cluster and reachable only through `parse_basic_tables/1`.

  ## Guardrails

  A class-based `GPOS` subtable declares a pair matrix of `class1 * class2`
  entries. A malformed or hostile font can declare one large enough to exhaust
  memory, so expansion is capped and over-large subtables are skipped with a
  log line. Skips are counted so callers can surface them; the benchmark suite
  asserts the count stays at zero for well-formed fonts.
  """

  import Bitwise
  require Logger

  alias Tincture.Font.Binary

  # Caps on how much a single GPOS subtable may expand. A malformed or hostile
  # font can declare a class-pair matrix large enough to exhaust memory, so
  # oversized subtables are skipped and counted rather than expanded.
  @max_gpos_pair_set_records 10_000
  @max_gpos_class_pair_records 10_000
  @max_gpos_expanded_class_pairs 10_000
  @max_gpos_class_def_entries 10_000

  @gpos_guardrail_skip_count_key {__MODULE__, :gpos_guardrail_skip_count}

  def parse_layout_metadata(data, table_records, cmap_by_code) do
    {gsub_scripts, gsub_features} = parse_layout_table_metadata(data, table_records, "GSUB")
    {gpos_scripts, gpos_features} = parse_layout_table_metadata(data, table_records, "GPOS")
    gsub_ligatures = parse_gsub_ligatures(data, table_records, cmap_by_code)
    gsub_ligatures_all = parse_gsub_ligatures_all_scripts(data, table_records, cmap_by_code)

    gsub_substitutions_all =
      parse_gsub_substitutions_all_scripts(data, table_records, cmap_by_code)

    gpos_pair_kerns = parse_gpos_pair_kerns(data, table_records, cmap_by_code)
    gpos_guardrail_skips = guardrail_skips()

    {:ok,
     %{
       gsub_scripts: gsub_scripts,
       gsub_features: gsub_features,
       gsub_ligatures: gsub_ligatures,
       gsub_ligatures_all: gsub_ligatures_all,
       gsub_substitutions_all: gsub_substitutions_all,
       gpos_scripts: gpos_scripts,
       gpos_features: gpos_features,
       gpos_pair_kerns: gpos_pair_kerns,
       gpos_guardrail_skips: gpos_guardrail_skips
     }}
  end

  defp parse_layout_table_metadata(data, table_records, tag)
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

  defp parse_open_type_layout_table(
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

  defp parse_open_type_layout_table(_), do: :error

  defp parse_open_type_layout_offsets(
         <<_major::16-big, _minor::16-big, script_list_offset::16-big,
           feature_list_offset::16-big, lookup_list_offset::16-big, _::binary>>
       ) do
    {:ok, script_list_offset, feature_list_offset, lookup_list_offset}
  end

  defp parse_open_type_layout_offsets(_layout_table), do: :error

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
               parse_open_type_layout_table(layout_table) do
          lookup_entries =
            parse_open_type_lookup_entries(layout_table, lookup_list_offset)
            |> then(
              &filter_open_type_lookup_entries_by_features(
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

  defp parse_open_type_lookup_entries(layout_table, 0) when is_binary(layout_table), do: []

  defp parse_open_type_lookup_entries(layout_table, lookup_list_offset)
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

  defp parse_open_type_lookup_entries(_layout_table, _lookup_list_offset), do: []

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

  defp filter_open_type_lookup_entries_by_feature(layout_table, lookup_entries, feature_tag)
       when is_binary(layout_table) and is_list(lookup_entries) and is_binary(feature_tag) and
              byte_size(feature_tag) == 4 do
    filter_open_type_lookup_entries_by_feature(
      layout_table,
      lookup_entries,
      feature_tag,
      :preferred
    )
  end

  defp filter_open_type_lookup_entries_by_feature(_layout_table, lookup_entries, _feature_tag),
    do: lookup_entries

  defp filter_open_type_lookup_entries_by_feature(
         layout_table,
         lookup_entries,
         feature_tag,
         script_scope
       )
       when is_binary(layout_table) and is_list(lookup_entries) and is_binary(feature_tag) and
              byte_size(feature_tag) == 4 and script_scope in [:preferred, :all] do
    filter_open_type_lookup_entries_by_features(
      layout_table,
      lookup_entries,
      [feature_tag],
      script_scope
    )
  end

  defp filter_open_type_lookup_entries_by_feature(
         _layout_table,
         lookup_entries,
         _feature_tag,
         _script_scope
       ),
       do: lookup_entries

  defp filter_open_type_lookup_entries_by_features(
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

  defp filter_open_type_lookup_entries_by_features(
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
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

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
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

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
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

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

  def parse_gpos_pair_kerns(data, table_records, cmap_by_code)
      when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    candidate_glyph_ids = cmap_candidate_glyph_ids(cmap_by_code)

    case Map.fetch(table_records, "GPOS") do
      {:ok, {offset, length}} ->
        with {:ok, layout_table} <- Binary.slice(data, offset, length),
             {:ok, _scripts, _features, lookup_list_offset} <-
               parse_open_type_layout_table(layout_table) do
          lookup_entries =
            parse_open_type_lookup_entries(layout_table, lookup_list_offset)
            |> then(&filter_open_type_lookup_entries_by_feature(layout_table, &1, "kern"))

          layout_table
          |> parse_gpos_pair_lookup_entries(lookup_entries, candidate_glyph_ids)
          |> map_gpos_pair_adjustments_to_codepoints(cmap_by_code)
        else
          _ -> %{}
        end

      :error ->
        %{}
    end
  end

  defp parse_gpos_pair_lookup_entries(layout_table, lookup_entries, candidate_glyph_ids)
       when is_binary(layout_table) and is_list(lookup_entries) and is_list(candidate_glyph_ids) do
    lookup_entries
    |> Enum.flat_map(fn
      %{type: 2, subtable_offsets: subtable_offsets} when is_list(subtable_offsets) ->
        parse_gpos_pair_subtables(layout_table, subtable_offsets, candidate_glyph_ids)

      _ ->
        []
    end)
  end

  defp parse_gpos_pair_subtables(layout_table, subtable_offsets, candidate_glyph_ids)
       when is_binary(layout_table) and is_list(subtable_offsets) and is_list(candidate_glyph_ids) do
    Enum.flat_map(subtable_offsets, fn subtable_offset ->
      parse_gpos_pair_subtable(layout_table, subtable_offset, candidate_glyph_ids)
    end)
  end

  defp parse_gpos_pair_subtable(layout_table, subtable_offset, candidate_glyph_ids)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 and
              is_list(candidate_glyph_ids) do
    case Binary.u16(layout_table, subtable_offset) do
      {:ok, 1} ->
        parse_gpos_pair_subtable_format_1(layout_table, subtable_offset)

      {:ok, 2} ->
        parse_gpos_pair_subtable_format_2(layout_table, subtable_offset, candidate_glyph_ids)

      _ ->
        []
    end
  end

  defp parse_gpos_pair_subtable(_layout_table, _subtable_offset, _candidate_glyph_ids), do: []

  defp parse_gpos_pair_subtable_format_1(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    with {:ok, 1} <- Binary.u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- Binary.u16(layout_table, subtable_offset + 2),
         {:ok, value_format_1} <- Binary.u16(layout_table, subtable_offset + 4),
         {:ok, value_format_2} <- Binary.u16(layout_table, subtable_offset + 6),
         {:ok, pair_set_count} <- Binary.u16(layout_table, subtable_offset + 8),
         pair_set_offsets_bin when not is_nil(pair_set_offsets_bin) <-
           Binary.bytes(layout_table, subtable_offset + 10, pair_set_count * 2),
         {:ok, value_record_1_size} <- gpos_value_record_size(value_format_1),
         {:ok, value_record_2_size} <- gpos_value_record_size(value_format_2) do
      coverage_glyph_ids =
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      pair_set_offsets =
        pair_set_offsets_bin
        |> Binary.u16_list()
        |> Enum.map(&(&1 + subtable_offset))

      coverage_glyph_count = length(coverage_glyph_ids)

      if coverage_glyph_count != pair_set_count do
        increment_guardrail_skips()

        Logger.warning(
          "GPOS pair subtable skipped: coverage_glyph_count=#{coverage_glyph_count} pair_set_count=#{pair_set_count} mismatch"
        )

        []
      else
        coverage_glyph_ids
        |> Enum.zip(pair_set_offsets)
        |> Enum.flat_map(fn {left_glyph_id, pair_set_offset} ->
          parse_gpos_pair_set(
            layout_table,
            pair_set_offset,
            left_glyph_id,
            value_format_1,
            value_format_2,
            value_record_1_size,
            value_record_2_size
          )
        end)
      end
    else
      _ -> []
    end
  end

  defp parse_gpos_pair_subtable_format_1(_layout_table, _subtable_offset), do: []

  defp parse_gpos_pair_subtable_format_2(layout_table, subtable_offset, candidate_glyph_ids)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 and
              is_list(candidate_glyph_ids) do
    with {:ok, 2} <- Binary.u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- Binary.u16(layout_table, subtable_offset + 2),
         {:ok, value_format_1} <- Binary.u16(layout_table, subtable_offset + 4),
         {:ok, value_format_2} <- Binary.u16(layout_table, subtable_offset + 6),
         {:ok, class_def_1_offset} <- Binary.u16(layout_table, subtable_offset + 8),
         {:ok, class_def_2_offset} <- Binary.u16(layout_table, subtable_offset + 10),
         {:ok, class_1_count} <- Binary.u16(layout_table, subtable_offset + 12),
         {:ok, class_2_count} <- Binary.u16(layout_table, subtable_offset + 14),
         {:ok, value_record_1_size} <- gpos_value_record_size(value_format_1),
         {:ok, value_record_2_size} <- gpos_value_record_size(value_format_2),
         true <- class_1_count > 0 and class_2_count > 0,
         {:ok, class_adjustments} <-
           parse_gpos_class_pair_adjustments(
             layout_table,
             subtable_offset + 16,
             class_1_count,
             class_2_count,
             value_format_1,
             value_format_2,
             value_record_1_size,
             value_record_2_size
           ),
         {:ok, class_def_1} <-
           parse_open_type_class_def_table(layout_table, subtable_offset + class_def_1_offset),
         {:ok, class_def_2} <-
           parse_open_type_class_def_table(layout_table, subtable_offset + class_def_2_offset) do
      coverage_glyph_ids =
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      expand_gpos_class_pair_adjustments(
        coverage_glyph_ids,
        class_def_1,
        class_def_2,
        class_adjustments,
        candidate_glyph_ids,
        class_1_count,
        class_2_count
      )
    else
      {:error, :guardrail_class_matrix} ->
        []

      {:error, :guardrail_class_def} ->
        []

      {:error, :malformed_class_def} ->
        {class_1_count, class_2_count} =
          gpos_pair_subtable_class_counts(layout_table, subtable_offset)

        increment_guardrail_skips()

        Logger.warning(
          "GPOS class-pair subtable skipped: malformed class definition tables class1_count=#{class_1_count} class2_count=#{class_2_count}"
        )

        []

      false ->
        {class_1_count, class_2_count} =
          gpos_pair_subtable_class_counts(layout_table, subtable_offset)

        increment_guardrail_skips()

        Logger.warning(
          "GPOS class-pair subtable skipped: class1_count=#{class_1_count} class2_count=#{class_2_count} must both be > 0"
        )

        []

      :error ->
        {class_1_count, class_2_count} =
          gpos_pair_subtable_class_counts(layout_table, subtable_offset)

        increment_guardrail_skips()

        Logger.warning(
          "GPOS class-pair subtable skipped: malformed class adjustment records class1_count=#{class_1_count} class2_count=#{class_2_count}"
        )

        []

      _ ->
        []
    end
  end

  defp parse_gpos_pair_subtable_format_2(_layout_table, _subtable_offset, _candidate_glyph_ids),
    do: []

  defp gpos_pair_subtable_class_counts(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    class_1_count =
      Binary.u16(layout_table, subtable_offset + 12)
      |> case do
        {:ok, value} -> value
        _ -> 0
      end

    class_2_count =
      Binary.u16(layout_table, subtable_offset + 14)
      |> case do
        {:ok, value} -> value
        _ -> 0
      end

    {class_1_count, class_2_count}
  end

  defp gpos_pair_subtable_class_counts(_layout_table, _subtable_offset), do: {0, 0}

  defp parse_gpos_class_pair_adjustments(
         layout_table,
         class_records_offset,
         class_1_count,
         class_2_count,
         value_format_1,
         value_format_2,
         value_record_1_size,
         value_record_2_size
       )
       when is_binary(layout_table) and is_integer(class_records_offset) and
              class_records_offset >= 0 and is_integer(class_1_count) and class_1_count > 0 and
              is_integer(class_2_count) and class_2_count > 0 and is_integer(value_format_1) and
              is_integer(value_format_2) and is_integer(value_record_1_size) and
              value_record_1_size >= 0 and is_integer(value_record_2_size) and
              value_record_2_size >= 0 do
    total_records = class_1_count * class_2_count

    if total_records > @max_gpos_class_pair_records do
      increment_guardrail_skips()

      Logger.warning(
        "GPOS class-pair matrix skipped: class1_count=#{class_1_count} class2_count=#{class_2_count} records=#{total_records} exceeds limit=#{@max_gpos_class_pair_records}"
      )

      {:error, :guardrail_class_matrix}
    else
      class_2_record_size = value_record_1_size + value_record_2_size
      class_1_record_size = class_2_count * class_2_record_size

      0..(class_1_count - 1)
      |> Enum.reduce_while({:ok, %{}}, fn class_1_index, {:ok, acc} ->
        0..(class_2_count - 1)
        |> Enum.reduce_while({:ok, acc}, fn class_2_index, {:ok, inner_acc} ->
          record_offset =
            class_records_offset + class_1_index * class_1_record_size +
              class_2_index * class_2_record_size

          with {:ok, x_advance_adjustment_1, parsed_value_record_1_size} <-
                 parse_gpos_value_record_x_advance(layout_table, record_offset, value_format_1),
               true <- parsed_value_record_1_size == value_record_1_size,
               {:ok, x_advance_adjustment_2, parsed_value_record_2_size} <-
                 parse_gpos_value_record_x_advance(
                   layout_table,
                   record_offset + value_record_1_size,
                   value_format_2
                 ),
               true <- parsed_value_record_2_size == value_record_2_size do
            x_advance_adjustment = x_advance_adjustment_1 + x_advance_adjustment_2

            next_inner_acc =
              if x_advance_adjustment != 0 do
                Map.put(inner_acc, {class_1_index, class_2_index}, x_advance_adjustment)
              else
                inner_acc
              end

            {:cont, {:ok, next_inner_acc}}
          else
            _ ->
              {:halt, :error}
          end
        end)
        |> case do
          {:ok, next_acc} -> {:cont, {:ok, next_acc}}
          :error -> {:halt, :error}
        end
      end)
    end
  end

  defp parse_gpos_class_pair_adjustments(
         _layout_table,
         _class_records_offset,
         _class_1_count,
         _class_2_count,
         _value_format_1,
         _value_format_2,
         _value_record_1_size,
         _value_record_2_size
       ),
       do: :error

  # nil means the key was absent before this parse, so remove it rather than
  # leaving a zero behind and making the process dictionary grow by one key per
  # process that ever parsed a font.
  @doc """
  Begin a guardrail-counting scope, returning the previous count to restore.

  The counter is process-local because it is incremented from seven places deep
  inside the GPOS pair and class parsers and read once at the end; threading it
  back through those `with` chains would reshape the control flow of the code
  that produces kerning pairs.

  Callers must pair this with `end_guardrail_scope/1` in an `after` block. That
  makes the counter re-entrancy-safe: without it a nested parse would zero an
  enclosing parse's accumulated count and silently under-report.
  """
  @spec begin_guardrail_scope() :: term()
  def begin_guardrail_scope do
    previous = Process.get(@gpos_guardrail_skip_count_key)
    Process.put(@gpos_guardrail_skip_count_key, 0)
    previous
  end

  @doc """
  End a guardrail-counting scope, restoring what `begin_guardrail_scope/0`
  returned.
  """
  @spec end_guardrail_scope(term()) :: :ok
  # nil means the key was absent before this scope, so remove it rather than
  # leaving a zero behind and making the process dictionary grow by one key per
  # process that ever parsed a font.
  def end_guardrail_scope(nil) do
    Process.delete(@gpos_guardrail_skip_count_key)
    :ok
  end

  def end_guardrail_scope(previous_skip_count) do
    Process.put(@gpos_guardrail_skip_count_key, previous_skip_count)
    :ok
  end

  @doc "How many GPOS subtables were skipped by a guardrail in the current scope."
  @spec guardrail_skips() :: non_neg_integer()
  def guardrail_skips do
    case Process.get(@gpos_guardrail_skip_count_key, 0) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end

  defp increment_guardrail_skips do
    Process.put(@gpos_guardrail_skip_count_key, guardrail_skips() + 1)
    :ok
  end

  defp expand_gpos_class_pair_adjustments(
         coverage_glyph_ids,
         class_def_1,
         class_def_2,
         class_adjustments,
         candidate_glyph_ids,
         class_1_count,
         class_2_count
       )
       when is_list(coverage_glyph_ids) and is_map(class_def_1) and is_map(class_def_2) and
              is_map(class_adjustments) and is_list(candidate_glyph_ids) and
              is_integer(class_1_count) and class_1_count > 0 and is_integer(class_2_count) and
              class_2_count > 0 do
    candidate_glyph_set = MapSet.new(candidate_glyph_ids)

    right_glyphs_by_class =
      candidate_glyph_ids
      |> Enum.filter(&(is_integer(&1) and &1 >= 0))
      |> Enum.reduce(%{}, fn glyph_id, acc ->
        class_2 = Map.get(class_def_2, glyph_id, 0)

        if is_integer(class_2) and class_2 >= 0 and class_2 < class_2_count do
          Map.update(acc, class_2, [glyph_id], &[glyph_id | &1])
        else
          acc
        end
      end)

    adjustments_by_class_1 =
      Enum.reduce(class_adjustments, %{}, fn
        {{class_1, class_2}, adjustment}, acc
        when is_integer(class_1) and is_integer(class_2) and is_integer(adjustment) and
               class_1 >= 0 and class_1 < class_1_count and class_2 >= 0 and
               class_2 < class_2_count and adjustment != 0 ->
          Map.update(acc, class_1, [{class_2, adjustment}], &[{class_2, adjustment} | &1])

        _, acc ->
          acc
      end)

    filtered_coverage_glyph_ids =
      Enum.filter(coverage_glyph_ids, fn glyph_id ->
        is_integer(glyph_id) and glyph_id >= 0 and MapSet.member?(candidate_glyph_set, glyph_id)
      end)

    case collect_expanded_gpos_class_pairs(
           filtered_coverage_glyph_ids,
           class_def_1,
           adjustments_by_class_1,
           right_glyphs_by_class,
           class_1_count,
           @max_gpos_expanded_class_pairs,
           [],
           0
         ) do
      {:ok, pairs} ->
        pairs

      {:error, estimated_pairs} ->
        increment_guardrail_skips()

        Logger.warning(
          "GPOS class-pair expansion skipped: estimated_pairs=#{estimated_pairs} exceeds limit=#{@max_gpos_expanded_class_pairs}"
        )

        []
    end
  end

  defp expand_gpos_class_pair_adjustments(
         _coverage_glyph_ids,
         _class_def_1,
         _class_def_2,
         _class_adjustments,
         _candidate_glyph_ids,
         _class_1_count,
         _class_2_count
       ),
       do: []

  defp collect_expanded_gpos_class_pairs(
         [],
         _class_def_1,
         _adjustments_by_class_1,
         _right_glyphs_by_class,
         _class_1_count,
         _limit,
         acc,
         _pair_count
       ),
       do: {:ok, Enum.reverse(acc)}

  defp collect_expanded_gpos_class_pairs(
         [left_glyph_id | rest_left_glyph_ids],
         class_def_1,
         adjustments_by_class_1,
         right_glyphs_by_class,
         class_1_count,
         limit,
         acc,
         pair_count
       )
       when is_map(class_def_1) and is_map(adjustments_by_class_1) and
              is_map(right_glyphs_by_class) and is_integer(class_1_count) and class_1_count > 0 and
              is_integer(limit) and limit > 0 and is_list(acc) and is_integer(pair_count) and
              pair_count >= 0 do
    class_1 = Map.get(class_def_1, left_glyph_id, 0)

    if is_integer(class_1) and class_1 >= 0 and class_1 < class_1_count do
      class_1
      |> then(&Map.get(adjustments_by_class_1, &1, []))
      |> Enum.reduce_while({acc, pair_count}, fn {class_2, adjustment},
                                                 {inner_acc, inner_count} ->
        right_glyph_ids = Map.get(right_glyphs_by_class, class_2, [])
        next_count = inner_count + length(right_glyph_ids)

        if next_count > limit do
          {:halt, {:limit, next_count}}
        else
          next_acc =
            Enum.reduce(right_glyph_ids, inner_acc, fn right_glyph_id, pairs_acc ->
              [{{left_glyph_id, right_glyph_id}, adjustment} | pairs_acc]
            end)

          {:cont, {next_acc, next_count}}
        end
      end)
      |> case do
        {:limit, estimated_pairs} ->
          {:error, estimated_pairs}

        {next_acc, next_count} ->
          collect_expanded_gpos_class_pairs(
            rest_left_glyph_ids,
            class_def_1,
            adjustments_by_class_1,
            right_glyphs_by_class,
            class_1_count,
            limit,
            next_acc,
            next_count
          )
      end
    else
      collect_expanded_gpos_class_pairs(
        rest_left_glyph_ids,
        class_def_1,
        adjustments_by_class_1,
        right_glyphs_by_class,
        class_1_count,
        limit,
        acc,
        pair_count
      )
    end
  end

  defp cmap_candidate_glyph_ids(cmap_by_code) when is_map(cmap_by_code) do
    cmap_by_code
    |> Map.values()
    |> Enum.filter(&(is_integer(&1) and &1 >= 0))
    |> Enum.uniq()
  end

  defp cmap_candidate_glyph_ids(_cmap_by_code), do: []

  defp parse_gpos_pair_set(
         layout_table,
         pair_set_offset,
         left_glyph_id,
         value_format_1,
         value_format_2,
         value_record_1_size,
         value_record_2_size
       )
       when is_binary(layout_table) and is_integer(pair_set_offset) and pair_set_offset >= 0 and
              is_integer(left_glyph_id) and left_glyph_id >= 0 and is_integer(value_format_1) and
              is_integer(value_format_2) and is_integer(value_record_1_size) and
              value_record_1_size >= 0 and is_integer(value_record_2_size) and
              value_record_2_size >= 0 do
    with {:ok, pair_value_count} <- Binary.u16(layout_table, pair_set_offset) do
      if pair_value_count > @max_gpos_pair_set_records do
        increment_guardrail_skips()

        Logger.warning(
          "GPOS pair-set skipped: left_glyph_id=#{left_glyph_id} pair_value_count=#{pair_value_count} exceeds limit=#{@max_gpos_pair_set_records}"
        )

        []
      else
        case parse_gpos_pair_value_records(
               layout_table,
               pair_set_offset + 2,
               pair_value_count,
               left_glyph_id,
               value_format_1,
               value_format_2,
               value_record_1_size,
               value_record_2_size,
               []
             ) do
          {:ok, pairs} ->
            Enum.reverse(pairs)

          :error ->
            []
        end
      end
    else
      _ -> []
    end
  end

  defp parse_gpos_pair_set(
         _layout_table,
         _pair_set_offset,
         _left_glyph_id,
         _value_format_1,
         _value_format_2,
         _value_record_1_size,
         _value_record_2_size
       ),
       do: []

  defp parse_gpos_pair_value_records(
         _layout_table,
         _offset,
         0,
         _left_glyph_id,
         _value_format_1,
         _value_format_2,
         _value_record_1_size,
         _value_record_2_size,
         acc
       ),
       do: {:ok, acc}

  defp parse_gpos_pair_value_records(
         layout_table,
         offset,
         remaining,
         left_glyph_id,
         value_format_1,
         value_format_2,
         value_record_1_size,
         value_record_2_size,
         acc
       )
       when is_binary(layout_table) and is_integer(offset) and offset >= 0 and
              is_integer(remaining) and remaining > 0 and is_integer(left_glyph_id) and
              left_glyph_id >= 0 and is_integer(value_format_1) and is_integer(value_format_2) and
              is_integer(value_record_1_size) and value_record_1_size >= 0 and
              is_integer(value_record_2_size) and value_record_2_size >= 0 do
    with {:ok, right_glyph_id} <- Binary.u16(layout_table, offset),
         {:ok, x_advance_adjustment_1, parsed_value_record_1_size} <-
           parse_gpos_value_record_x_advance(layout_table, offset + 2, value_format_1),
         true <- parsed_value_record_1_size == value_record_1_size,
         {:ok, x_advance_adjustment_2, parsed_value_record_2_size} <-
           parse_gpos_value_record_x_advance(
             layout_table,
             offset + 2 + value_record_1_size,
             value_format_2
           ),
         true <- parsed_value_record_2_size == value_record_2_size do
      x_advance_adjustment = x_advance_adjustment_1 + x_advance_adjustment_2

      next_acc =
        if x_advance_adjustment != 0 do
          [{{left_glyph_id, right_glyph_id}, x_advance_adjustment} | acc]
        else
          acc
        end

      next_offset = offset + 2 + value_record_1_size + value_record_2_size

      parse_gpos_pair_value_records(
        layout_table,
        next_offset,
        remaining - 1,
        left_glyph_id,
        value_format_1,
        value_format_2,
        value_record_1_size,
        value_record_2_size,
        next_acc
      )
    else
      _ ->
        :error
    end
  end

  defp parse_gpos_value_record_x_advance(layout_table, offset, value_format)
       when is_binary(layout_table) and is_integer(offset) and offset >= 0 and
              is_integer(value_format) and value_format >= 0 do
    parse_gpos_value_record_fields(
      layout_table,
      offset,
      value_format,
      gpos_value_record_field_specs(),
      0,
      0
    )
  end

  defp parse_gpos_value_record_x_advance(_layout_table, _offset, _value_format), do: :error

  defp parse_gpos_value_record_fields(
         _layout_table,
         _offset,
         _value_format,
         [],
         x_advance_adjustment,
         bytes_read
       ),
       do: {:ok, x_advance_adjustment, bytes_read}

  defp parse_gpos_value_record_fields(
         layout_table,
         offset,
         value_format,
         [{bitmask, :u16} | rest],
         x_advance_adjustment,
         bytes_read
       ) do
    if (value_format &&& bitmask) != 0 do
      case Binary.u16(layout_table, offset + bytes_read) do
        {:ok, _value} ->
          parse_gpos_value_record_fields(
            layout_table,
            offset,
            value_format,
            rest,
            x_advance_adjustment,
            bytes_read + 2
          )

        :error ->
          :error
      end
    else
      parse_gpos_value_record_fields(
        layout_table,
        offset,
        value_format,
        rest,
        x_advance_adjustment,
        bytes_read
      )
    end
  end

  defp parse_gpos_value_record_fields(
         layout_table,
         offset,
         value_format,
         [{bitmask, :s16_x_advance} | rest],
         x_advance_adjustment,
         bytes_read
       ) do
    if (value_format &&& bitmask) != 0 do
      case Binary.s16(layout_table, offset + bytes_read) do
        {:ok, x_advance} ->
          parse_gpos_value_record_fields(
            layout_table,
            offset,
            value_format,
            rest,
            x_advance_adjustment + x_advance,
            bytes_read + 2
          )

        :error ->
          :error
      end
    else
      parse_gpos_value_record_fields(
        layout_table,
        offset,
        value_format,
        rest,
        x_advance_adjustment,
        bytes_read
      )
    end
  end

  defp gpos_value_record_size(value_format)
       when is_integer(value_format) and value_format >= 0 and value_format <= 0xFFFF do
    bits_set =
      value_format
      |> Integer.digits(2)
      |> Enum.sum()

    {:ok, bits_set * 2}
  end

  defp gpos_value_record_size(_value_format), do: :error

  defp gpos_value_record_field_specs do
    [
      {0x0001, :u16},
      {0x0002, :u16},
      {0x0004, :s16_x_advance},
      {0x0008, :u16},
      {0x0010, :u16},
      {0x0020, :u16},
      {0x0040, :u16},
      {0x0080, :u16}
    ]
  end

  defp parse_open_type_coverage_table(layout_table, coverage_offset)
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

  defp parse_open_type_coverage_table(_layout_table, _coverage_offset), do: []
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

  defp parse_open_type_class_def_table(layout_table, class_def_offset)
       when is_binary(layout_table) and is_integer(class_def_offset) and class_def_offset >= 0 do
    case Binary.u16(layout_table, class_def_offset) do
      {:ok, 1} ->
        with {:ok, start_glyph_id} <- Binary.u16(layout_table, class_def_offset + 2),
             {:ok, glyph_count} <- Binary.u16(layout_table, class_def_offset + 4),
             class_values_bin when not is_nil(class_values_bin) <-
               Binary.bytes(layout_table, class_def_offset + 6, glyph_count * 2) do
          if glyph_count > @max_gpos_class_def_entries do
            increment_guardrail_skips()

            Logger.warning(
              "GPOS class definition skipped: format=1 entries=#{glyph_count} exceeds limit=#{@max_gpos_class_def_entries}"
            )

            {:error, :guardrail_class_def}
          else
            class_values = Binary.u16_list(class_values_bin)

            class_definitions =
              Enum.reduce(class_values, {start_glyph_id, %{}}, fn class_id, {glyph_id, acc} ->
                {glyph_id + 1, Map.put(acc, glyph_id, class_id)}
              end)
              |> elem(1)

            {:ok, class_definitions}
          end
        else
          _ -> {:error, :malformed_class_def}
        end

      {:ok, 2} ->
        with {:ok, class_range_count} <- Binary.u16(layout_table, class_def_offset + 2),
             class_ranges_bin when not is_nil(class_ranges_bin) <-
               Binary.bytes(layout_table, class_def_offset + 4, class_range_count * 6) do
          case parse_open_type_class_ranges_with_limit(
                 class_ranges_bin,
                 %{},
                 0,
                 @max_gpos_class_def_entries
               ) do
            {:ok, class_definitions} ->
              {:ok, class_definitions}

            {:error, entries} ->
              increment_guardrail_skips()

              Logger.warning(
                "GPOS class definition skipped: format=2 entries=#{entries} exceeds limit=#{@max_gpos_class_def_entries}"
              )

              {:error, :guardrail_class_def}

            :error ->
              {:error, :malformed_class_def}
          end
        else
          _ -> {:error, :malformed_class_def}
        end

      _ ->
        {:error, :malformed_class_def}
    end
  end

  defp parse_open_type_class_def_table(_layout_table, _class_def_offset),
    do: {:error, :malformed_class_def}

  defp parse_open_type_class_ranges_with_limit(<<>>, acc, _entry_count, _limit), do: {:ok, acc}

  defp parse_open_type_class_ranges_with_limit(
         <<start_glyph_id::16-big, end_glyph_id::16-big, class_id::16-big, rest::binary>>,
         acc,
         entry_count,
         limit
       )
       when start_glyph_id <= end_glyph_id do
    span = end_glyph_id - start_glyph_id + 1
    next_entry_count = entry_count + span

    if next_entry_count > limit do
      {:error, next_entry_count}
    else
      next_acc =
        Enum.reduce(start_glyph_id..end_glyph_id, acc, fn glyph_id, inner_acc ->
          Map.put(inner_acc, glyph_id, class_id)
        end)

      parse_open_type_class_ranges_with_limit(rest, next_acc, next_entry_count, limit)
    end
  end

  defp parse_open_type_class_ranges_with_limit(_class_ranges_bin, _acc, _entry_count, _limit),
    do: :error

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
    glyph_to_codepoint = invert_cmap_by_code(cmap_by_code)

    Enum.reduce(gsub_ligatures, %{}, fn {source_glyph_ids, ligature_glyph_id}, acc ->
      with {:ok, source_codepoints} <-
             glyph_ids_to_codepoints(source_glyph_ids, glyph_to_codepoint),
           {:ok, ligature_codepoint} <- Map.fetch(glyph_to_codepoint, ligature_glyph_id),
           true <- valid_unicode_codepoint?(ligature_codepoint),
           source when is_binary(source) and byte_size(source) > 0 <-
             codepoints_to_string(source_codepoints) do
        Map.put_new(acc, source, <<ligature_codepoint::utf8>>)
      else
        _ -> acc
      end
    end)
  end

  defp map_gsub_ligatures_to_codepoint_strings(_gsub_ligatures, _cmap_by_code), do: %{}

  defp map_gpos_pair_adjustments_to_codepoints(gpos_pair_adjustments, cmap_by_code)
       when is_list(gpos_pair_adjustments) and is_map(cmap_by_code) do
    glyph_to_codepoint = invert_cmap_by_code(cmap_by_code)

    Enum.reduce(gpos_pair_adjustments, %{}, fn {{left_glyph_id, right_glyph_id}, adjustment},
                                               acc ->
      with {:ok, left_codepoint} <- Map.fetch(glyph_to_codepoint, left_glyph_id),
           {:ok, right_codepoint} <- Map.fetch(glyph_to_codepoint, right_glyph_id),
           true <- valid_unicode_codepoint?(left_codepoint),
           true <- valid_unicode_codepoint?(right_codepoint),
           true <- is_integer(adjustment) and adjustment != 0 do
        Map.put_new(acc, {left_codepoint, right_codepoint}, adjustment)
      else
        _ -> acc
      end
    end)
  end

  defp map_gpos_pair_adjustments_to_codepoints(_gpos_pair_adjustments, _cmap_by_code), do: %{}

  defp invert_cmap_by_code(cmap_by_code) when is_map(cmap_by_code) do
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

  defp glyph_ids_to_codepoints(glyph_ids, glyph_to_codepoint)
       when is_list(glyph_ids) and is_map(glyph_to_codepoint) do
    glyph_ids
    |> Enum.reduce_while([], fn glyph_id, acc ->
      case Map.fetch(glyph_to_codepoint, glyph_id) do
        {:ok, codepoint} ->
          if valid_unicode_codepoint?(codepoint) do
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

  defp valid_unicode_codepoint?(codepoint)
       when is_integer(codepoint) and codepoint >= 0 and codepoint <= 0x10FFFF,
       do: true

  defp valid_unicode_codepoint?(_codepoint), do: false
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
