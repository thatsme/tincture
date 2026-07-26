defmodule Tincture.Font.TTF do
  @moduledoc false

  import Bitwise
  require Logger
  @max_gpos_pair_set_records 10_000
  @max_gpos_class_pair_records 10_000
  @max_gpos_expanded_class_pairs 10_000
  @max_gpos_class_def_entries 10_000
  @gpos_guardrail_skip_count_key {__MODULE__, :gpos_guardrail_skip_count}

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
    reset_gpos_guardrail_skip_count()

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
         {:ok, name_metadata} <- parse_name_metadata(data, table_records),
         {:ok, cff_descriptor_metrics} <- parse_cff_descriptor_metrics(data, table_records),
         {:ok, hhea_vertical_metrics} <- parse_hhea_vertical_metrics(hhea_table),
         {:ok, os2_vertical_metrics} <- parse_os2_vertical_metrics(data, table_records),
         {:ok, index_to_loc_format} <- parse_index_to_loc_format(head_table),
         {:ok, advance_widths} <-
           parse_advance_widths(hmtx_table, num_glyphs, number_of_h_metrics),
         {:ok, cmap_by_code} <- parse_cmap_by_code(data, table_records),
         {:ok, cmap_variation_metadata} <- parse_cmap_variation_metadata(data, table_records),
         {:ok, layout_metadata} <- parse_layout_metadata(data, table_records, cmap_by_code),
         {:ok, glyph_metrics} <-
           parse_glyph_metrics(data, table_records, num_glyphs, index_to_loc_format) do
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
    case extract_slice(data, offset, length) do
      {:ok, _slice} ->
        parse_records(rest, Map.put(acc, tag, {offset, length}), data)

      :error ->
        :error
    end
  end

  defp parse_records(_, _, _), do: :error

  defp fetch_table(data, table_records, tag) do
    case Map.fetch(table_records, tag) do
      {:ok, {offset, length}} -> extract_slice(data, offset, length)
      :error -> :error
    end
  end

  defp extract_slice(data, offset, length) do
    data_size = byte_size(data)

    if offset <= data_size and length <= data_size - offset do
      {:ok, binary_part(data, offset, length)}
    else
      :error
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
        with {:ok, post_table} <- extract_slice(data, offset, length) do
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
      case read_u32(post_table, 12) do
        {:ok, value} -> value != 0
        :error -> false
      end

    %{italic_angle: italic_angle, fixed_pitch: fixed_pitch}
  end

  defp parse_cff_style_metrics(data, table_records) do
    with {:ok, top_dict} <- fetch_cff_top_dict(data, table_records) do
      italic_angle =
        case extract_cff_escaped_operator_operand(top_dict, 2) do
          {:ok, value} when is_integer(value) -> value * 1.0
          {:ok, value} when is_float(value) -> value
          _ -> 0.0
        end

      fixed_pitch =
        case extract_cff_escaped_operator_operand(top_dict, 1) do
          {:ok, value} when is_integer(value) -> value != 0
          {:ok, value} when is_float(value) -> abs(value) > 0.0001
          _ -> false
        end

      %{italic_angle: italic_angle, fixed_pitch: fixed_pitch}
    else
      _ -> %{italic_angle: 0.0, fixed_pitch: false}
    end
  end

  defp parse_name_metadata(data, table_records) do
    case Map.fetch(table_records, "name") do
      {:ok, {offset, length}} ->
        with {:ok, name_table} <- extract_slice(data, offset, length) do
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
           fetch_cff_metadata(data, table_records) do
      family_name =
        case extract_cff_operator_operand(top_dict, 3) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            cff_sid_to_string(string_index, sid)

          _ ->
            nil
        end

      full_name =
        case extract_cff_operator_operand(top_dict, 2) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            cff_sid_to_string(string_index, sid)

          _ ->
            nil
        end

      font_name =
        case extract_cff_escaped_operator_operand(top_dict, 38) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            cff_sid_to_string(string_index, sid)

          _ ->
            nil
        end

      family_name || full_name || font_name || normalize_name_value(cff_name)
    else
      _ -> nil
    end
  end

  defp cff_sid_to_string(string_index, sid) when is_integer(sid) and sid >= 0 do
    if sid < 391 do
      cff_standard_sid_to_string(sid)
    else
      cff_string_index_sid_to_string(string_index, sid)
    end
  end

  defp cff_sid_to_string(_string_index, _sid), do: nil

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

  defp parse_cff_descriptor_metrics(data, table_records) do
    with {:ok, %{top_dict: top_dict, string_index: string_index, cff_table: cff_table}} <-
           fetch_cff_metadata(data, table_records) do
      cff_weight_class =
        case extract_cff_operator_operand(top_dict, 4) do
          {:ok, sid} when is_integer(sid) and sid >= 0 ->
            string_index
            |> cff_sid_to_string(sid)
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
                  case extract_cff_escaped_operator_operand(private_dict, 8) do
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
    case extract_cff_operator_operand(private_dict, operator) do
      {:ok, value} -> normalize_positive_metric(value)
      _ -> nil
    end
  end

  defp cff_private_dict_stem_metric(_private_dict, _operator), do: nil

  defp cff_private_dict_force_bold(private_dict) when is_binary(private_dict) do
    case extract_cff_operator_operand(private_dict, 14) do
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

  defp name_record_priority({3, 1, 0x0409, 1, _length, _offset}), do: 0
  defp name_record_priority({3, _encoding, _language, 1, _length, _offset}), do: 1
  defp name_record_priority({0, _encoding, _language, 1, _length, _offset}), do: 2
  defp name_record_priority({1, _encoding, _language, 1, _length, _offset}), do: 3
  defp name_record_priority(_), do: 10

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
      value -> normalize_name_value(value)
    end
  end

  defp decode_name_string(raw, 0, _encoding_id) when is_binary(raw) do
    case safe_unicode_decode(raw, {:utf16, :big}) do
      nil -> nil
      value -> normalize_name_value(value)
    end
  end

  defp decode_name_string(raw, 1, _encoding_id) when is_binary(raw) do
    case safe_unicode_decode(raw, :latin1) do
      nil -> nil
      value -> normalize_name_value(value)
    end
  end

  defp decode_name_string(_raw, _platform_id, _encoding_id), do: nil

  defp safe_unicode_decode(raw, source_encoding) do
    try do
      :unicode.characters_to_binary(raw, source_encoding, :utf8)
    rescue
      _ -> nil
    end
  end

  defp normalize_name_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
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

  defp parse_layout_metadata(data, table_records, cmap_by_code) do
    {gsub_scripts, gsub_features} = parse_layout_table_metadata(data, table_records, "GSUB")
    {gpos_scripts, gpos_features} = parse_layout_table_metadata(data, table_records, "GPOS")
    gsub_ligatures = parse_gsub_ligatures(data, table_records, cmap_by_code)
    gsub_ligatures_all = parse_gsub_ligatures_all_scripts(data, table_records, cmap_by_code)

    gsub_substitutions_all =
      parse_gsub_substitutions_all_scripts(data, table_records, cmap_by_code)

    gpos_pair_kerns = parse_gpos_pair_kerns(data, table_records, cmap_by_code)
    gpos_guardrail_skips = gpos_guardrail_skip_count()

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
        with {:ok, layout_table} <- extract_slice(data, offset, length),
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

  defp parse_gsub_ligatures(data, table_records, cmap_by_code)
       when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    parse_gsub_substitutions(data, table_records, cmap_by_code, :preferred, ["liga"])
  end

  defp parse_gsub_ligatures_all_scripts(data, table_records, cmap_by_code)
       when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    parse_gsub_substitutions(data, table_records, cmap_by_code, :all, ["liga"])
  end

  defp parse_gsub_substitutions_all_scripts(data, table_records, cmap_by_code)
       when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    parse_gsub_substitutions(data, table_records, cmap_by_code, :all, ["liga", "rlig", "ccmp"])
  end

  defp parse_gsub_substitutions(data, table_records, cmap_by_code, script_scope, feature_tags)
       when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) and
              script_scope in [:preferred, :all] and is_list(feature_tags) do
    case Map.fetch(table_records, "GSUB") do
      {:ok, {offset, length}} ->
        with {:ok, layout_table} <- extract_slice(data, offset, length),
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
    case read_u16(layout_table, lookup_list_offset) do
      {:ok, lookup_count} ->
        offsets_offset = lookup_list_offset + 2
        required_bytes = lookup_count * 2

        case read_bytes(layout_table, offsets_offset, required_bytes) do
          nil ->
            []

          offsets_bin ->
            offsets_bin
            |> decode_u16_list()
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

    with {:ok, lookup_type} <- read_u16(layout_table, lookup_table_offset),
         {:ok, _lookup_flag} <- read_u16(layout_table, lookup_table_offset + 2),
         {:ok, subtable_count} <- read_u16(layout_table, lookup_table_offset + 4),
         subtable_offsets_bin when not is_nil(subtable_offsets_bin) <-
           read_bytes(layout_table, lookup_table_offset + 6, subtable_count * 2) do
      subtable_offsets =
        subtable_offsets_bin
        |> decode_u16_list()
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
    with {:ok, default_lang_sys_offset} <- read_u16(layout_table, script_table_offset),
         {:ok, lang_sys_count} <- read_u16(layout_table, script_table_offset + 2) do
      named_lang_sys_offsets =
        if lang_sys_count == 0 do
          []
        else
          case read_bytes(layout_table, script_table_offset + 4, lang_sys_count * 6) do
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
    with {:ok, req_feature_index} <- read_u16(layout_table, lang_sys_offset + 2),
         {:ok, feature_index_count} <- read_u16(layout_table, lang_sys_offset + 4) do
      feature_indices =
        if feature_index_count == 0 do
          []
        else
          case read_bytes(layout_table, lang_sys_offset + 6, feature_index_count * 2) do
            nil -> []
            feature_indices_bin -> decode_u16_list(feature_indices_bin)
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
    with {:ok, lookup_index_count} <- read_u16(layout_table, feature_table_offset + 2),
         lookup_indices_bin when not is_nil(lookup_indices_bin) <-
           read_bytes(layout_table, feature_table_offset + 4, lookup_index_count * 2) do
      decode_u16_list(lookup_indices_bin)
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
    with {:ok, 1} <- read_u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- read_u16(layout_table, subtable_offset + 2),
         {:ok, ligature_set_count} <- read_u16(layout_table, subtable_offset + 4),
         ligature_set_offsets_bin when not is_nil(ligature_set_offsets_bin) <-
           read_bytes(layout_table, subtable_offset + 6, ligature_set_count * 2) do
      coverage_glyph_ids =
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      ligature_set_offsets =
        ligature_set_offsets_bin
        |> decode_u16_list()
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
    case read_u16(layout_table, subtable_offset) do
      {:ok, 1} -> parse_gsub_single_substitution_subtable_format_1(layout_table, subtable_offset)
      {:ok, 2} -> parse_gsub_single_substitution_subtable_format_2(layout_table, subtable_offset)
      _ -> []
    end
  end

  defp parse_gsub_single_substitution_subtable(_layout_table, _subtable_offset), do: []

  defp parse_gsub_single_substitution_subtable_format_1(layout_table, subtable_offset)
       when is_binary(layout_table) and is_integer(subtable_offset) and subtable_offset >= 0 do
    with {:ok, 1} <- read_u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- read_u16(layout_table, subtable_offset + 2),
         {:ok, delta_glyph_id} <- read_s16(layout_table, subtable_offset + 4) do
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
    with {:ok, 2} <- read_u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- read_u16(layout_table, subtable_offset + 2),
         {:ok, glyph_count} <- read_u16(layout_table, subtable_offset + 4),
         substitute_glyph_ids_bin when not is_nil(substitute_glyph_ids_bin) <-
           read_bytes(layout_table, subtable_offset + 6, glyph_count * 2) do
      coverage_glyph_ids =
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      if length(coverage_glyph_ids) == glyph_count do
        substitute_glyph_ids = decode_u16_list(substitute_glyph_ids_bin)

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

  defp parse_gpos_pair_kerns(data, table_records, cmap_by_code)
       when is_binary(data) and is_map(table_records) and is_map(cmap_by_code) do
    candidate_glyph_ids = cmap_candidate_glyph_ids(cmap_by_code)

    case Map.fetch(table_records, "GPOS") do
      {:ok, {offset, length}} ->
        with {:ok, layout_table} <- extract_slice(data, offset, length),
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
    case read_u16(layout_table, subtable_offset) do
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
    with {:ok, 1} <- read_u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- read_u16(layout_table, subtable_offset + 2),
         {:ok, value_format_1} <- read_u16(layout_table, subtable_offset + 4),
         {:ok, value_format_2} <- read_u16(layout_table, subtable_offset + 6),
         {:ok, pair_set_count} <- read_u16(layout_table, subtable_offset + 8),
         pair_set_offsets_bin when not is_nil(pair_set_offsets_bin) <-
           read_bytes(layout_table, subtable_offset + 10, pair_set_count * 2),
         {:ok, value_record_1_size} <- gpos_value_record_size(value_format_1),
         {:ok, value_record_2_size} <- gpos_value_record_size(value_format_2) do
      coverage_glyph_ids =
        parse_open_type_coverage_table(layout_table, subtable_offset + coverage_offset)

      pair_set_offsets =
        pair_set_offsets_bin
        |> decode_u16_list()
        |> Enum.map(&(&1 + subtable_offset))

      coverage_glyph_count = length(coverage_glyph_ids)

      if coverage_glyph_count != pair_set_count do
        increment_gpos_guardrail_skip_count()

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
    with {:ok, 2} <- read_u16(layout_table, subtable_offset),
         {:ok, coverage_offset} <- read_u16(layout_table, subtable_offset + 2),
         {:ok, value_format_1} <- read_u16(layout_table, subtable_offset + 4),
         {:ok, value_format_2} <- read_u16(layout_table, subtable_offset + 6),
         {:ok, class_def_1_offset} <- read_u16(layout_table, subtable_offset + 8),
         {:ok, class_def_2_offset} <- read_u16(layout_table, subtable_offset + 10),
         {:ok, class_1_count} <- read_u16(layout_table, subtable_offset + 12),
         {:ok, class_2_count} <- read_u16(layout_table, subtable_offset + 14),
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

        increment_gpos_guardrail_skip_count()

        Logger.warning(
          "GPOS class-pair subtable skipped: malformed class definition tables class1_count=#{class_1_count} class2_count=#{class_2_count}"
        )

        []

      false ->
        {class_1_count, class_2_count} =
          gpos_pair_subtable_class_counts(layout_table, subtable_offset)

        increment_gpos_guardrail_skip_count()

        Logger.warning(
          "GPOS class-pair subtable skipped: class1_count=#{class_1_count} class2_count=#{class_2_count} must both be > 0"
        )

        []

      :error ->
        {class_1_count, class_2_count} =
          gpos_pair_subtable_class_counts(layout_table, subtable_offset)

        increment_gpos_guardrail_skip_count()

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
      read_u16(layout_table, subtable_offset + 12)
      |> case do
        {:ok, value} -> value
        _ -> 0
      end

    class_2_count =
      read_u16(layout_table, subtable_offset + 14)
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
      increment_gpos_guardrail_skip_count()

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

  defp reset_gpos_guardrail_skip_count do
    Process.put(@gpos_guardrail_skip_count_key, 0)
    :ok
  end

  defp increment_gpos_guardrail_skip_count do
    Process.put(@gpos_guardrail_skip_count_key, gpos_guardrail_skip_count() + 1)
    :ok
  end

  defp gpos_guardrail_skip_count do
    case Process.get(@gpos_guardrail_skip_count_key, 0) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
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
        increment_gpos_guardrail_skip_count()

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
    with {:ok, pair_value_count} <- read_u16(layout_table, pair_set_offset) do
      if pair_value_count > @max_gpos_pair_set_records do
        increment_gpos_guardrail_skip_count()

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
    with {:ok, right_glyph_id} <- read_u16(layout_table, offset),
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
      case read_u16(layout_table, offset + bytes_read) do
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
      case read_s16(layout_table, offset + bytes_read) do
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
    case read_u16(layout_table, coverage_offset) do
      {:ok, 1} ->
        with {:ok, glyph_count} <- read_u16(layout_table, coverage_offset + 2),
             glyph_ids_bin when not is_nil(glyph_ids_bin) <-
               read_bytes(layout_table, coverage_offset + 4, glyph_count * 2) do
          decode_u16_list(glyph_ids_bin)
        else
          _ -> []
        end

      {:ok, 2} ->
        with {:ok, range_count} <- read_u16(layout_table, coverage_offset + 2),
             range_records_bin when not is_nil(range_records_bin) <-
               read_bytes(layout_table, coverage_offset + 4, range_count * 6) do
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
    case read_u16(layout_table, class_def_offset) do
      {:ok, 1} ->
        with {:ok, start_glyph_id} <- read_u16(layout_table, class_def_offset + 2),
             {:ok, glyph_count} <- read_u16(layout_table, class_def_offset + 4),
             class_values_bin when not is_nil(class_values_bin) <-
               read_bytes(layout_table, class_def_offset + 6, glyph_count * 2) do
          if glyph_count > @max_gpos_class_def_entries do
            increment_gpos_guardrail_skip_count()

            Logger.warning(
              "GPOS class definition skipped: format=1 entries=#{glyph_count} exceeds limit=#{@max_gpos_class_def_entries}"
            )

            {:error, :guardrail_class_def}
          else
            class_values = decode_u16_list(class_values_bin)

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
        with {:ok, class_range_count} <- read_u16(layout_table, class_def_offset + 2),
             class_ranges_bin when not is_nil(class_ranges_bin) <-
               read_bytes(layout_table, class_def_offset + 4, class_range_count * 6) do
          case parse_open_type_class_ranges_with_limit(
                 class_ranges_bin,
                 %{},
                 0,
                 @max_gpos_class_def_entries
               ) do
            {:ok, class_definitions} ->
              {:ok, class_definitions}

            {:error, entries} ->
              increment_gpos_guardrail_skip_count()

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
    with {:ok, ligature_count} <- read_u16(layout_table, ligature_set_offset),
         ligature_offsets_bin when not is_nil(ligature_offsets_bin) <-
           read_bytes(layout_table, ligature_set_offset + 2, ligature_count * 2) do
      ligature_offsets_bin
      |> decode_u16_list()
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
    with {:ok, ligature_glyph_id} <- read_u16(layout_table, ligature_offset),
         {:ok, component_count} <- read_u16(layout_table, ligature_offset + 2),
         true <- component_count >= 2,
         components_bin when not is_nil(components_bin) <-
           read_bytes(layout_table, ligature_offset + 4, (component_count - 1) * 2) do
      source_glyph_ids = [coverage_glyph_id | decode_u16_list(components_bin)]
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
    codepoints
    |> Enum.map(fn codepoint -> <<codepoint::utf8>> end)
    |> Enum.join()
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

  defp parse_os2_vertical_metrics(data, table_records) do
    case Map.fetch(table_records, "OS/2") do
      {:ok, {offset, length}} ->
        with {:ok, os2_table} <- extract_slice(data, offset, length) do
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
      case read_u16(os2_table, 0) do
        {:ok, value} -> value
        :error -> 0
      end

    typo_ascender =
      case read_s16(os2_table, 68) do
        {:ok, value} -> value
        :error -> nil
      end

    typo_descender =
      case read_s16(os2_table, 70) do
        {:ok, value} -> value
        :error -> nil
      end

    typo_line_gap =
      case read_s16(os2_table, 72) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_avg_char_width =
      case read_s16(os2_table, 2) do
        {:ok, value} -> value
        :error -> nil
      end

    x_height =
      if version >= 2 do
        case read_s16(os2_table, 86) do
          {:ok, value} -> value
          :error -> nil
        end
      else
        nil
      end

    cap_height =
      if version >= 2 do
        case read_s16(os2_table, 88) do
          {:ok, value} -> value
          :error -> nil
        end
      else
        nil
      end

    os2_weight_class =
      case read_u16(os2_table, 4) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_width_class =
      case read_u16(os2_table, 6) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_family_class =
      case read_s16(os2_table, 30) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_vendor_id =
      case read_bytes(os2_table, 58, 4) do
        <<0, 0, 0, 0>> ->
          nil

        value when is_binary(value) and byte_size(value) == 4 ->
          value

        _ ->
          nil
      end

    os2_fs_type =
      case read_u16(os2_table, 8) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_x_size =
      case read_s16(os2_table, 10) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_y_size =
      case read_s16(os2_table, 12) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_x_offset =
      case read_s16(os2_table, 14) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_subscript_y_offset =
      case read_s16(os2_table, 16) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_x_size =
      case read_s16(os2_table, 18) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_y_size =
      case read_s16(os2_table, 20) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_x_offset =
      case read_s16(os2_table, 22) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_superscript_y_offset =
      case read_s16(os2_table, 24) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_strikeout_size =
      case read_s16(os2_table, 26) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_strikeout_position =
      case read_s16(os2_table, 28) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_unicode_ranges =
      case {read_u32(os2_table, 42), read_u32(os2_table, 46), read_u32(os2_table, 50),
            read_u32(os2_table, 54)} do
        {{:ok, range1}, {:ok, range2}, {:ok, range3}, {:ok, range4}} ->
          {range1, range2, range3, range4}

        _ ->
          nil
      end

    os2_code_page_ranges =
      case {read_u32(os2_table, 78), read_u32(os2_table, 82)} do
        {{:ok, range1}, {:ok, range2}} ->
          {range1, range2}

        _ ->
          nil
      end

    os2_first_char_index =
      case read_u16(os2_table, 64) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_last_char_index =
      case read_u16(os2_table, 66) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_default_char =
      case read_u16(os2_table, 90) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_break_char =
      case read_u16(os2_table, 92) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_max_context =
      case read_u16(os2_table, 94) do
        {:ok, value} -> value
        :error -> nil
      end

    os2_lower_optical_point_size =
      if version >= 5 do
        case read_u16(os2_table, 96) do
          {:ok, value} when value > 0 -> value
          _ -> nil
        end
      else
        nil
      end

    os2_upper_optical_point_size =
      if version >= 5 do
        case read_u16(os2_table, 98) do
          {:ok, value} when value > 0 -> value
          _ -> nil
        end
      else
        nil
      end

    os2_win_ascent =
      case read_u16(os2_table, 74) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_win_descent =
      case read_u16(os2_table, 76) do
        {:ok, value} when value > 0 -> value
        _ -> nil
      end

    os2_panose = read_bytes(os2_table, 32, 10)

    fs_selection =
      case read_u16(os2_table, 62) do
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

  defp parse_glyph_metrics(data, table_records, num_glyphs, index_to_loc_format) do
    loca_record = Map.get(table_records, "loca")
    glyf_record = Map.get(table_records, "glyf")
    cff_font_bbox = parse_cff_font_bbox(data, table_records)
    cff_outline_metrics = parse_cff_outline_metrics(data, table_records)

    case {loca_record, glyf_record} do
      {{loca_offset, loca_length}, {glyf_offset, glyf_length}} ->
        with {:ok, loca_table} <- extract_slice(data, loca_offset, loca_length),
             {:ok, glyf_table} <- extract_slice(data, glyf_offset, glyf_length),
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
           fetch_cff_metadata(data, table_records),
         {:ok, charstrings_offset} <- extract_cff_operator_operand(top_dict, 17),
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
    with {:ok, top_dict} <- fetch_cff_top_dict(data, table_records),
         {:ok, bbox} <- extract_cff_font_bbox(top_dict) do
      bbox
    else
      _ -> nil
    end
  end

  defp fetch_cff_top_dict(data, table_records) do
    with {:ok, %{top_dict: top_dict}} <- fetch_cff_metadata(data, table_records) do
      {:ok, top_dict}
    else
      _ -> :error
    end
  end

  defp fetch_cff_metadata(data, table_records) do
    case Map.fetch(table_records, "CFF ") do
      {:ok, {offset, length}} ->
        with {:ok, cff_table} <- extract_slice(data, offset, length),
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

      with {:ok, {name_index, after_name}} <- parse_cff_index(body),
           {:ok, {top_dict_index, after_top_dict}} <- parse_cff_index(after_name),
           {:ok, {string_index, _after_string}} <- parse_cff_index(after_top_dict),
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

  defp parse_cff_index(<<count::16-big, rest::binary>>) do
    if count == 0 do
      {:ok, {[], rest}}
    else
      case rest do
        <<off_size::8, offset_data::binary>> when off_size >= 1 and off_size <= 4 ->
          offset_count = count + 1
          offset_bytes = offset_count * off_size

          if byte_size(offset_data) < offset_bytes do
            :error
          else
            <<offset_bytes_bin::binary-size(offset_bytes), objects_and_rest::binary>> =
              offset_data

            with {:ok, offsets} <- decode_cff_index_offsets(offset_bytes_bin, off_size),
                 {:ok, objects, rest_after} <-
                   parse_cff_index_objects(offsets, count, objects_and_rest) do
              {:ok, {objects, rest_after}}
            else
              _ -> :error
            end
          end

        _ ->
          :error
      end
    end
  end

  defp parse_cff_index(_), do: :error

  defp decode_cff_index_offsets(bin, off_size) when is_binary(bin) and is_integer(off_size) do
    decode_cff_index_offsets(bin, off_size, [])
  end

  defp decode_cff_index_offsets(<<>>, _off_size, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_cff_index_offsets(bin, off_size, acc) do
    if byte_size(bin) < off_size do
      :error
    else
      <<entry::binary-size(off_size), rest::binary>> = bin
      value = :binary.decode_unsigned(entry)
      decode_cff_index_offsets(rest, off_size, [value | acc])
    end
  end

  defp parse_cff_index_objects(offsets, count, objects_and_rest)
       when is_list(offsets) and is_integer(count) and count > 0 and is_binary(objects_and_rest) do
    cond do
      length(offsets) != count + 1 ->
        :error

      not nondecreasing?(offsets) ->
        :error

      hd(offsets) < 1 ->
        :error

      List.last(offsets) < 1 ->
        :error

      List.last(offsets) - 1 > byte_size(objects_and_rest) ->
        :error

      true ->
        objects_data_size = List.last(offsets) - 1
        <<objects_data::binary-size(objects_data_size), rest_after::binary>> = objects_and_rest

        pairs = Enum.chunk_every(offsets, 2, 1, :discard)

        if length(pairs) != count do
          :error
        else
          Enum.reduce_while(pairs, {:ok, []}, fn [start_offset, end_offset], {:ok, acc} ->
            if end_offset < start_offset do
              {:halt, :error}
            else
              object_size = end_offset - start_offset
              object_offset = start_offset - 1
              object_data = binary_part(objects_data, object_offset, object_size)
              {:cont, {:ok, [object_data | acc]}}
            end
          end)
          |> case do
            {:ok, reverse_objects} -> {:ok, Enum.reverse(reverse_objects), rest_after}
            :error -> :error
          end
        end
    end
  end

  defp parse_cff_index_objects(_offsets, _count, _objects_and_rest), do: :error

  defp extract_cff_font_bbox(top_dict) when is_binary(top_dict) do
    scan_cff_dict_for_font_bbox(top_dict, [])
  end

  defp extract_cff_font_bbox(_top_dict), do: :error

  defp extract_cff_operator_operand(top_dict, operator)
       when is_binary(top_dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_dict_for_operator_operand(top_dict, operator, [])
  end

  defp extract_cff_operator_operand(_top_dict, _operator), do: :error

  defp extract_cff_operator_operands(top_dict, operator)
       when is_binary(top_dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_dict_for_operator_operands(top_dict, operator, [])
  end

  defp extract_cff_operator_operands(_top_dict, _operator), do: :error

  defp extract_cff_escaped_operator_operand(top_dict, escaped_operator)
       when is_binary(top_dict) and is_integer(escaped_operator) and escaped_operator >= 0 and
              escaped_operator <= 255 do
    scan_cff_dict_for_escaped_operator_operand(top_dict, escaped_operator, [])
  end

  defp extract_cff_escaped_operator_operand(_top_dict, _escaped_operator), do: :error

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
    case parse_cff_dict_number(dict_data) do
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
    case parse_cff_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_for_operator_operands(rest, operator, [number | operands])

      :error ->
        :error
    end
  end

  defp extract_cff_private_dict(top_dict, cff_table)
       when is_binary(top_dict) and is_binary(cff_table) do
    with {:ok, [private_size, private_offset]} <- extract_cff_operator_operands(top_dict, 18),
         true <- is_integer(private_size) and private_size > 0,
         true <- is_integer(private_offset) and private_offset >= 0,
         true <- private_offset + private_size <= byte_size(cff_table) do
      {:ok, binary_part(cff_table, private_offset, private_size)}
    else
      _ -> :error
    end
  end

  defp extract_cff_private_dict(_top_dict, _cff_table), do: :error

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
    case parse_cff_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_for_escaped_operator_operand(rest, escaped_operator, [number | operands])

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

  defp parse_cff_dict_number(<<30, rest::binary>>) do
    parse_cff_real_number(rest, [])
  end

  defp parse_cff_dict_number(<<28, value::16-signed-big, rest::binary>>),
    do: {:ok, value, rest}

  defp parse_cff_dict_number(<<29, value::32-signed-big, rest::binary>>),
    do: {:ok, value, rest}

  defp parse_cff_dict_number(<<255, value::32-signed-big, rest::binary>>),
    do: {:ok, value / 65_536, rest}

  defp parse_cff_dict_number(<<first::8, second::8, rest::binary>>)
       when first >= 247 and first <= 250 do
    value = (first - 247) * 256 + second + 108
    {:ok, value, rest}
  end

  defp parse_cff_dict_number(<<first::8, second::8, rest::binary>>)
       when first >= 251 and first <= 254 do
    value = -((first - 251) * 256 + second + 108)
    {:ok, value, rest}
  end

  defp parse_cff_dict_number(<<value::8, rest::binary>>) when value >= 32 and value <= 246,
    do: {:ok, value - 139, rest}

  defp parse_cff_dict_number(_), do: :error

  defp parse_cff_real_number(<<>>, _acc), do: :error

  defp parse_cff_real_number(<<byte::8, rest::binary>>, acc) do
    high = byte >>> 4
    low = byte &&& 0x0F

    case parse_cff_real_nibble(high, acc) do
      {:continue, acc_after_high} ->
        case parse_cff_real_nibble(low, acc_after_high) do
          {:continue, acc_after_low} ->
            parse_cff_real_number(rest, acc_after_low)

          {:done, acc_final} ->
            finalize_cff_real_number(acc_final, rest)

          :error ->
            :error
        end

      {:done, acc_final} ->
        finalize_cff_real_number(acc_final, rest)

      :error ->
        :error
    end
  end

  defp parse_cff_real_nibble(nibble, acc) when nibble >= 0 and nibble <= 9,
    do: {:continue, [Integer.to_string(nibble) | acc]}

  defp parse_cff_real_nibble(0xA, acc), do: {:continue, ["." | acc]}
  defp parse_cff_real_nibble(0xB, acc), do: {:continue, ["E" | acc]}
  defp parse_cff_real_nibble(0xC, acc), do: {:continue, ["E-" | acc]}
  defp parse_cff_real_nibble(0xE, acc), do: {:continue, ["-" | acc]}
  defp parse_cff_real_nibble(0xF, acc), do: {:done, acc}
  defp parse_cff_real_nibble(_nibble, _acc), do: :error

  defp finalize_cff_real_number(acc, rest) do
    acc
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> case do
      "" ->
        :error

      number_string ->
        case Float.parse(number_string) do
          {value, ""} -> {:ok, value, rest}
          _ -> :error
        end
    end
  end

  defp parse_loca_offsets(loca_table, num_glyphs, 0) do
    expected_entries = num_glyphs + 1
    required_bytes = expected_entries * 2

    if byte_size(loca_table) < required_bytes do
      :error
    else
      <<entries::binary-size(required_bytes), _::binary>> = loca_table

      entries
      |> decode_u16_list()
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
      |> decode_u32_list()
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

      end_points = decode_u16_list(end_points_bin)

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

  defp parse_cmap_by_code(data, table_records) do
    case Map.fetch(table_records, "cmap") do
      {:ok, {offset, length}} ->
        with {:ok, cmap_table} <- extract_slice(data, offset, length) do
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

  defp parse_cmap_variation_metadata(data, table_records) do
    default = %{cmap_var_selectors: [], cmap_non_default_uvs: %{}}

    case Map.fetch(table_records, "cmap") do
      {:ok, {offset, length}} ->
        with {:ok, cmap_table} <- extract_slice(data, offset, length),
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

  defp cmap_record_priority({3, 10, _offset}), do: 0
  defp cmap_record_priority({3, 1, _offset}), do: 1
  defp cmap_record_priority({3, 0, _offset}), do: 2
  defp cmap_record_priority({0, _encoding, _offset}), do: 3
  defp cmap_record_priority({1, 0, _offset}), do: 4
  defp cmap_record_priority({_platform, _encoding, _offset}), do: 10

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
    keys = decode_u16_list(subheader_keys)
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

      end_codes = decode_u16_list(end_codes_bin)
      start_codes = decode_u16_list(start_codes_bin)
      id_deltas = decode_s16_list(id_deltas_bin)
      id_range_offsets = decode_u16_list(id_range_offsets_bin)

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
      glyph_ids = decode_u16_list(glyph_ids_bin)

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
      glyph_ids = decode_u16_list(glyph_ids_bin)

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

      cond do
        subheader_key < 0 or rem(subheader_key, 8) != 0 ->
          {:halt, :error}

        true ->
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

    case read_u16(subtable, glyph_offset) do
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

      case read_u16(subtable, word_offset) do
        {:ok, 0} ->
          0

        {:ok, glyph_index} ->
          Integer.mod(glyph_index + id_delta, 65_536)

        :error ->
          0
      end
    end
  end

  defp read_u16(data, offset) when is_integer(offset) and offset >= 0 do
    data_size = byte_size(data)

    if offset + 2 <= data_size do
      <<value::16-big>> = binary_part(data, offset, 2)
      {:ok, value}
    else
      :error
    end
  end

  defp read_u16(_data, _offset), do: :error

  defp read_s16(data, offset) when is_integer(offset) and offset >= 0 do
    data_size = byte_size(data)

    if offset + 2 <= data_size do
      <<value::16-signed-big>> = binary_part(data, offset, 2)
      {:ok, value}
    else
      :error
    end
  end

  defp read_s16(_data, _offset), do: :error

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

  defp read_u32(data, offset) when is_integer(offset) and offset >= 0 do
    data_size = byte_size(data)

    if offset + 4 <= data_size do
      <<value::32-big>> = binary_part(data, offset, 4)
      {:ok, value}
    else
      :error
    end
  end

  defp read_u32(_data, _offset), do: :error

  defp read_bytes(data, offset, len)
       when is_integer(offset) and offset >= 0 and is_integer(len) and len > 0 do
    data_size = byte_size(data)

    if offset + len <= data_size do
      binary_part(data, offset, len)
    else
      nil
    end
  end

  defp read_bytes(_data, _offset, _len), do: nil

  defp decode_u16_list(bin), do: decode_u16_list(bin, [])
  defp decode_u32_list(bin), do: decode_u32_list(bin, [])
  defp decode_s16_list(bin), do: decode_s16_list(bin, [])

  defp decode_u16_list(<<>>, acc), do: Enum.reverse(acc)

  defp decode_u16_list(<<value::16-big, rest::binary>>, acc),
    do: decode_u16_list(rest, [value | acc])

  defp decode_u32_list(<<>>, acc), do: Enum.reverse(acc)

  defp decode_u32_list(<<value::32-big, rest::binary>>, acc),
    do: decode_u32_list(rest, [value | acc])

  defp decode_s16_list(<<>>, acc), do: Enum.reverse(acc)

  defp decode_s16_list(<<value::16-signed-big, rest::binary>>, acc),
    do: decode_s16_list(rest, [value | acc])

  defp lengths_match?(a, b, c, d) do
    length(a) == length(b) and length(b) == length(c) and length(c) == length(d)
  end

  defp nondecreasing?([]), do: true
  defp nondecreasing?([_]), do: true

  defp nondecreasing?([left, right | rest]) when left <= right do
    nondecreasing?([right | rest])
  end

  defp nondecreasing?(_), do: false
end
