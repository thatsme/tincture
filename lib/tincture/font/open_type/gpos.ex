defmodule Tincture.Font.OpenType.GPOS do
  @moduledoc """
  Parser for the OpenType `GPOS` table: glyph positioning.

  Tincture reads one thing from `GPOS` - pair kerning, in both its formats.
  Format 1 lists explicit glyph pairs; format 2 declares glyph classes and a
  `class1 * class2` adjustment matrix.

  ## Guardrails

  The class matrix is the attack surface. A font declares `class1_count` and
  `class2_count` and the parser is expected to expand their product. A
  malformed or hostile font can declare a product large enough to exhaust
  memory, so expansion is capped and oversized subtables are skipped with a log
  line rather than expanded.

  Skips are counted in a process-local scope. The counter is incremented from
  seven places deep in the subtable parsers and read once at the end; threading
  it back through those `with` chains would reshape the control flow of the
  code that produces kerning pairs. Callers must bracket a parse with
  `begin_guardrail_scope/0` and `end_guardrail_scope/1`, which makes nesting
  safe.
  """

  import Bitwise
  require Logger

  alias Tincture.Font.Binary
  alias Tincture.Font.OpenType.Common

  # Caps on how much a single GPOS subtable may expand. A malformed or hostile
  # font can declare a class-pair matrix large enough to exhaust memory, so
  # oversized subtables are skipped and counted rather than expanded.
  @max_gpos_pair_set_records 10_000
  @max_gpos_class_pair_records 10_000
  @max_gpos_expanded_class_pairs 10_000
  @max_gpos_class_def_entries 10_000

  @gpos_guardrail_skip_count_key {__MODULE__, :gpos_guardrail_skip_count}

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
    Common.filter_open_type_lookup_entries_by_features(
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

  def parse_gpos_pair_kerns(data, table_records, cmap_by_code)
      when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    candidate_glyph_ids = cmap_candidate_glyph_ids(cmap_by_code)

    case Map.fetch(table_records, "GPOS") do
      {:ok, {offset, length}} ->
        with {:ok, layout_table} <- Binary.slice(data, offset, length),
             {:ok, _scripts, _features, lookup_list_offset} <-
               Common.parse_open_type_layout_table(layout_table) do
          lookup_entries =
            Common.parse_open_type_lookup_entries(layout_table, lookup_list_offset)
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
        Common.parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

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
        Common.parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

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
  The process dictionary key the guardrail counter is stored under.

  Exposed so tests can assert on the counter's lifecycle without hardcoding a
  module name. A hardcoded key silently stops matching when this module moves,
  which turns the isolation tests into assertions about a key nothing writes -
  they then pass for the wrong reason. That has now happened twice.
  """
  @spec guardrail_scope_key() :: term()
  def guardrail_scope_key, do: @gpos_guardrail_skip_count_key

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

  defp map_gpos_pair_adjustments_to_codepoints(gpos_pair_adjustments, cmap_by_code)
       when is_list(gpos_pair_adjustments) and is_map(cmap_by_code) do
    glyph_to_codepoint = Common.invert_cmap_by_code(cmap_by_code)

    Enum.reduce(gpos_pair_adjustments, %{}, fn {{left_glyph_id, right_glyph_id}, adjustment},
                                               acc ->
      with {:ok, left_codepoint} <- Map.fetch(glyph_to_codepoint, left_glyph_id),
           {:ok, right_codepoint} <- Map.fetch(glyph_to_codepoint, right_glyph_id),
           true <- Common.valid_unicode_codepoint?(left_codepoint),
           true <- Common.valid_unicode_codepoint?(right_codepoint),
           true <- is_integer(adjustment) and adjustment != 0 do
        Map.put_new(acc, {left_codepoint, right_codepoint}, adjustment)
      else
        _ -> acc
      end
    end)
  end

  defp map_gpos_pair_adjustments_to_codepoints(_gpos_pair_adjustments, _cmap_by_code), do: %{}
end
