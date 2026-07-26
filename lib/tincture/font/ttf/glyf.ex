defmodule Tincture.Font.TTF.Glyf do
  @moduledoc """
  Parsers for the TrueType glyph outline tables, `loca` and `glyf`.

  `loca` is an offset table locating each glyph's outline within `glyf`; a
  glyph whose start and end offsets are equal has no outline at all, which is
  how the space character and every other non-marking glyph is encoded.

  `glyf` entries are either simple outlines or composites that reference other
  glyphs by index, so following a composite means walking a reference graph
  that a malformed font can make cyclic or self-referential.

  Extracted from `Tincture.Font.TTF`.
  """

  import Bitwise

  alias Tincture.Font.Binary
  alias Tincture.Font.CFF

  def parse_glyph_metrics(data, table_records, num_glyphs, index_to_loc_format) do
    loca_record = Map.get(table_records, "loca")
    glyf_record = Map.get(table_records, "glyf")
    cff_font_bbox = parse_cff_font_bbox(data, table_records)
    cff_outline_metrics = parse_cff_outline_metrics(data, table_records)

    case {loca_record, glyf_record} do
      {{loca_offset, loca_length}, {glyf_offset, glyf_length}} ->
        with {:ok, loca_table} <- Binary.slice(data, loca_offset, loca_length),
             {:ok, glyf_table} <- Binary.slice(data, glyf_offset, glyf_length),
             {:ok, glyph_offsets} <-
               parse_loca_offsets(loca_table, num_glyphs, index_to_loc_format),
             {:ok, glyph_bboxes_by_id, glyph_contour_counts_by_id, glyph_outline_types_by_id,
              glyph_component_counts_by_id, glyph_component_glyph_ids_by_id,
              glyph_point_counts_by_id, glyph_simple_instruction_lengths_by_id,
              glyph_composite_instruction_lengths_by_id} <-
               parse_glyph_bboxes(glyf_table, glyph_offsets) do
          {:ok,
           %{
             glyph_offsets: glyph_offsets,
             glyph_bboxes_by_id: glyph_bboxes_by_id,
             glyph_contour_counts_by_id: glyph_contour_counts_by_id,
             glyph_point_counts_by_id: glyph_point_counts_by_id,
             glyph_simple_instruction_lengths_by_id: glyph_simple_instruction_lengths_by_id,
             glyph_composite_instruction_lengths_by_id: glyph_composite_instruction_lengths_by_id,
             glyph_outline_types_by_id: glyph_outline_types_by_id,
             glyph_component_counts_by_id: glyph_component_counts_by_id,
             glyph_component_glyph_ids_by_id: glyph_component_glyph_ids_by_id,
             font_bbox: union_font_bbox(glyph_bboxes_by_id)
           }
           |> Map.merge(cff_outline_metrics)}
        else
          _ -> :error
        end

      {nil, nil} ->
        {:ok,
         %{
           glyph_offsets: [],
           glyph_bboxes_by_id: %{},
           glyph_contour_counts_by_id: %{},
           glyph_point_counts_by_id: %{},
           glyph_simple_instruction_lengths_by_id: %{},
           glyph_composite_instruction_lengths_by_id: %{},
           glyph_outline_types_by_id: %{},
           glyph_component_counts_by_id: %{},
           glyph_component_glyph_ids_by_id: %{},
           font_bbox: cff_font_bbox
         }
         |> Map.merge(cff_outline_metrics)}

      _ ->
        {:ok,
         %{
           glyph_offsets: [],
           glyph_bboxes_by_id: %{},
           glyph_contour_counts_by_id: %{},
           glyph_point_counts_by_id: %{},
           glyph_simple_instruction_lengths_by_id: %{},
           glyph_composite_instruction_lengths_by_id: %{},
           glyph_outline_types_by_id: %{},
           glyph_component_counts_by_id: %{},
           glyph_component_glyph_ids_by_id: %{},
           font_bbox: cff_font_bbox
         }
         |> Map.merge(cff_outline_metrics)}
    end
  end

  defp parse_cff_outline_metrics(data, table_records) do
    with {:ok, %{top_dict: top_dict, cff_table: cff_table}} <-
           CFF.fetch_cff_metadata(data, table_records),
         {:ok, charstrings_offset} <- CFF.extract_cff_operator_operand(top_dict, 17),
         true <- is_integer(charstrings_offset) and charstrings_offset >= 0,
         true <- charstrings_offset < byte_size(cff_table),
         charstrings_tail <-
           binary_part(cff_table, charstrings_offset, byte_size(cff_table) - charstrings_offset),
         {:ok, {charstrings, _rest}} <- parse_cff_index(charstrings_tail) do
      lengths_by_id =
        charstrings
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {charstring, glyph_id}, acc ->
          if is_binary(charstring) do
            Map.put(acc, glyph_id, byte_size(charstring))
          else
            acc
          end
        end)

      %{
        cff_charstring_count: map_size(lengths_by_id),
        cff_charstring_lengths_by_id: lengths_by_id
      }
    else
      _ ->
        %{
          cff_charstring_count: 0,
          cff_charstring_lengths_by_id: %{}
        }
    end
  end

  defp parse_cff_font_bbox(data, table_records) do
    with {:ok, top_dict} <- CFF.fetch_cff_top_dict(data, table_records),
         {:ok, bbox} <- extract_cff_font_bbox(top_dict) do
      bbox
    else
      _ -> nil
    end
  end

  defp parse_cff_index(data) do
    case CFF.parse_index(data) do
      {:ok, %{objects: objects, rest: rest}} -> {:ok, {objects, rest}}
      :error -> :error
    end
  end

  defp extract_cff_font_bbox(top_dict) when is_binary(top_dict) do
    scan_cff_dict_for_font_bbox(top_dict, [])
  end

  defp extract_cff_font_bbox(_top_dict), do: :error
  defp scan_cff_dict_for_font_bbox(<<>>, _operands), do: :error

  defp scan_cff_dict_for_font_bbox(<<12, _escaped_op::8, rest::binary>>, _operands) do
    scan_cff_dict_for_font_bbox(rest, [])
  end

  defp scan_cff_dict_for_font_bbox(<<operator::8, rest::binary>>, operands)
       when operator <= 21 do
    if operator == 5 do
      case normalize_cff_font_bbox_operands(operands) do
        {:ok, bbox} -> {:ok, bbox}
        :error -> scan_cff_dict_for_font_bbox(rest, [])
      end
    else
      scan_cff_dict_for_font_bbox(rest, [])
    end
  end

  defp scan_cff_dict_for_font_bbox(dict_data, operands) do
    case parse_cff_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_for_font_bbox(rest, [number | operands])

      :error ->
        :error
    end
  end

  defp normalize_cff_font_bbox_operands(operands) when is_list(operands) do
    case Enum.reverse(operands) do
      [x_min, y_min, x_max, y_max] ->
        with {:ok, x_min} <- normalize_cff_font_bbox_value(x_min),
             {:ok, y_min} <- normalize_cff_font_bbox_value(y_min),
             {:ok, x_max} <- normalize_cff_font_bbox_value(x_max),
             {:ok, y_max} <- normalize_cff_font_bbox_value(y_max) do
          {:ok, {x_min, y_min, x_max, y_max}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp normalize_cff_font_bbox_value(value) when is_integer(value), do: {:ok, value}
  defp normalize_cff_font_bbox_value(value) when is_float(value), do: {:ok, round(value)}
  defp normalize_cff_font_bbox_value(_value), do: :error

  # Delegates to Tincture.Font.CFF. Note this changes operator 255 (16.16
  # fixed) from a bare `value / 65_536` to the normalised form, so a whole
  # value now parses as an integer rather than a float - matching what the
  # subsetting path already did for the same bytes.
  defp parse_cff_dict_number(data), do: CFF.parse_dict_number(data)

  defp parse_loca_offsets(loca_table, num_glyphs, 0) do
    expected_entries = num_glyphs + 1
    required_bytes = expected_entries * 2

    if byte_size(loca_table) < required_bytes do
      :error
    else
      <<entries::binary-size(required_bytes), _::binary>> = loca_table

      entries
      |> Binary.u16_list()
      |> Enum.map(&(&1 * 2))
      |> validate_glyph_offsets()
    end
  end

  defp parse_loca_offsets(loca_table, num_glyphs, 1) do
    expected_entries = num_glyphs + 1
    required_bytes = expected_entries * 4

    if byte_size(loca_table) < required_bytes do
      :error
    else
      <<entries::binary-size(required_bytes), _::binary>> = loca_table

      entries
      |> Binary.u32_list()
      |> validate_glyph_offsets()
    end
  end

  defp parse_loca_offsets(_, _, _), do: :error

  defp validate_glyph_offsets(offsets) when is_list(offsets) do
    if nondecreasing?(offsets) do
      {:ok, offsets}
    else
      :error
    end
  end

  defp parse_glyph_bboxes(glyf_table, glyph_offsets) when is_binary(glyf_table) do
    if length(glyph_offsets) < 2 or List.last(glyph_offsets) > byte_size(glyf_table) do
      :error
    else
      glyph_offsets
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.reduce_while(
        {:ok,
         %{
           bboxes: %{},
           contour_counts: %{},
           point_counts: %{},
           instruction_lengths: %{},
           composite_instruction_lengths: %{},
           outline_types: %{},
           component_counts: %{},
           component_glyph_ids: %{}
         }},
        fn {[start_offset, end_offset], glyph_id}, {:ok, acc} ->
          cond do
            end_offset < start_offset ->
              {:halt, :error}

            end_offset == start_offset ->
              {:cont, {:ok, acc}}

            end_offset - start_offset < 10 ->
              {:halt, :error}

            end_offset > byte_size(glyf_table) ->
              {:halt, :error}

            true ->
              glyph_data = binary_part(glyf_table, start_offset, end_offset - start_offset)

              case parse_glyph_header(glyph_data) do
                {:ok, number_of_contours, bbox, component_data} ->
                  contour_counts =
                    if number_of_contours > 0 do
                      Map.put(acc.contour_counts, glyph_id, number_of_contours)
                    else
                      acc.contour_counts
                    end

                  point_counts =
                    case parse_glyph_simple_point_count(number_of_contours, component_data) do
                      {:ok, point_count} ->
                        Map.put(acc.point_counts, glyph_id, point_count)

                      _ ->
                        acc.point_counts
                    end

                  instruction_lengths =
                    case parse_glyph_simple_instruction_length(number_of_contours, component_data) do
                      {:ok, instruction_length} ->
                        Map.put(acc.instruction_lengths, glyph_id, instruction_length)

                      _ ->
                        acc.instruction_lengths
                    end

                  composite_instruction_lengths =
                    case parse_glyph_composite_instruction_length(
                           number_of_contours,
                           component_data
                         ) do
                      {:ok, instruction_length} ->
                        Map.put(acc.composite_instruction_lengths, glyph_id, instruction_length)

                      _ ->
                        acc.composite_instruction_lengths
                    end

                  outline_types =
                    case glyph_outline_type(number_of_contours) do
                      nil -> acc.outline_types
                      outline_type -> Map.put(acc.outline_types, glyph_id, outline_type)
                    end

                  component_counts =
                    case parse_glyph_component_count(number_of_contours, component_data) do
                      {:ok, component_count} ->
                        Map.put(acc.component_counts, glyph_id, component_count)

                      _ ->
                        acc.component_counts
                    end

                  component_glyph_ids =
                    case parse_glyph_component_glyph_ids(number_of_contours, component_data) do
                      {:ok, glyph_ids} when glyph_ids != [] ->
                        Map.put(acc.component_glyph_ids, glyph_id, glyph_ids)

                      _ ->
                        acc.component_glyph_ids
                    end

                  {:cont,
                   {:ok,
                    %{
                      bboxes: Map.put(acc.bboxes, glyph_id, bbox),
                      contour_counts: contour_counts,
                      point_counts: point_counts,
                      instruction_lengths: instruction_lengths,
                      composite_instruction_lengths: composite_instruction_lengths,
                      outline_types: outline_types,
                      component_counts: component_counts,
                      component_glyph_ids: component_glyph_ids
                    }}}

                :error ->
                  {:halt, :error}
              end
          end
        end
      )
      |> case do
        {:ok,
         %{
           bboxes: bboxes,
           contour_counts: contour_counts,
           point_counts: point_counts,
           instruction_lengths: instruction_lengths,
           composite_instruction_lengths: composite_instruction_lengths,
           outline_types: outline_types,
           component_counts: component_counts,
           component_glyph_ids: component_glyph_ids
         }} ->
          {:ok, bboxes, contour_counts, outline_types, component_counts, component_glyph_ids,
           point_counts, instruction_lengths, composite_instruction_lengths}

        :error ->
          :error
      end
    end
  end

  defp parse_glyph_bboxes(_, _), do: :error

  defp parse_glyph_header(
         <<number_of_contours::16-signed-big, x_min::16-signed-big, y_min::16-signed-big,
           x_max::16-signed-big, y_max::16-signed-big, component_data::binary>>
       ) do
    {:ok, number_of_contours, {x_min, y_min, x_max, y_max}, component_data}
  end

  defp parse_glyph_header(_), do: :error

  defp glyph_outline_type(number_of_contours)
       when is_integer(number_of_contours) and number_of_contours > 0,
       do: :simple

  defp glyph_outline_type(number_of_contours)
       when is_integer(number_of_contours) and number_of_contours < 0,
       do: :composite

  defp glyph_outline_type(_number_of_contours), do: nil

  defp parse_glyph_simple_point_count(number_of_contours, component_data)
       when is_integer(number_of_contours) and number_of_contours > 0 and
              is_binary(component_data) do
    case parse_glyph_simple_metadata(number_of_contours, component_data) do
      {:ok, point_count, _instruction_length} -> {:ok, point_count}
      :error -> :error
    end
  end

  defp parse_glyph_simple_point_count(_number_of_contours, _component_data), do: :error

  defp parse_glyph_simple_instruction_length(number_of_contours, component_data)
       when is_integer(number_of_contours) and number_of_contours > 0 and
              is_binary(component_data) do
    case parse_glyph_simple_metadata(number_of_contours, component_data) do
      {:ok, _point_count, instruction_length} -> {:ok, instruction_length}
      :error -> :error
    end
  end

  defp parse_glyph_simple_instruction_length(_number_of_contours, _component_data), do: :error

  defp parse_glyph_simple_metadata(number_of_contours, component_data)
       when is_integer(number_of_contours) and number_of_contours > 0 and
              is_binary(component_data) do
    endpoint_bytes = number_of_contours * 2

    if byte_size(component_data) < endpoint_bytes + 2 do
      :error
    else
      <<end_points_bin::binary-size(endpoint_bytes), instruction_length::16-big,
        remaining::binary>> = component_data

      end_points = Binary.u16_list(end_points_bin)

      if nondecreasing?(end_points) and byte_size(remaining) >= instruction_length do
        case List.last(end_points) do
          last_endpoint when is_integer(last_endpoint) and last_endpoint >= 0 ->
            {:ok, last_endpoint + 1, instruction_length}

          _ ->
            :error
        end
      else
        :error
      end
    end
  end

  defp parse_glyph_simple_metadata(_number_of_contours, _component_data), do: :error

  defp parse_glyph_composite_instruction_length(number_of_contours, component_data)
       when is_integer(number_of_contours) and number_of_contours < 0 and
              is_binary(component_data) do
    case parse_composite_component_glyph_ids(component_data, []) do
      {:ok, _glyph_ids, instruction_length}
      when is_integer(instruction_length) and instruction_length >= 0 ->
        {:ok, instruction_length}

      _ ->
        :error
    end
  end

  defp parse_glyph_composite_instruction_length(_number_of_contours, _component_data), do: :error

  defp parse_glyph_component_count(number_of_contours, component_data)
       when is_integer(number_of_contours) and number_of_contours < 0 and
              is_binary(component_data) do
    case parse_composite_component_glyph_ids(component_data, []) do
      {:ok, glyph_ids, _instruction_length} -> {:ok, length(glyph_ids)}
      :error -> :error
    end
  end

  defp parse_glyph_component_count(_number_of_contours, _component_data), do: :error

  defp parse_glyph_component_glyph_ids(number_of_contours, component_data)
       when is_integer(number_of_contours) and number_of_contours < 0 and
              is_binary(component_data) do
    case parse_composite_component_glyph_ids(component_data, []) do
      {:ok, glyph_ids, _instruction_length} -> {:ok, glyph_ids}
      :error -> :error
    end
  end

  defp parse_glyph_component_glyph_ids(_number_of_contours, _component_data), do: :error

  defp parse_composite_component_glyph_ids(component_data, reverse_glyph_ids)
       when is_list(reverse_glyph_ids) do
    parse_composite_component_glyph_ids(component_data, reverse_glyph_ids, nil)
  end

  defp parse_composite_component_glyph_ids(
         <<flags::16-big, glyph_id::16-big, rest::binary>>,
         reverse_glyph_ids,
         composite_instruction_length
       )
       when is_list(reverse_glyph_ids) do
    with {:ok, rest_after_args} <- consume_composite_component_args(rest, flags),
         {:ok, rest_after_transform} <-
           consume_composite_component_transform(rest_after_args, flags),
         {:ok, rest_after_instructions, instruction_length} <-
           consume_composite_component_instructions(rest_after_transform, flags) do
      next_reverse_glyph_ids = [glyph_id | reverse_glyph_ids]
      next_instruction_length = instruction_length || composite_instruction_length

      if (flags &&& 0x0020) != 0 do
        parse_composite_component_glyph_ids(
          rest_after_instructions,
          next_reverse_glyph_ids,
          next_instruction_length
        )
      else
        {:ok, Enum.reverse(next_reverse_glyph_ids), next_instruction_length}
      end
    else
      _ ->
        :error
    end
  end

  defp parse_composite_component_glyph_ids(
         _component_data,
         _reverse_glyph_ids,
         _composite_instruction_length
       ),
       do: :error

  defp consume_composite_component_args(rest, flags) when is_binary(rest) and is_integer(flags) do
    arg_bytes = if (flags &&& 0x0001) != 0, do: 4, else: 2

    if byte_size(rest) >= arg_bytes do
      <<_args::binary-size(arg_bytes), remaining::binary>> = rest
      {:ok, remaining}
    else
      :error
    end
  end

  defp consume_composite_component_transform(rest, flags)
       when is_binary(rest) and is_integer(flags) do
    transform_bytes =
      cond do
        (flags &&& 0x0080) != 0 -> 8
        (flags &&& 0x0040) != 0 -> 4
        (flags &&& 0x0008) != 0 -> 2
        true -> 0
      end

    if byte_size(rest) >= transform_bytes do
      <<_transform::binary-size(transform_bytes), remaining::binary>> = rest
      {:ok, remaining}
    else
      :error
    end
  end

  defp consume_composite_component_instructions(rest, flags)
       when is_binary(rest) and is_integer(flags) do
    if (flags &&& 0x0100) != 0 do
      case rest do
        <<instruction_length::16-big, _instructions::binary-size(instruction_length),
          remaining::binary>> ->
          {:ok, remaining, instruction_length}

        _ ->
          :error
      end
    else
      {:ok, rest, nil}
    end
  end

  defp union_font_bbox(glyph_bboxes_by_id) when map_size(glyph_bboxes_by_id) == 0, do: nil

  defp union_font_bbox(glyph_bboxes_by_id) do
    glyph_bboxes_by_id
    |> Map.values()
    |> Enum.reduce(nil, fn {x_min, y_min, x_max, y_max}, acc ->
      case acc do
        nil ->
          {x_min, y_min, x_max, y_max}

        {acc_x_min, acc_y_min, acc_x_max, acc_y_max} ->
          {
            min(acc_x_min, x_min),
            min(acc_y_min, y_min),
            max(acc_x_max, x_max),
            max(acc_y_max, y_max)
          }
      end
    end)
  end

  defp nondecreasing?([]), do: true
  defp nondecreasing?([_]), do: true

  defp nondecreasing?([left, right | rest]) when left <= right do
    nondecreasing?([right | rest])
  end

  defp nondecreasing?(_), do: false
end
