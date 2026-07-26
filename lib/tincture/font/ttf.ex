defmodule Tincture.Font.TTF do
  @moduledoc false

  import Bitwise
  require Logger

  alias Tincture.Font.Binary
  alias Tincture.Font.CFF
  alias Tincture.Font.TTF.Cmap
  alias Tincture.Font.TTF.Glyf
  alias Tincture.Font.TTF.Layout
  alias Tincture.Font.TTF.Name

  @type basic_metrics :: %{
          units_per_em: pos_integer(),
          num_glyphs: pos_integer(),
          number_of_h_metrics: pos_integer(),
          advance_widths: [non_neg_integer()],
          max_advance_width: non_neg_integer(),
          cmap_by_code: %{optional(non_neg_integer()) => non_neg_integer()},
          cmap_var_selectors: [non_neg_integer()],
          cmap_non_default_uvs: %{
            optional({non_neg_integer(), non_neg_integer()}) => non_neg_integer()
          },
          gsub_scripts: [String.t()],
          gsub_features: [String.t()],
          gsub_ligatures: %{optional(String.t()) => String.t()},
          gsub_ligatures_all: %{optional(String.t()) => String.t()},
          gsub_substitutions_all: %{optional(String.t()) => String.t()},
          gpos_scripts: [String.t()],
          gpos_features: [String.t()],
          gpos_pair_kerns: %{optional({non_neg_integer(), non_neg_integer()}) => integer()},
          gpos_guardrail_skips: non_neg_integer(),
          italic: boolean(),
          bold: boolean(),
          italic_angle: float(),
          fixed_pitch: boolean(),
          head_bbox: {integer(), integer(), integer(), integer()} | nil,
          hhea_ascender: integer(),
          hhea_descender: integer(),
          hhea_line_gap: integer(),
          hhea_advance_width_max: non_neg_integer(),
          typo_ascender: integer() | nil,
          typo_descender: integer() | nil,
          typo_line_gap: integer() | nil,
          os2_avg_char_width: integer() | nil,
          x_height: integer() | nil,
          cap_height: integer() | nil,
          os2_weight_class: non_neg_integer() | nil,
          os2_width_class: non_neg_integer() | nil,
          os2_family_class: integer() | nil,
          os2_vendor_id: String.t() | nil,
          os2_version: non_neg_integer() | nil,
          os2_fs_selection: non_neg_integer() | nil,
          os2_fs_type: non_neg_integer() | nil,
          os2_subscript_x_size: integer() | nil,
          os2_subscript_y_size: integer() | nil,
          os2_subscript_x_offset: integer() | nil,
          os2_subscript_y_offset: integer() | nil,
          os2_superscript_x_size: integer() | nil,
          os2_superscript_y_size: integer() | nil,
          os2_superscript_x_offset: integer() | nil,
          os2_superscript_y_offset: integer() | nil,
          os2_strikeout_size: integer() | nil,
          os2_strikeout_position: integer() | nil,
          os2_unicode_ranges:
            {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
            | nil,
          os2_code_page_ranges: {non_neg_integer(), non_neg_integer()} | nil,
          os2_first_char_index: non_neg_integer() | nil,
          os2_last_char_index: non_neg_integer() | nil,
          os2_default_char: non_neg_integer() | nil,
          os2_break_char: non_neg_integer() | nil,
          os2_max_context: non_neg_integer() | nil,
          os2_lower_optical_point_size: non_neg_integer() | nil,
          os2_upper_optical_point_size: non_neg_integer() | nil,
          os2_win_ascent: non_neg_integer() | nil,
          os2_win_descent: non_neg_integer() | nil,
          os2_italic: boolean(),
          os2_oblique: boolean(),
          os2_bold: boolean(),
          os2_panose: binary() | nil,
          cff_stem_h: non_neg_integer() | nil,
          cff_stem_v: non_neg_integer() | nil,
          cff_force_bold: boolean() | nil,
          cff_weight_class: non_neg_integer() | nil,
          font_family: String.t() | nil,
          index_to_loc_format: 0 | 1,
          glyph_offsets: [non_neg_integer()],
          glyph_bboxes_by_id: %{
            optional(non_neg_integer()) => {integer(), integer(), integer(), integer()}
          },
          glyph_contour_counts_by_id: %{optional(non_neg_integer()) => non_neg_integer()},
          glyph_point_counts_by_id: %{optional(non_neg_integer()) => pos_integer()},
          glyph_simple_instruction_lengths_by_id: %{
            optional(non_neg_integer()) => non_neg_integer()
          },
          glyph_composite_instruction_lengths_by_id: %{
            optional(non_neg_integer()) => non_neg_integer()
          },
          glyph_outline_types_by_id: %{optional(non_neg_integer()) => :simple | :composite},
          glyph_component_counts_by_id: %{optional(non_neg_integer()) => non_neg_integer()},
          glyph_component_glyph_ids_by_id: %{
            optional(non_neg_integer()) => [non_neg_integer()]
          },
          cff_charstring_count: non_neg_integer(),
          cff_charstring_lengths_by_id: %{optional(non_neg_integer()) => non_neg_integer()},
          font_bbox: {integer(), integer(), integer(), integer()} | nil
        }

  @spec parse_basic_tables(binary()) :: {:ok, basic_metrics()} | :error
  def parse_basic_tables(data) when is_binary(data) do
    # The GPOS guardrail counter lives in the process dictionary because it is
    # incremented from seven places deep inside the GPOS pair/class parsers and
    # read once here; threading it back through those `with` chains would mean
    # reshaping the control flow of the code that produces kerning pairs.
    #
    # That is a tolerated smell, not a free one. The save/restore below makes it
    # re-entrancy-safe: without it, a nested parse_basic_tables/1 call would
    # zero an outer parse's accumulated count and silently under-report. No such
    # nesting exists today - the only callers are in Tincture.PDF, neither
    # reachable from inside the parse tree - so this guards a future caller
    # rather than a present bug.
    guardrail_scope = Layout.begin_guardrail_scope()

    try do
      parse_basic_tables_body(data)
    after
      Layout.end_guardrail_scope(guardrail_scope)
    end
  end

  defp parse_basic_tables_body(data) do
    with {:ok, table_records} <- parse_table_records(data),
         {:ok, head_table} <- fetch_table(data, table_records, "head"),
         {:ok, maxp_table} <- fetch_table(data, table_records, "maxp"),
         {:ok, hhea_table} <- fetch_table(data, table_records, "hhea"),
         {:ok, hmtx_table} <- fetch_table(data, table_records, "hmtx"),
         {:ok, units_per_em} <- parse_units_per_em(head_table),
         {:ok, num_glyphs} <- parse_num_glyphs(maxp_table),
         {:ok, number_of_h_metrics} <- parse_number_of_h_metrics(hhea_table),
         {:ok, head_italic} <- parse_head_italic(head_table),
         {:ok, head_bold} <- parse_head_bold(head_table),
         {:ok, head_bbox} <- parse_head_bbox(head_table),
         {:ok, post_style_metrics} <- parse_post_style_metrics(data, table_records),
         {:ok, name_metadata} <- Name.parse_name_metadata(data, table_records),
         {:ok, cff_descriptor_metrics} <- parse_cff_descriptor_metrics(data, table_records),
         {:ok, hhea_vertical_metrics} <- parse_hhea_vertical_metrics(hhea_table),
         {:ok, os2_vertical_metrics} <- parse_os2_vertical_metrics(data, table_records),
         {:ok, index_to_loc_format} <- parse_index_to_loc_format(head_table),
         {:ok, advance_widths} <-
           parse_advance_widths(hmtx_table, num_glyphs, number_of_h_metrics),
         {:ok, cmap_by_code} <- Cmap.parse_cmap_by_code(data, table_records),
         {:ok, cmap_variation_metadata} <- Cmap.parse_cmap_variation_metadata(data, table_records),
         {:ok, layout_metadata} <- Layout.parse_layout_metadata(data, table_records, cmap_by_code),
         {:ok, glyph_metrics} <-
           Glyf.parse_glyph_metrics(data, table_records, num_glyphs, index_to_loc_format) do
      metrics =
        %{
          units_per_em: units_per_em,
          num_glyphs: num_glyphs,
          number_of_h_metrics: number_of_h_metrics,
          advance_widths: advance_widths,
          max_advance_width: Enum.max(advance_widths),
          cmap_by_code: cmap_by_code,
          index_to_loc_format: index_to_loc_format,
          head_bbox: head_bbox,
          italic: head_italic,
          bold: head_bold
        }
        |> Map.merge(post_style_metrics)
        |> Map.merge(name_metadata)
        |> Map.merge(cff_descriptor_metrics)
        |> Map.merge(cmap_variation_metadata)
        |> Map.merge(layout_metadata)
        |> Map.merge(hhea_vertical_metrics)
        |> Map.merge(os2_vertical_metrics)
        |> Map.update!(:italic, fn italic ->
          italic or Map.get(os2_vertical_metrics, :os2_italic, false) or
            Map.get(os2_vertical_metrics, :os2_oblique, false) or
            abs(Map.get(post_style_metrics, :italic_angle, 0.0)) > 0.0001
        end)
        |> Map.update!(:bold, fn bold ->
          bold or Map.get(os2_vertical_metrics, :os2_bold, false)
        end)
        |> Map.merge(glyph_metrics)

      {:ok, metrics}
    else
      _ -> :error
    end
  end

  defp parse_table_records(
         <<_sfnt_version::32-big, num_tables::16-big, _search_range::16-big,
           _entry_selector::16-big, _range_shift::16-big, rest::binary>> = data
       ) do
    required_bytes = num_tables * 16

    if byte_size(rest) < required_bytes do
      :error
    else
      <<record_bytes::binary-size(required_bytes), _::binary>> = rest
      parse_records(record_bytes, %{}, data)
    end
  end

  defp parse_table_records(_), do: :error

  defp parse_records(<<>>, acc, _data), do: {:ok, acc}

  defp parse_records(
         <<tag::binary-size(4), _checksum::32-big, offset::32-big, length::32-big, rest::binary>>,
         acc,
         data
       ) do
    case Binary.slice(data, offset, length) do
      {:ok, _slice} ->
        parse_records(rest, Map.put(acc, tag, {offset, length}), data)

      :error ->
        :error
    end
  end

  defp parse_records(_, _, _), do: :error

  defp fetch_table(data, table_records, tag) do
    case Map.fetch(table_records, tag) do
      {:ok, {offset, length}} -> Binary.slice(data, offset, length)
      :error -> :error
    end
  end

  defp parse_units_per_em(<<_prefix::binary-size(18), units_per_em::16-big, _::binary>>)
       when units_per_em > 0,
       do: {:ok, units_per_em}

  defp parse_units_per_em(_), do: :error

  defp parse_hhea_vertical_metrics(
         <<_version::32-big, ascender::16-signed-big, descender::16-signed-big,
           line_gap::16-signed-big, advance_width_max::16-big, _::binary>>
       ) do
    {:ok,
     %{
       hhea_ascender: ascender,
       hhea_descender: descender,
       hhea_line_gap: line_gap,
       hhea_advance_width_max: advance_width_max
     }}
  end

  defp parse_hhea_vertical_metrics(_), do: :error

  defp parse_head_italic(<<_prefix::binary-size(44), mac_style::16-big, _::binary>>) do
    {:ok, rem(div(mac_style, 2), 2) == 1}
  end

  defp parse_head_italic(_), do: :error

  defp parse_head_bold(<<_prefix::binary-size(44), mac_style::16-big, _::binary>>) do
    {:ok, rem(mac_style, 2) == 1}
  end

  defp parse_head_bold(_), do: :error

  defp parse_head_bbox(
         <<_prefix::binary-size(36), x_min::16-signed-big, y_min::16-signed-big,
           x_max::16-signed-big, y_max::16-signed-big, _::binary>>
       ) do
    {:ok, {x_min, y_min, x_max, y_max}}
  end

  defp parse_head_bbox(_), do: :error

  defp parse_post_style_metrics(data, table_records) do
    case Map.fetch(table_records, "post") do
      {:ok, {offset, length}} ->
        with {:ok, post_table} <- Binary.slice(data, offset, length) do
          {:ok, extract_post_style_metrics(post_table)}
        else
          _ -> {:ok, parse_cff_style_metrics(data, table_records)}
        end

      :error ->
        {:ok, parse_cff_style_metrics(data, table_records)}
    end
  end

  defp extract_post_style_metrics(post_table) when is_binary(post_table) do
    italic_angle =
      case read_s32(post_table, 4) do
        {:ok, fixed_16_16} -> fixed_16_16 / 65_536
        :error -> 0.0
      end

    fixed_pitch =
      case Binary.u32(post_table, 12) do
        {:ok, value} -> value != 0
        :error -> false
      end

    %{italic_angle: italic_angle, fixed_pitch: fixed_pitch}
  end

  defp parse_cff_style_metrics(data, table_records) do
    with {:ok, top_dict} <- CFF.fetch_cff_top_dict(data, table_records) do
      italic_angle =
        case CFF.extract_cff_escaped_operator_operand(top_dict, 2) do
          {:ok, value} when is_integer(value) -> value * 1.0
          {:ok, value} when is_float(value) -> value
          _ -> 0.0
        end

      fixed_pitch =
        case CFF.extract_cff_escaped_operator_operand(top_dict, 1) do
          {:ok, value} when is_integer(value) -> value != 0
          {:ok, value} when is_float(value) -> abs(value) > 0.0001
          _ -> false
        end

      %{italic_angle: italic_angle, fixed_pitch: fixed_pitch}
    else
      _ -> %{italic_angle: 0.0, fixed_pitch: false}
    end
  end

  defp parse_cff_descriptor_metrics(data, table_records) do
    with {:ok, %{top_dict: top_dict, string_index: string_index, cff_table: cff_table}} <-
           CFF.fetch_cff_metadata(data, table_records) do
      cff_weight_class =
        case CFF.extract_cff_operator_operand(top_dict, 4) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            string_index
            |> CFF.cff_sid_to_string(sid)
            |> cff_weight_name_to_class()

          _ ->
            nil
        end

      {cff_stem_v, cff_stem_h, cff_force_bold} =
        case extract_cff_private_dict(top_dict, cff_table) do
          {:ok, private_dict} ->
            stem_v =
              private_dict
              |> cff_private_dict_stem_metric(11)
              |> case do
                nil ->
                  # Legacy fallback for older synthetic fixtures that encoded this as escaped 12 8.
                  case CFF.extract_cff_escaped_operator_operand(private_dict, 8) do
                    {:ok, value} -> normalize_positive_metric(value)
                    _ -> nil
                  end

                value ->
                  value
              end

            stem_h = cff_private_dict_stem_metric(private_dict, 10)
            force_bold = cff_private_dict_force_bold(private_dict)
            {stem_v, stem_h, force_bold}

          :error ->
            {nil, nil, nil}
        end

      {:ok,
       %{
         cff_weight_class: cff_weight_class,
         cff_stem_v: cff_stem_v,
         cff_stem_h: cff_stem_h,
         cff_force_bold: cff_force_bold
       }}
    else
      _ -> {:ok, %{cff_weight_class: nil, cff_stem_v: nil, cff_stem_h: nil, cff_force_bold: nil}}
    end
  end

  defp cff_private_dict_stem_metric(private_dict, operator)
       when is_binary(private_dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    case CFF.extract_cff_operator_operand(private_dict, operator) do
      {:ok, value} -> normalize_positive_metric(value)
      _ -> nil
    end
  end

  defp cff_private_dict_stem_metric(_private_dict, _operator), do: nil

  defp cff_private_dict_force_bold(private_dict) when is_binary(private_dict) do
    case CFF.extract_cff_operator_operand(private_dict, 14) do
      {:ok, value} when is_integer(value) -> value != 0
      {:ok, value} when is_float(value) -> abs(value) > 0.0001
      _ -> nil
    end
  end

  defp cff_private_dict_force_bold(_private_dict), do: nil

  defp normalize_positive_metric(value) when is_integer(value) and value > 0, do: value
  defp normalize_positive_metric(value) when is_float(value) and value > 0, do: round(value)
  defp normalize_positive_metric(_value), do: nil

  defp cff_weight_name_to_class(nil), do: nil

  defp cff_weight_name_to_class(name) when is_binary(name) do
    normalized = String.trim(name)

    case Integer.parse(normalized) do
      {value, ""} when value >= 1 and value <= 1000 ->
        value

      _ ->
        cff_weight_name_to_class_from_name(normalized)
    end
  end

  defp cff_weight_name_to_class_from_name(normalized_name) when is_binary(normalized_name) do
    canonical_name =
      normalized_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "")

    case canonical_name do
      "thin" -> 100
      "hairline" -> 100
      "extralight" -> 200
      "ultralight" -> 200
      "light" -> 300
      "book" -> 350
      "normal" -> 400
      "regular" -> 400
      "roman" -> 400
      "medium" -> 500
      "semibold" -> 600
      "demibold" -> 600
      "bold" -> 700
      "extrabold" -> 800
      "ultrabold" -> 800
      "black" -> 900
      "heavy" -> 900
      _ -> nil
    end
  end

  defp parse_index_to_loc_format(
         <<_prefix::binary-size(50), index_to_loc_format::16-signed-big, _::binary>>
       )
       when index_to_loc_format in [0, 1],
       do: {:ok, index_to_loc_format}

  defp parse_index_to_loc_format(_), do: :error

  defp parse_num_glyphs(<<_version::32-big, num_glyphs::16-big, _::binary>>) when num_glyphs > 0,
    do: {:ok, num_glyphs}

  defp parse_num_glyphs(_), do: :error

  defp parse_number_of_h_metrics(
         <<_prefix::binary-size(34), number_of_h_metrics::16-big, _::binary>>
       )
       when number_of_h_metrics > 0,
       do: {:ok, number_of_h_metrics}

  defp parse_number_of_h_metrics(_), do: :error

  defp parse_advance_widths(hmtx_table, num_glyphs, number_of_h_metrics)
       when is_integer(num_glyphs) and is_integer(number_of_h_metrics) and num_glyphs > 0 and
              number_of_h_metrics > 0 and number_of_h_metrics <= num_glyphs do
    required_metric_bytes = number_of_h_metrics * 4
    trailing_lsb_count = num_glyphs - number_of_h_metrics
    required_trailing_lsb_bytes = trailing_lsb_count * 2

    if byte_size(hmtx_table) < required_metric_bytes + required_trailing_lsb_bytes do
      :error
    else
      <<metric_bytes::binary-size(required_metric_bytes), trailing::binary>> = hmtx_table

      if byte_size(trailing) < required_trailing_lsb_bytes do
        :error
      else
        case parse_h_metrics(metric_bytes, []) do
          {:ok, [last_width | _] = reverse_widths} ->
            widths = Enum.reverse(reverse_widths)
            repeated_widths = List.duplicate(last_width, trailing_lsb_count)
            {:ok, widths ++ repeated_widths}

          :error ->
            :error
        end
      end
    end
  end

  defp parse_advance_widths(_, _, _), do: :error

  defp parse_h_metrics(<<>>, acc), do: {:ok, acc}

  defp parse_h_metrics(<<advance_width::16-big, _lsb::16-signed-big, rest::binary>>, acc) do
    parse_h_metrics(rest, [advance_width | acc])
  end

  defp parse_h_metrics(_, _), do: :error

  defp parse_os2_vertical_metrics(data, table_records) do
    case Map.fetch(table_records, "OS/2") do
      {:ok, {offset, length}} ->
        with {:ok, os2_table} <- Binary.slice(data, offset, length) do
          {:ok, extract_os2_vertical_metrics(os2_table)}
        else
          _ ->
            {:ok,
             %{
               typo_ascender: nil,
               typo_descender: nil,
               typo_line_gap: nil,
               os2_avg_char_width: nil,
               x_height: nil,
               cap_height: nil,
               os2_weight_class: nil,
               os2_width_class: nil,
               os2_family_class: nil,
               os2_vendor_id: nil,
               os2_version: nil,
               os2_fs_selection: nil,
               os2_fs_type: nil,
               os2_subscript_x_size: nil,
               os2_subscript_y_size: nil,
               os2_subscript_x_offset: nil,
               os2_subscript_y_offset: nil,
               os2_superscript_x_size: nil,
               os2_superscript_y_size: nil,
               os2_superscript_x_offset: nil,
               os2_superscript_y_offset: nil,
               os2_strikeout_size: nil,
               os2_strikeout_position: nil,
               os2_unicode_ranges: nil,
               os2_code_page_ranges: nil,
               os2_first_char_index: nil,
               os2_last_char_index: nil,
               os2_default_char: nil,
               os2_break_char: nil,
               os2_max_context: nil,
               os2_lower_optical_point_size: nil,
               os2_upper_optical_point_size: nil,
               os2_win_ascent: nil,
               os2_win_descent: nil,
               os2_italic: false,
               os2_oblique: false,
               os2_bold: false,
               os2_panose: nil
             }}
        end

      :error ->
        {:ok,
         %{
           typo_ascender: nil,
           typo_descender: nil,
           typo_line_gap: nil,
           os2_avg_char_width: nil,
           x_height: nil,
           cap_height: nil,
           os2_weight_class: nil,
           os2_width_class: nil,
           os2_family_class: nil,
           os2_vendor_id: nil,
           os2_version: nil,
           os2_fs_selection: nil,
           os2_fs_type: nil,
           os2_subscript_x_size: nil,
           os2_subscript_y_size: nil,
           os2_subscript_x_offset: nil,
           os2_subscript_y_offset: nil,
           os2_superscript_x_size: nil,
           os2_superscript_y_size: nil,
           os2_superscript_x_offset: nil,
           os2_superscript_y_offset: nil,
           os2_strikeout_size: nil,
           os2_strikeout_position: nil,
           os2_unicode_ranges: nil,
           os2_code_page_ranges: nil,
           os2_first_char_index: nil,
           os2_last_char_index: nil,
           os2_default_char: nil,
           os2_break_char: nil,
           os2_max_context: nil,
           os2_lower_optical_point_size: nil,
           os2_upper_optical_point_size: nil,
           os2_win_ascent: nil,
           os2_win_descent: nil,
           os2_italic: false,
           os2_oblique: false,
           os2_bold: false,
           os2_panose: nil
         }}
    end
  end

  defp extract_os2_vertical_metrics(os2_table) when is_binary(os2_table) do
    version =
      case Binary.u16(os2_table, 0) do
        {:ok, value} -> value
        :error -> 0
      end

    typo_ascender =
      case Binary.s16(os2_table, 68) do
        {:ok, value} -> value
        :error -> nil
      end

    typo_descender =
      case Binary.s16(os2_table, 70) do
        {:ok, value} -> value
        :error -> nil
      end

    typo_line_gap =
      case Binary.s16(os2_table, 72) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_avg_char_width =
      case Binary.s16(os2_table, 2) do
        {:ok, value} -> value
        :error -> nil
      end

    x_height =
      if version >= 2 do
        case Binary.s16(os2_table, 86) do
          {:ok, value} -> value
          :error -> nil
        end
      else
        nil
      end

    cap_height =
      if version >= 2 do
        case Binary.s16(os2_table, 88) do
          {:ok, value} -> value
          :error -> nil
        end
      else
        nil
      end

    os2_weight_class =
      case Binary.u16(os2_table, 4) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_width_class =
      case Binary.u16(os2_table, 6) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_family_class =
      case Binary.s16(os2_table, 30) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_vendor_id =
      case Binary.bytes(os2_table, 58, 4) do
        <<0, 0, 0, 0>> ->
          nil

        value when is_binary(value) and byte_size(value) == 4 ->
          value

        _ ->
          nil
      end

    os2_fs_type =
      case Binary.u16(os2_table, 8) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_x_size =
      case Binary.s16(os2_table, 10) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_y_size =
      case Binary.s16(os2_table, 12) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_x_offset =
      case Binary.s16(os2_table, 14) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_y_offset =
      case Binary.s16(os2_table, 16) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_x_size =
      case Binary.s16(os2_table, 18) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_y_size =
      case Binary.s16(os2_table, 20) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_x_offset =
      case Binary.s16(os2_table, 22) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_y_offset =
      case Binary.s16(os2_table, 24) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_strikeout_size =
      case Binary.s16(os2_table, 26) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_strikeout_position =
      case Binary.s16(os2_table, 28) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_unicode_ranges =
      case {Binary.u32(os2_table, 42), Binary.u32(os2_table, 46), Binary.u32(os2_table, 50),
            Binary.u32(os2_table, 54)} do
        {{:ok, range1}, {:ok, range2}, {:ok, range3}, {:ok, range4}} ->
          {range1, range2, range3, range4}

        _ ->
          nil
      end

    os2_code_page_ranges =
      case {Binary.u32(os2_table, 78), Binary.u32(os2_table, 82)} do
        {{:ok, range1}, {:ok, range2}} ->
          {range1, range2}

        _ ->
          nil
      end

    os2_first_char_index =
      case Binary.u16(os2_table, 64) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_last_char_index =
      case Binary.u16(os2_table, 66) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_default_char =
      case Binary.u16(os2_table, 90) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_break_char =
      case Binary.u16(os2_table, 92) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_max_context =
      case Binary.u16(os2_table, 94) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_lower_optical_point_size =
      if version >= 5 do
        case Binary.u16(os2_table, 96) do
          {:ok, value} when value > 0 -> value
          _ -> nil
        end
      else
        nil
      end

    os2_upper_optical_point_size =
      if version >= 5 do
        case Binary.u16(os2_table, 98) do
          {:ok, value} when value > 0 -> value
          _ -> nil
        end
      else
        nil
      end

    os2_win_ascent =
      case Binary.u16(os2_table, 74) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_win_descent =
      case Binary.u16(os2_table, 76) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_panose = Binary.bytes(os2_table, 32, 10)

    fs_selection =
      case Binary.u16(os2_table, 62) do
        {:ok, value} -> value
        :error -> 0
      end

    %{
      typo_ascender: typo_ascender,
      typo_descender: typo_descender,
      typo_line_gap: typo_line_gap,
      os2_avg_char_width: os2_avg_char_width,
      x_height: x_height,
      cap_height: cap_height,
      os2_weight_class: os2_weight_class,
      os2_width_class: os2_width_class,
      os2_family_class: os2_family_class,
      os2_vendor_id: os2_vendor_id,
      os2_version: version,
      os2_fs_selection: fs_selection,
      os2_fs_type: os2_fs_type,
      os2_subscript_x_size: os2_subscript_x_size,
      os2_subscript_y_size: os2_subscript_y_size,
      os2_subscript_x_offset: os2_subscript_x_offset,
      os2_subscript_y_offset: os2_subscript_y_offset,
      os2_superscript_x_size: os2_superscript_x_size,
      os2_superscript_y_size: os2_superscript_y_size,
      os2_superscript_x_offset: os2_superscript_x_offset,
      os2_superscript_y_offset: os2_superscript_y_offset,
      os2_strikeout_size: os2_strikeout_size,
      os2_strikeout_position: os2_strikeout_position,
      os2_unicode_ranges: os2_unicode_ranges,
      os2_code_page_ranges: os2_code_page_ranges,
      os2_first_char_index: os2_first_char_index,
      os2_last_char_index: os2_last_char_index,
      os2_default_char: os2_default_char,
      os2_break_char: os2_break_char,
      os2_max_context: os2_max_context,
      os2_lower_optical_point_size: os2_lower_optical_point_size,
      os2_upper_optical_point_size: os2_upper_optical_point_size,
      os2_win_ascent: os2_win_ascent,
      os2_win_descent: os2_win_descent,
      os2_italic: (fs_selection &&& 0x0001) != 0,
      os2_oblique: (fs_selection &&& 0x0200) != 0,
      os2_bold: (fs_selection &&& 0x0020) != 0,
      os2_panose: os2_panose
    }
  end

  defp extract_cff_private_dict(top_dict, cff_table)
       when is_binary(top_dict) and is_binary(cff_table) do
    with {:ok, [private_size, private_offset]} <- CFF.extract_cff_operator_operands(top_dict, 18),
         true <- is_integer(private_size) and private_size > 0,
         true <- is_integer(private_offset) and private_offset >= 0,
         true <- private_offset + private_size <= byte_size(cff_table) do
      {:ok, binary_part(cff_table, private_offset, private_size)}
    else
      _ -> :error
    end
  end

  defp extract_cff_private_dict(_top_dict, _cff_table), do: :error

  defp read_s32(data, offset) when is_integer(offset) and offset >= 0 do
    data_size = byte_size(data)

    if offset + 4 <= data_size do
      <<value::32-signed-big>> = binary_part(data, offset, 4)
      {:ok, value}
    else
      :error
    end
  end

  defp read_s32(_data, _offset), do: :error
end
