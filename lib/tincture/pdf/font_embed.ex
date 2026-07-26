defmodule Tincture.PDF.FontEmbed do
  @moduledoc """
  Builds the PDF objects for embedded TrueType and OpenType fonts.

  This is everything between "the document uses these fonts" and "here are the
  PDF objects that carry them": choosing simple vs composite (Type0/CID) fonts,
  subsetting the sfnt tables, rebuilding `glyf`/`loca` and `CFF `, computing
  descriptors and widths, and emitting the `ToUnicode` CMap.

  It was extracted from `Tincture.PDF.Serialize`, where 134 of that module's
  174 private functions were reachable from this one entry point. The rest of
  the serializer — pages, content streams, images, the object table — never
  needed any of it, and could not be read without scrolling past it.

  The public surface is deliberately narrow: `build_embedded_font_objects/3` is
  the whole contract, and returns everything the page and content-stream code
  needs to reference the fonts it produced.
  """

  import Bitwise
  require Logger

  alias Tincture.Font.CFF
  alias Tincture.PDF
  alias Tincture.PDF.Object
  alias Tincture.Telemetry
  alias Tincture.Unicode

  @sfnt_checksum_magic 0xB1B0AFBA

  def build_embedded_font_objects(pdf, page_numbers, start_object_id) do
    used_char_codes_by_font = used_char_codes_by_font(pdf, page_numbers)
    used_cids_by_font = used_cids_by_font(pdf, page_numbers)
    scalar_codepoints_by_font = scalar_codepoints_by_font(pdf, page_numbers)
    variation_sequences_by_font = variation_sequences_by_font(pdf, page_numbers)
    to_unicode_mappings_by_font = to_unicode_mappings_by_font(pdf, page_numbers)
    unicode_text_by_font = unicode_text_by_font(pdf, page_numbers)

    embedded_font_names =
      page_numbers
      |> Enum.flat_map(fn page_number ->
        pdf
        |> PDF.page_operations(page_number)
        |> font_names_from_operations()
      end)
      |> Enum.uniq()
      |> Enum.filter(fn font_name -> Map.has_key?(pdf.embedded_fonts, font_name) end)

    {refs, objects, text_modes, next_object_id} =
      Enum.reduce(
        embedded_font_names,
        {%{}, [], %{}, start_object_id},
        fn font_name, {acc_refs, acc_objects, acc_modes, next_id} ->
          embedded_font = Map.fetch!(pdf.embedded_fonts, font_name)
          used_char_codes = Map.get(used_char_codes_by_font, font_name, [])
          used_cids = Map.get(used_cids_by_font, font_name, [])
          scalar_codepoints = Map.get(scalar_codepoints_by_font, font_name, [])
          variation_sequences = Map.get(variation_sequences_by_font, font_name, [])
          to_unicode_mappings = Map.get(to_unicode_mappings_by_font, font_name, [])
          unicode_text? = Map.get(unicode_text_by_font, font_name, false)
          use_type0? = use_type0_embedded_font?(embedded_font, unicode_text?)

          font_metadata = %{
            font_name: font_name,
            format: Map.get(embedded_font, :format),
            subset: Map.get(embedded_font, :subset)
          }

          {font_object_ref, per_font_objects, next_object_id, text_mode} =
            Telemetry.span([:tincture, :font, :embed], font_metadata, fn ->
              result =
                build_embedded_font_family_objects(
                  embedded_font,
                  next_id,
                  used_char_codes,
                  used_cids,
                  scalar_codepoints,
                  variation_sequences,
                  to_unicode_mappings,
                  use_type0?
                )

              {_ref, objects, _next, _mode} = result

              measurements = %{
                byte_size: IO.iodata_length(objects),
                source_size: byte_size(Map.get(embedded_font, :data, ""))
              }

              {result, measurements}
            end)

          {
            Map.put(acc_refs, font_name, font_object_ref),
            acc_objects ++ per_font_objects,
            Map.put(acc_modes, font_name, text_mode),
            next_object_id
          }
        end
      )

    {refs, objects, text_modes, next_object_id}
  end

  def font_names_from_operations(operations) do
    operations
    |> Enum.flat_map(fn
      {:text_at, _x, _y, _text, {font_name, _size}} -> [font_name]
      {:text_at_rotated, _x, _y, _angle_degrees, _text, {font_name, _size}} -> [font_name]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp used_char_codes_by_font(pdf, page_numbers) do
    page_numbers
    |> Enum.flat_map(fn page_number -> PDF.page_operations(pdf, page_number) end)
    |> Enum.reduce(%{}, fn
      {:text_at, _x, _y, text, {font_name, _size}}, acc ->
        merge_used_char_codes(acc, font_name, text)

      {:text_at_rotated, _x, _y, _angle_degrees, text, {font_name, _size}}, acc ->
        merge_used_char_codes(acc, font_name, text)

      _op, acc ->
        acc
    end)
    |> Enum.into(%{}, fn
      {font_name, :full_range} -> {font_name, []}
      {font_name, set} -> {font_name, set |> Enum.sort()}
    end)
  end

  defp merge_used_char_codes(acc, font_name, text) do
    codepoints = String.to_charlist(text)

    if Enum.any?(codepoints, &(&1 > 127)) do
      Map.put(acc, font_name, :full_range)
    else
      codes = Enum.filter(codepoints, &(&1 >= 32 and &1 <= 255))

      Map.update(acc, font_name, MapSet.new(codes), fn
        :full_range ->
          :full_range

        existing ->
          Enum.reduce(codes, existing, &MapSet.put(&2, &1))
      end)
    end
  end

  defp unicode_text_by_font(pdf, page_numbers) do
    page_numbers
    |> Enum.flat_map(fn page_number -> PDF.page_operations(pdf, page_number) end)
    |> Enum.reduce(%{}, fn
      {:text_at, _x, _y, text, {font_name, _size}}, acc ->
        merge_unicode_text_usage(acc, font_name, text)

      {:text_at_rotated, _x, _y, _angle_degrees, text, {font_name, _size}}, acc ->
        merge_unicode_text_usage(acc, font_name, text)

      _op, acc ->
        acc
    end)
  end

  defp merge_unicode_text_usage(acc, font_name, text) do
    if Object.unicode_text?(text) do
      Map.put(acc, font_name, true)
    else
      Map.put_new(acc, font_name, false)
    end
  end

  defp used_cids_by_font(pdf, page_numbers) do
    page_numbers
    |> Enum.flat_map(fn page_number -> PDF.page_operations(pdf, page_number) end)
    |> Enum.reduce(%{}, fn
      {:text_at, _x, _y, text, {font_name, _size}}, acc ->
        merge_used_cids(acc, font_name, text)

      {:text_at_rotated, _x, _y, _angle_degrees, text, {font_name, _size}}, acc ->
        merge_used_cids(acc, font_name, text)

      _op, acc ->
        acc
    end)
    |> Enum.into(%{}, fn {font_name, set} -> {font_name, set |> Enum.sort()} end)
  end

  defp merge_used_cids(acc, font_name, text) do
    cids = utf16_code_units(text)

    Map.update(acc, font_name, MapSet.new(cids), fn existing ->
      Enum.reduce(cids, existing, &MapSet.put(&2, &1))
    end)
  end

  defp scalar_codepoints_by_font(pdf, page_numbers) do
    page_numbers
    |> Enum.flat_map(fn page_number -> PDF.page_operations(pdf, page_number) end)
    |> Enum.reduce(%{}, fn
      {:text_at, _x, _y, text, {font_name, _size}}, acc ->
        merge_scalar_codepoints(acc, font_name, text)

      {:text_at_rotated, _x, _y, _angle_degrees, text, {font_name, _size}}, acc ->
        merge_scalar_codepoints(acc, font_name, text)

      _op, acc ->
        acc
    end)
    |> Enum.into(%{}, fn {font_name, set} -> {font_name, set |> Enum.sort()} end)
  end

  defp variation_sequences_by_font(pdf, page_numbers) do
    page_numbers
    |> Enum.flat_map(fn page_number -> PDF.page_operations(pdf, page_number) end)
    |> Enum.reduce(%{}, fn
      {:text_at, _x, _y, text, {font_name, _size}}, acc ->
        merge_variation_sequences(acc, font_name, text)

      {:text_at_rotated, _x, _y, _angle_degrees, text, {font_name, _size}}, acc ->
        merge_variation_sequences(acc, font_name, text)

      _op, acc ->
        acc
    end)
    |> Enum.into(%{}, fn {font_name, set} -> {font_name, set |> Enum.sort()} end)
  end

  defp merge_variation_sequences(acc, font_name, text) do
    sequences =
      text
      |> String.to_charlist()
      |> Enum.filter(&(&1 >= 0 and &1 <= 0x10FFFF))
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(MapSet.new(), fn
        [base, selector], set ->
          if Unicode.variation_selector_codepoint?(selector) do
            MapSet.put(set, {base, selector})
          else
            set
          end

        _other, set ->
          set
      end)

    Map.update(acc, font_name, sequences, fn existing ->
      MapSet.union(existing, sequences)
    end)
  end

  defp merge_scalar_codepoints(acc, font_name, text) do
    codepoints =
      text
      |> String.to_charlist()
      |> Enum.filter(&(&1 >= 0 and &1 <= 0x10FFFF))

    Map.update(acc, font_name, MapSet.new(codepoints), fn existing ->
      Enum.reduce(codepoints, existing, &MapSet.put(&2, &1))
    end)
  end

  defp to_unicode_mappings_by_font(pdf, page_numbers) do
    page_numbers
    |> Enum.flat_map(fn page_number -> PDF.page_operations(pdf, page_number) end)
    |> Enum.reduce(%{}, fn
      {:text_at, _x, _y, text, {font_name, _size}}, acc ->
        merge_to_unicode_mappings(acc, font_name, text)

      {:text_at_rotated, _x, _y, _angle_degrees, text, {font_name, _size}}, acc ->
        merge_to_unicode_mappings(acc, font_name, text)

      _op, acc ->
        acc
    end)
    |> Enum.into(%{}, fn {font_name, set} -> {font_name, set |> Enum.sort()} end)
  end

  defp merge_to_unicode_mappings(acc, font_name, text) do
    mappings = scalar_to_utf16_hex_mappings(text)

    Map.update(acc, font_name, MapSet.new(mappings), fn existing ->
      Enum.reduce(mappings, existing, &MapSet.put(&2, &1))
    end)
  end

  defp embedded_font_file_object(embedded_font, used_char_codes, scalar_codepoints) do
    data = embedded_font_file_data(embedded_font, used_char_codes, scalar_codepoints)
    length = byte_size(data)

    case Map.fetch!(embedded_font, :format) do
      :ttf ->
        ["<< /Length #{length} /Length1 #{length} >>\nstream\n", data, "\nendstream"]

      :otf ->
        [
          "<< /Length #{length} /Length1 #{length} /Subtype /OpenType >>\nstream\n",
          data,
          "\nendstream"
        ]
    end
  end

  defp embedded_font_file_data(embedded_font, used_char_codes, scalar_codepoints) do
    case Map.fetch!(embedded_font, :format) do
      :ttf ->
        maybe_subset_ttf_font_data(embedded_font, used_char_codes, scalar_codepoints)

      :otf ->
        maybe_subset_otf_font_data(embedded_font, used_char_codes, scalar_codepoints)
    end
  end

  defp maybe_subset_ttf_font_data(embedded_font, used_char_codes, scalar_codepoints) do
    data = Map.fetch!(embedded_font, :data)
    subset_mode = Map.get(embedded_font, :subset, :none)
    ttf_metrics = Map.get(embedded_font, :ttf_metrics, %{})

    case subset_mode do
      :none ->
        data

      mode when mode in [:ascii_basic, :used_text] ->
        case ttf_metrics do
          %{
            cmap_by_code: cmap_by_code,
            glyph_offsets: glyph_offsets,
            num_glyphs: num_glyphs,
            index_to_loc_format: index_to_loc_format
          } = metrics
          when is_map(cmap_by_code) and map_size(cmap_by_code) > 0 and is_list(glyph_offsets) and
                 glyph_offsets != [] and is_integer(num_glyphs) and num_glyphs > 0 and
                 index_to_loc_format in [0, 1] ->
            codepoints =
              subset_mode_codepoints(mode, used_char_codes, scalar_codepoints)

            used_glyph_ids = subset_glyph_ids(codepoints, cmap_by_code, num_glyphs)

            case subset_ttf_font_data(data, metrics, used_glyph_ids) do
              {:ok, subset_data} when byte_size(subset_data) < byte_size(data) ->
                subset_data

              {:error, :invalid_composite_component_reference} ->
                Logger.warning(
                  "TTF subset fallback to full font for #{Map.get(embedded_font, :name, "unknown")}: invalid composite component reference"
                )

                data

              {:error, :malformed_composite_component_records} ->
                Logger.warning(
                  "TTF subset fallback to full font for #{Map.get(embedded_font, :name, "unknown")}: malformed composite component records"
                )

                data

              _ ->
                data
            end

          _ ->
            data
        end

      _ ->
        data
    end
  end

  defp subset_mode_codepoints(:ascii_basic, _used_char_codes, _scalar_codepoints) do
    Enum.to_list(32..126)
  end

  defp subset_mode_codepoints(:used_text, used_char_codes, scalar_codepoints) do
    (List.wrap(used_char_codes) ++ List.wrap(scalar_codepoints))
    |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 <= 0x10FFFF))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp subset_mode_codepoints(_mode, _used_char_codes, _scalar_codepoints), do: []

  defp maybe_subset_otf_font_data(embedded_font, used_char_codes, scalar_codepoints) do
    data = Map.fetch!(embedded_font, :data)
    subset_mode = Map.get(embedded_font, :subset, :none)
    ttf_metrics = Map.get(embedded_font, :ttf_metrics, %{})

    case subset_mode do
      :none ->
        data

      mode when mode in [:ascii_basic, :used_text] ->
        case ttf_metrics do
          %{cmap_by_code: cmap_by_code, num_glyphs: num_glyphs}
          when is_map(cmap_by_code) and map_size(cmap_by_code) > 0 and is_integer(num_glyphs) and
                 num_glyphs > 0 ->
            codepoints =
              subset_mode_codepoints(mode, used_char_codes, scalar_codepoints)

            used_glyph_ids = subset_glyph_ids(codepoints, cmap_by_code, num_glyphs)

            case subset_otf_font_data(data, used_glyph_ids) do
              {:ok, subset_data} when byte_size(subset_data) < byte_size(data) ->
                subset_data

              _ ->
                data
            end

          _ ->
            data
        end

      _ ->
        data
    end
  end

  defp subset_glyph_ids(codepoints, cmap_by_code, num_glyphs)
       when is_list(codepoints) and is_map(cmap_by_code) and is_integer(num_glyphs) and
              num_glyphs > 0 do
    codepoints
    |> Enum.reduce(MapSet.new([0]), fn codepoint, acc ->
      case Map.get(cmap_by_code, codepoint) do
        glyph_id when is_integer(glyph_id) and glyph_id >= 0 and glyph_id < num_glyphs ->
          MapSet.put(acc, glyph_id)

        _ ->
          acc
      end
    end)
  end

  defp subset_glyph_ids(_codepoints, _cmap_by_code, _num_glyphs), do: MapSet.new([0])

  defp subset_ttf_font_data(data, ttf_metrics, used_glyph_ids)
       when is_binary(data) and is_map(ttf_metrics) and is_map(used_glyph_ids) do
    with {:ok, sfnt_version, table_order, tables} <- parse_sfnt_tables(data),
         {:ok, _loca_table} <- Map.fetch(tables, "loca"),
         {:ok, glyf_table} <- Map.fetch(tables, "glyf"),
         {:ok, subset_glyf_table, subset_loca_table} <-
           subset_ttf_glyf_and_loca(glyf_table, ttf_metrics, used_glyph_ids) do
      updated_tables =
        tables
        |> Map.put("glyf", subset_glyf_table)
        |> Map.put("loca", subset_loca_table)

      {:ok, build_sfnt(sfnt_version, table_order, updated_tables)}
    else
      {:error, :invalid_composite_component_reference} ->
        {:error, :invalid_composite_component_reference}

      {:error, :malformed_composite_component_records} ->
        {:error, :malformed_composite_component_records}

      _ ->
        :error
    end
  end

  defp subset_ttf_font_data(_data, _ttf_metrics, _used_glyph_ids), do: :error

  defp subset_otf_font_data(data, used_glyph_ids)
       when is_binary(data) and is_map(used_glyph_ids) do
    with {:ok, sfnt_version, table_order, tables} <- parse_sfnt_tables(data),
         {:ok, cff_table} <- Map.fetch(tables, "CFF "),
         {:ok, subset_cff_table} <- subset_otf_cff_table(cff_table, used_glyph_ids) do
      updated_tables = Map.put(tables, "CFF ", subset_cff_table)
      {:ok, build_sfnt(sfnt_version, table_order, updated_tables)}
    else
      _ ->
        :error
    end
  end

  defp subset_otf_font_data(_data, _used_glyph_ids), do: :error

  defp subset_otf_cff_table(cff_table, used_glyph_ids)
       when is_binary(cff_table) and is_map(used_glyph_ids) do
    with {:ok,
          %{
            charstrings_offset: charstrings_offset,
            charstrings_size: charstrings_size,
            charstrings: charstrings,
            top_dict: top_dict,
            top_dict_offset: top_dict_offset,
            top_dict_length: top_dict_length
          }} <- parse_cff_charstrings(cff_table),
         subset_charstrings <- subset_cff_charstrings(charstrings, used_glyph_ids),
         subset_charstrings_index <- encode_cff_index(subset_charstrings) do
      charstrings_end = charstrings_offset + charstrings_size

      cond do
        byte_size(subset_charstrings_index) > charstrings_size ->
          :error

        cff_charstrings_tail_droppable?(top_dict, charstrings_end, byte_size(cff_table)) ->
          prefix_size = charstrings_offset
          <<prefix::binary-size(prefix_size), _charstrings_and_tail::binary>> = cff_table
          {:ok, IO.iodata_to_binary([prefix, subset_charstrings_index])}

        true ->
          shrink = charstrings_size - byte_size(subset_charstrings_index)

          if shrink > 0 do
            with {:ok, patched_cff_table} <-
                   patch_cff_top_dict_offsets_for_tail_shift(
                     cff_table,
                     top_dict_offset,
                     top_dict_length,
                     charstrings_end,
                     byte_size(cff_table),
                     -shrink
                   ) do
              prefix_size = charstrings_offset
              suffix_offset = charstrings_end
              suffix_size = byte_size(patched_cff_table) - suffix_offset

              <<prefix::binary-size(prefix_size), _old_charstrings::binary-size(charstrings_size),
                suffix::binary-size(suffix_size)>> = patched_cff_table

              {:ok, IO.iodata_to_binary([prefix, subset_charstrings_index, suffix])}
            else
              _ ->
                :error
            end
          else
            :error
          end
      end
    else
      _ ->
        :error
    end
  end

  defp subset_otf_cff_table(_cff_table, _used_glyph_ids), do: :error

  defp patch_cff_top_dict_offsets_for_tail_shift(
         cff_table,
         top_dict_offset,
         top_dict_length,
         tail_start,
         cff_size,
         delta
       )
       when is_binary(cff_table) and is_integer(top_dict_offset) and is_integer(top_dict_length) and
              is_integer(tail_start) and is_integer(cff_size) and is_integer(delta) do
    if top_dict_offset >= 0 and top_dict_length > 0 and
         top_dict_offset + top_dict_length <= cff_size and
         cff_size <= byte_size(cff_table) and delta < 0 do
      top_dict = binary_part(cff_table, top_dict_offset, top_dict_length)

      with {:ok, top_dict_patches} <-
             collect_cff_top_dict_offset_patches(top_dict, tail_start, cff_size, delta),
           {:ok, fdarray_patches} <-
             collect_cff_fdarray_font_dict_offset_patches(
               cff_table,
               top_dict,
               tail_start,
               cff_size,
               delta
             ) do
        absolute_top_dict_patches =
          Enum.map(top_dict_patches, fn {start, length, replacement} ->
            {top_dict_offset + start, length, replacement}
          end)

        all_patches = absolute_top_dict_patches ++ fdarray_patches

        if all_patches != [] do
          apply_binary_patches_same_length(cff_table, all_patches)
        else
          :error
        end
      else
        _ ->
          :error
      end
    else
      :error
    end
  end

  defp patch_cff_top_dict_offsets_for_tail_shift(
         _cff_table,
         _top_dict_offset,
         _top_dict_length,
         _tail_start,
         _cff_size,
         _delta
       ),
       do: :error

  defp collect_cff_fdarray_font_dict_offset_patches(
         cff_table,
         top_dict,
         tail_start,
         cff_size,
         delta
       )
       when is_binary(cff_table) and is_binary(top_dict) and is_integer(tail_start) and
              is_integer(cff_size) and is_integer(delta) do
    case cff_dict_escaped_operator_operand(top_dict, 36) do
      {:ok, fdarray_offset}
      when is_integer(fdarray_offset) and fdarray_offset >= 0 and
             fdarray_offset < cff_size ->
        fdarray_data = binary_part(cff_table, fdarray_offset, cff_size - fdarray_offset)

        with {:ok, fdarray_index} <- parse_cff_index_with_offsets(fdarray_data),
             font_dicts <- Map.fetch!(fdarray_index, :objects),
             offsets <- Map.fetch!(fdarray_index, :offsets),
             objects_data_offset <- Map.fetch!(fdarray_index, :objects_data_offset),
             true <- length(offsets) == length(font_dicts) + 1 do
          font_dict_patches =
            offsets
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.zip(font_dicts)
            |> Enum.reduce_while({:ok, []}, fn {[start_offset, _end_offset], font_dict},
                                               {:ok, patch_acc} ->
              font_dict_offset = fdarray_offset + objects_data_offset + start_offset - 1

              case collect_cff_top_dict_offset_patches(font_dict, tail_start, cff_size, delta) do
                {:ok, patches} ->
                  absolute_patches =
                    Enum.map(patches, fn {start, length, replacement} ->
                      {font_dict_offset + start, length, replacement}
                    end)

                  {:cont, {:ok, absolute_patches ++ patch_acc}}

                _ ->
                  {:halt, :error}
              end
            end)

          case font_dict_patches do
            {:ok, patches} -> {:ok, patches}
            :error -> :error
          end
        else
          _ ->
            :error
        end

      {:ok, _fdarray_offset} ->
        :error

      :error ->
        {:ok, []}
    end
  end

  defp collect_cff_fdarray_font_dict_offset_patches(
         _cff_table,
         _top_dict,
         _tail_start,
         _cff_size,
         _delta
       ),
       do: :error

  defp collect_cff_top_dict_offset_patches(top_dict, tail_start, cff_size, delta)
       when is_binary(top_dict) and is_integer(tail_start) and is_integer(cff_size) and
              is_integer(delta) do
    scan_cff_top_dict_for_offset_patches(top_dict, 0, [], tail_start, cff_size, delta, [])
  end

  defp collect_cff_top_dict_offset_patches(_top_dict, _tail_start, _cff_size, _delta), do: :error

  defp scan_cff_top_dict_for_offset_patches(
         <<>>,
         _cursor,
         _operands,
         _tail_start,
         _cff_size,
         _delta,
         patches
       ),
       do: {:ok, Enum.reverse(patches)}

  defp scan_cff_top_dict_for_offset_patches(
         <<12, escaped_op::8, rest::binary>>,
         cursor,
         operands,
         tail_start,
         cff_size,
         delta,
         patches
       ) do
    with {:ok, next_patches} <-
           add_cff_operator_offset_patches(
             {:escaped, escaped_op},
             operands,
             tail_start,
             cff_size,
             delta,
             patches
           ) do
      scan_cff_top_dict_for_offset_patches(
        rest,
        cursor + 2,
        [],
        tail_start,
        cff_size,
        delta,
        next_patches
      )
    else
      _ ->
        :error
    end
  end

  defp scan_cff_top_dict_for_offset_patches(
         <<op::8, rest::binary>>,
         cursor,
         operands,
         tail_start,
         cff_size,
         delta,
         patches
       )
       when op <= 21 do
    with {:ok, next_patches} <-
           add_cff_operator_offset_patches(
             {:op, op},
             operands,
             tail_start,
             cff_size,
             delta,
             patches
           ) do
      scan_cff_top_dict_for_offset_patches(
        rest,
        cursor + 1,
        [],
        tail_start,
        cff_size,
        delta,
        next_patches
      )
    else
      _ ->
        :error
    end
  end

  defp scan_cff_top_dict_for_offset_patches(
         dict_data,
         cursor,
         operands,
         tail_start,
         cff_size,
         delta,
         patches
       ) do
    case parse_cff_dict_number_meta(dict_data, cursor) do
      {:ok, operand, rest} ->
        scan_cff_top_dict_for_offset_patches(
          rest,
          cursor + operand.length,
          [operand | operands],
          tail_start,
          cff_size,
          delta,
          patches
        )

      :error ->
        :error
    end
  end

  defp add_cff_operator_offset_patches(
         operator_id,
         reverse_operands,
         tail_start,
         cff_size,
         delta,
         patches
       ) do
    operands = Enum.reverse(reverse_operands)

    target_operands =
      case operator_id do
        {:op, 15} -> [List.last(operands)]
        {:op, 16} -> [List.last(operands)]
        {:op, 17} -> [List.last(operands)]
        {:op, 18} -> [Enum.at(operands, 1)]
        {:escaped, 36} -> [List.last(operands)]
        {:escaped, 37} -> [List.last(operands)]
        _ -> []
      end
      |> Enum.reject(&is_nil/1)

    Enum.reduce_while(target_operands, {:ok, patches}, fn operand, {:ok, patches_acc} ->
      case cff_offset_patch_for_operand(operand, tail_start, cff_size, delta) do
        {:ok, nil} ->
          {:cont, {:ok, patches_acc}}

        {:ok, patch} ->
          {:cont, {:ok, [patch | patches_acc]}}

        :error ->
          {:halt, :error}
      end
    end)
  end

  defp cff_offset_patch_for_operand(
         %{value: value, start: start, length: length, kind: kind},
         tail_start,
         cff_size,
         delta
       )
       when is_integer(value) and is_integer(start) and is_integer(length) and
              is_integer(tail_start) and
              is_integer(cff_size) and is_integer(delta) do
    if value >= tail_start and value < cff_size do
      new_value = value + delta

      with true <- new_value >= 0,
           {:ok, replacement} <- encode_cff_number_same_kind(kind, new_value),
           true <- byte_size(replacement) == length do
        {:ok, {start, length, replacement}}
      else
        _ ->
          :error
      end
    else
      {:ok, nil}
    end
  end

  defp cff_offset_patch_for_operand(_operand, _tail_start, _cff_size, _delta), do: :error

  defp encode_cff_number_same_kind(:one_byte, value)
       when is_integer(value) and value >= -107 and value <= 107,
       do: {:ok, <<value + 139>>}

  defp encode_cff_number_same_kind(:two_byte_positive, value)
       when is_integer(value) and value >= 108 and value <= 1131 do
    adjusted = value - 108
    {:ok, <<247 + div(adjusted, 256), rem(adjusted, 256)>>}
  end

  defp encode_cff_number_same_kind(:two_byte_negative, value)
       when is_integer(value) and value >= -1131 and value <= -108 do
    adjusted = -value - 108
    {:ok, <<251 + div(adjusted, 256), rem(adjusted, 256)>>}
  end

  defp encode_cff_number_same_kind(:shortint, value)
       when is_integer(value) and value >= -32_768 and value <= 32_767,
       do: {:ok, <<28, value::16-signed-big>>}

  defp encode_cff_number_same_kind(:longint, value)
       when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
       do: {:ok, <<29, value::32-signed-big>>}

  defp encode_cff_number_same_kind(:fixed_16_16, value)
       when is_integer(value) and value >= -32_768 and value <= 32_767,
       do: {:ok, <<255, value * 65_536::32-signed-big>>}

  defp encode_cff_number_same_kind(_kind, _value), do: :error

  defp parse_cff_dict_number_meta(<<30, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0 do
    case CFF.parse_real_number(rest) do
      {:ok, value, next_rest, consumed_bytes} ->
        {:ok, %{value: value, start: cursor, length: 1 + consumed_bytes, kind: :real}, next_rest}

      :error ->
        :error
    end
  end

  defp parse_cff_dict_number_meta(<<28, value::16-signed-big, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0,
       do: {:ok, %{value: value, start: cursor, length: 3, kind: :shortint}, rest}

  defp parse_cff_dict_number_meta(<<255, raw_value::32-signed-big, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0,
       do:
         {:ok,
          %{
            value: CFF.fixed_16_16_to_number(raw_value),
            start: cursor,
            length: 5,
            kind: :fixed_16_16
          }, rest}

  defp parse_cff_dict_number_meta(<<29, value::32-signed-big, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0,
       do: {:ok, %{value: value, start: cursor, length: 5, kind: :longint}, rest}

  defp parse_cff_dict_number_meta(<<first::8, second::8, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0 and first >= 247 and first <= 250 do
    value = (first - 247) * 256 + second + 108
    {:ok, %{value: value, start: cursor, length: 2, kind: :two_byte_positive}, rest}
  end

  defp parse_cff_dict_number_meta(<<first::8, second::8, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0 and first >= 251 and first <= 254 do
    value = -((first - 251) * 256 + second + 108)
    {:ok, %{value: value, start: cursor, length: 2, kind: :two_byte_negative}, rest}
  end

  defp parse_cff_dict_number_meta(<<value::8, rest::binary>>, cursor)
       when is_integer(cursor) and cursor >= 0 and value >= 32 and value <= 246 do
    {:ok, %{value: value - 139, start: cursor, length: 1, kind: :one_byte}, rest}
  end

  defp parse_cff_dict_number_meta(_dict_data, _cursor), do: :error

  defp apply_binary_patches_same_length(binary, patches)
       when is_binary(binary) and is_list(patches) do
    sorted_patches =
      Enum.sort_by(patches, fn
        {start, _length, _replacement} -> start
        _ -> -1
      end)

    reduce_result =
      Enum.reduce_while(sorted_patches, {0, []}, fn
        {start, length, replacement}, {cursor_acc, parts_acc}
        when is_integer(start) and is_integer(length) and is_binary(replacement) and
               start >= cursor_acc and length >= 0 and start + length <= byte_size(binary) and
               byte_size(replacement) == length ->
          prefix_size = start - cursor_acc
          prefix = binary_part(binary, cursor_acc, prefix_size)
          {:cont, {start + length, [replacement, prefix | parts_acc]}}

        _, _acc ->
          {:halt, :error}
      end)

    case reduce_result do
      :error ->
        :error

      {final_cursor, parts} when is_integer(final_cursor) and is_list(parts) ->
        suffix = binary_part(binary, final_cursor, byte_size(binary) - final_cursor)
        {:ok, IO.iodata_to_binary(Enum.reverse([suffix | parts]))}
    end
  end

  defp apply_binary_patches_same_length(_binary, _patches), do: :error

  defp parse_cff_charstrings(cff_table)
       when is_binary(cff_table) and byte_size(cff_table) >= 4 do
    case cff_table do
      <<_major::8, _minor::8, header_size::8, _off_size::8, _::binary>>
      when header_size >= 4 and byte_size(cff_table) >= header_size ->
        <<_header::binary-size(header_size), body::binary>> = cff_table

        with {:ok, name_index} <- parse_cff_index_with_offsets(body),
             after_name <- Map.fetch!(name_index, :rest),
             name_size <- Map.fetch!(name_index, :size),
             top_dict_index_start = header_size + name_size,
             {:ok, top_dict_index} <- parse_cff_index_with_offsets(after_name),
             after_top_dict <- Map.fetch!(top_dict_index, :rest),
             top_dict_offsets <- Map.fetch!(top_dict_index, :offsets),
             top_dict_data_start =
               top_dict_index_start + Map.fetch!(top_dict_index, :objects_data_offset),
             [top_dict | _] <- Map.fetch!(top_dict_index, :objects),
             [top_dict_start_offset, top_dict_end_offset | _] <- top_dict_offsets,
             top_dict_offset = top_dict_data_start + top_dict_start_offset - 1,
             top_dict_length = top_dict_end_offset - top_dict_start_offset,
             {:ok, {_string_index, after_string, _string_size}} <-
               parse_cff_index(after_top_dict),
             {:ok, {_global_subr_index, _after_global, _global_size}} <-
               parse_cff_index(after_string),
             {:ok, charstrings_offset} <- cff_dict_operator_operand(top_dict, 17),
             true <- charstrings_offset >= 0 and charstrings_offset < byte_size(cff_table),
             charstrings_data <-
               binary_part(
                 cff_table,
                 charstrings_offset,
                 byte_size(cff_table) - charstrings_offset
               ),
             {:ok, {charstrings, _charstrings_rest, charstrings_size}} <-
               parse_cff_index(charstrings_data) do
          {:ok,
           %{
             charstrings_offset: charstrings_offset,
             charstrings_size: charstrings_size,
             charstrings: charstrings,
             top_dict: top_dict,
             top_dict_offset: top_dict_offset,
             top_dict_length: top_dict_length
           }}
        else
          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp parse_cff_charstrings(_cff_table), do: :error

  defp subset_cff_charstrings(charstrings, used_glyph_ids)
       when is_list(charstrings) and is_map(used_glyph_ids) do
    charstrings
    |> Enum.with_index()
    |> Enum.map(fn {charstring, glyph_id} ->
      keep_original? =
        is_binary(charstring) and byte_size(charstring) > 0 and
          (glyph_id == 0 or MapSet.member?(used_glyph_ids, glyph_id))

      if keep_original? do
        charstring
      else
        <<14>>
      end
    end)
  end

  defp subset_cff_charstrings(_charstrings, _used_glyph_ids), do: []
  defp parse_cff_index_with_offsets(data), do: CFF.parse_index(data)

  defp cff_dict_operator_operand(top_dict, operator)
       when is_binary(top_dict) and is_integer(operator) and operator >= 0 and operator <= 21 do
    scan_cff_dict_operator_operand(top_dict, operator, [])
  end

  defp cff_dict_operator_operand(_top_dict, _operator), do: :error
  defp scan_cff_dict_operator_operand(<<>>, _operator, _operands), do: :error

  defp scan_cff_dict_operator_operand(<<12, _escaped_op::8, rest::binary>>, operator, _operands) do
    scan_cff_dict_operator_operand(rest, operator, [])
  end

  defp scan_cff_dict_operator_operand(<<op::8, rest::binary>>, operator, operands)
       when op <= 21 do
    if op == operator do
      case Enum.reverse(operands) do
        [value | _] when is_integer(value) and value >= 0 -> {:ok, value}
        _ -> :error
      end
    else
      scan_cff_dict_operator_operand(rest, operator, [])
    end
  end

  defp scan_cff_dict_operator_operand(dict_data, operator, operands) do
    case parse_cff_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_operator_operand(rest, operator, [number | operands])

      :error ->
        :error
    end
  end

  defp cff_dict_escaped_operator_operand(top_dict, escaped_operator)
       when is_binary(top_dict) and is_integer(escaped_operator) and escaped_operator >= 0 and
              escaped_operator <= 255 do
    scan_cff_dict_escaped_operator_operand(top_dict, escaped_operator, [])
  end

  defp cff_dict_escaped_operator_operand(_top_dict, _escaped_operator), do: :error
  defp scan_cff_dict_escaped_operator_operand(<<>>, _escaped_operator, _operands), do: :error

  defp scan_cff_dict_escaped_operator_operand(
         <<12, escaped_op::8, rest::binary>>,
         escaped_operator,
         operands
       ) do
    if escaped_op == escaped_operator do
      case Enum.reverse(operands) do
        [value | _] when is_integer(value) and value >= 0 -> {:ok, value}
        _ -> :error
      end
    else
      scan_cff_dict_escaped_operator_operand(rest, escaped_operator, [])
    end
  end

  defp scan_cff_dict_escaped_operator_operand(
         <<op::8, rest::binary>>,
         escaped_operator,
         _operands
       )
       when op <= 21 do
    scan_cff_dict_escaped_operator_operand(rest, escaped_operator, [])
  end

  defp scan_cff_dict_escaped_operator_operand(dict_data, escaped_operator, operands) do
    case parse_cff_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_dict_escaped_operator_operand(rest, escaped_operator, [number | operands])

      :error ->
        :error
    end
  end

  defp encode_cff_index(entries) when is_list(entries) do
    count = length(entries)

    if count == 0 do
      <<0::16-big>>
    else
      normalized_entries =
        Enum.map(entries, fn
          entry when is_binary(entry) and byte_size(entry) > 0 -> entry
          _ -> <<14>>
        end)

      entry_data = IO.iodata_to_binary(normalized_entries)

      offsets =
        normalized_entries
        |> Enum.reduce({[1], 1}, fn entry, {acc, cursor} ->
          next_cursor = cursor + byte_size(entry)
          {[next_cursor | acc], next_cursor}
        end)
        |> elem(0)
        |> Enum.reverse()

      max_offset = List.last(offsets)

      off_size =
        cond do
          max_offset <= 0xFF -> 1
          max_offset <= 0xFFFF -> 2
          max_offset <= 0xFF_FFFF -> 3
          true -> 4
        end

      encoded_offsets =
        offsets
        |> Enum.map(&encode_cff_index_offset(&1, off_size))
        |> IO.iodata_to_binary()

      <<count::16-big, off_size::8, encoded_offsets::binary, entry_data::binary>>
    end
  end

  defp encode_cff_index_offset(offset, off_size)
       when is_integer(offset) and offset >= 0 and is_integer(off_size) and off_size >= 1 and
              off_size <= 4 do
    encoded = :binary.encode_unsigned(offset)
    padding_bytes = max(off_size - byte_size(encoded), 0)
    <<0::size(padding_bytes)-unit(8), encoded::binary>>
  end

  defp subset_ttf_glyf_and_loca(glyf_table, ttf_metrics, used_glyph_ids)
       when is_binary(glyf_table) and is_map(ttf_metrics) and is_map(used_glyph_ids) do
    with glyph_offsets when is_list(glyph_offsets) <- Map.get(ttf_metrics, :glyph_offsets),
         num_glyphs when is_integer(num_glyphs) and num_glyphs > 0 <-
           Map.get(ttf_metrics, :num_glyphs),
         index_to_loc_format when index_to_loc_format in [0, 1] <-
           Map.get(ttf_metrics, :index_to_loc_format),
         true <- length(glyph_offsets) == num_glyphs + 1,
         last_offset when is_integer(last_offset) and last_offset <= byte_size(glyf_table) <-
           List.last(glyph_offsets),
         {:ok, expanded_used_glyph_ids} <-
           expand_ttf_composite_glyph_ids(glyf_table, glyph_offsets, num_glyphs, used_glyph_ids),
         {:ok, subset_glyf_table, subset_offsets} <-
           subset_glyf_table(
             glyf_table,
             glyph_offsets,
             index_to_loc_format,
             expanded_used_glyph_ids
           ),
         {:ok, subset_loca_table} <- encode_loca_offsets(subset_offsets, index_to_loc_format) do
      _ = last_offset
      {:ok, subset_glyf_table, subset_loca_table}
    else
      {:error, :invalid_composite_component_reference} ->
        {:error, :invalid_composite_component_reference}

      {:error, :malformed_composite_component_records} ->
        {:error, :malformed_composite_component_records}

      _ ->
        :error
    end
  end

  defp subset_ttf_glyf_and_loca(_glyf_table, _ttf_metrics, _used_glyph_ids), do: :error

  defp expand_ttf_composite_glyph_ids(glyf_table, glyph_offsets, num_glyphs, used_glyph_ids)
       when is_binary(glyf_table) and is_list(glyph_offsets) and is_integer(num_glyphs) and
              num_glyphs > 0 and is_map(used_glyph_ids) do
    initial_glyph_ids =
      used_glyph_ids
      |> MapSet.to_list()
      |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 < num_glyphs))

    do_expand_ttf_composite_glyph_ids(
      glyf_table,
      glyph_offsets,
      num_glyphs,
      MapSet.new(initial_glyph_ids),
      initial_glyph_ids
    )
  end

  defp expand_ttf_composite_glyph_ids(_glyf_table, _glyph_offsets, _num_glyphs, _used_glyph_ids),
    do: :error

  defp do_expand_ttf_composite_glyph_ids(
         _glyf_table,
         _glyph_offsets,
         _num_glyphs,
         used_glyph_ids,
         []
       ),
       do: {:ok, used_glyph_ids}

  defp do_expand_ttf_composite_glyph_ids(
         glyf_table,
         glyph_offsets,
         num_glyphs,
         used_glyph_ids,
         [glyph_id | rest_queue]
       ) do
    with {:ok, glyph_data} <- glyph_data_for_id(glyf_table, glyph_offsets, glyph_id) do
      case composite_component_glyph_ids(glyph_data) do
        {:ok, component_glyph_ids} ->
          if Enum.all?(component_glyph_ids, &(is_integer(&1) and &1 >= 0 and &1 < num_glyphs)) do
            {next_used_glyph_ids, next_queue} =
              Enum.reduce(
                component_glyph_ids,
                {used_glyph_ids, rest_queue},
                fn component_glyph_id, {used_acc, queue_acc} ->
                  if MapSet.member?(used_acc, component_glyph_id) do
                    {used_acc, queue_acc}
                  else
                    {MapSet.put(used_acc, component_glyph_id), [component_glyph_id | queue_acc]}
                  end
                end
              )

            do_expand_ttf_composite_glyph_ids(
              glyf_table,
              glyph_offsets,
              num_glyphs,
              next_used_glyph_ids,
              next_queue
            )
          else
            {:error, :invalid_composite_component_reference}
          end

        :error ->
          {:error, :malformed_composite_component_records}
      end
    else
      _ ->
        :error
    end
  end

  defp glyph_data_for_id(glyf_table, glyph_offsets, glyph_id)
       when is_binary(glyf_table) and is_list(glyph_offsets) and is_integer(glyph_id) and
              glyph_id >= 0 do
    case Enum.at(glyph_offsets, glyph_id) do
      start_offset when is_integer(start_offset) ->
        case Enum.at(glyph_offsets, glyph_id + 1) do
          end_offset
          when is_integer(end_offset) and start_offset >= 0 and end_offset >= start_offset and
                 end_offset <= byte_size(glyf_table) ->
            {:ok, binary_part(glyf_table, start_offset, end_offset - start_offset)}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp glyph_data_for_id(_glyf_table, _glyph_offsets, _glyph_id), do: :error

  # A glyph with no outline is encoded as loca[i] == loca[i+1], i.e. zero bytes
  # of glyph data. This is legal and common - the space character does it, as
  # does every non-marking character. It has no components to follow.
  #
  # Without this clause an empty glyph falls through to the catch-all :error,
  # which aborts the whole subset and silently falls back to embedding the full
  # font. Since almost every real string contains a space, that defeated
  # subsetting for essentially all real text.
  defp composite_component_glyph_ids(<<>>), do: {:ok, []}

  defp composite_component_glyph_ids(<<num_contours::16-signed-big, _rest::binary>> = glyph_data)
       when num_contours >= 0 do
    if byte_size(glyph_data) >= 10 do
      {:ok, []}
    else
      :error
    end
  end

  defp composite_component_glyph_ids(
         <<num_contours::16-signed-big, _x_min::16-signed-big, _y_min::16-signed-big,
           _x_max::16-signed-big, _y_max::16-signed-big, components::binary>>
       )
       when num_contours < 0 do
    parse_composite_component_records(components, [])
  end

  defp composite_component_glyph_ids(_glyph_data), do: :error

  defp parse_composite_component_records(
         <<flags::16-big, glyph_id::16-big, rest::binary>>,
         reverse_components
       ) do
    with {:ok, rest_after_args} <- consume_composite_component_args(rest, flags),
         {:ok, rest_after_transform} <-
           consume_composite_component_transform(rest_after_args, flags),
         {:ok, rest_after_instructions} <-
           consume_composite_component_instructions(rest_after_transform, flags),
         next_components <- [glyph_id | reverse_components] do
      if (flags &&& 0x0020) != 0 do
        parse_composite_component_records(rest_after_instructions, next_components)
      else
        {:ok, Enum.reverse(next_components)}
      end
    else
      _ ->
        :error
    end
  end

  defp parse_composite_component_records(_invalid_components, _reverse_components), do: :error

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
          {:ok, remaining}

        _ ->
          :error
      end
    else
      {:ok, rest}
    end
  end

  defp subset_glyf_table(glyf_table, glyph_offsets, index_to_loc_format, used_glyph_ids)
       when is_binary(glyf_table) and is_list(glyph_offsets) and index_to_loc_format in [0, 1] and
              is_map(used_glyph_ids) do
    pairs = Enum.chunk_every(glyph_offsets, 2, 1, :discard)

    result =
      pairs
      |> Enum.with_index()
      |> Enum.reduce_while({[], [0], 0}, fn {[start_offset, end_offset], glyph_id},
                                            {parts_acc, offsets_acc, cursor} ->
        cond do
          not is_integer(start_offset) or not is_integer(end_offset) ->
            {:halt, :error}

          start_offset < 0 or end_offset < start_offset or end_offset > byte_size(glyf_table) ->
            {:halt, :error}

          MapSet.member?(used_glyph_ids, glyph_id) and end_offset > start_offset ->
            glyph_data = binary_part(glyf_table, start_offset, end_offset - start_offset)
            glyph_data = maybe_pad_glyph_data(glyph_data, index_to_loc_format)
            next_cursor = cursor + byte_size(glyph_data)
            {:cont, {[glyph_data | parts_acc], [next_cursor | offsets_acc], next_cursor}}

          true ->
            {:cont, {parts_acc, [cursor | offsets_acc], cursor}}
        end
      end)

    case result do
      :error ->
        :error

      {parts_acc, offsets_acc, _cursor} ->
        subset_glyf_table = parts_acc |> Enum.reverse() |> IO.iodata_to_binary()
        subset_offsets = Enum.reverse(offsets_acc)
        {:ok, subset_glyf_table, subset_offsets}
    end
  end

  defp subset_glyf_table(_glyf_table, _glyph_offsets, _index_to_loc_format, _used_glyph_ids),
    do: :error

  defp maybe_pad_glyph_data(glyph_data, 0) when is_binary(glyph_data) do
    if rem(byte_size(glyph_data), 2) == 0 do
      glyph_data
    else
      <<glyph_data::binary, 0>>
    end
  end

  defp maybe_pad_glyph_data(glyph_data, _index_to_loc_format), do: glyph_data

  defp encode_loca_offsets(offsets, 0) when is_list(offsets) do
    encoded =
      Enum.reduce_while(offsets, [], fn offset, acc ->
        if is_integer(offset) and offset >= 0 and rem(offset, 2) == 0 and div(offset, 2) <= 65_535 do
          {:cont, [<<div(offset, 2)::16-big>> | acc]}
        else
          {:halt, :error}
        end
      end)

    case encoded do
      :error -> :error
      binaries -> {:ok, binaries |> Enum.reverse() |> IO.iodata_to_binary()}
    end
  end

  defp encode_loca_offsets(offsets, 1) when is_list(offsets) do
    encoded =
      offsets
      |> Enum.reduce_while([], fn offset, acc ->
        if is_integer(offset) and offset >= 0 and offset <= 4_294_967_295 do
          {:cont, [<<offset::32-big>> | acc]}
        else
          {:halt, :error}
        end
      end)

    case encoded do
      :error -> :error
      binaries -> {:ok, binaries |> Enum.reverse() |> IO.iodata_to_binary()}
    end
  end

  defp encode_loca_offsets(_offsets, _index_to_loc_format), do: :error

  defp parse_sfnt_tables(
         <<sfnt_version::binary-size(4), num_tables::16-big, _search_range::16-big,
           _entry_selector::16-big, _range_shift::16-big, rest::binary>> = data
       ) do
    required_record_bytes = num_tables * 16

    if byte_size(rest) < required_record_bytes do
      :error
    else
      <<record_bytes::binary-size(required_record_bytes), _::binary>> = rest
      parse_sfnt_table_records(record_bytes, data, sfnt_version, [], %{})
    end
  end

  defp parse_sfnt_tables(_data), do: :error

  defp parse_sfnt_table_records(<<>>, _data, sfnt_version, reverse_table_order, tables) do
    {:ok, sfnt_version, Enum.reverse(reverse_table_order), tables}
  end

  defp parse_sfnt_table_records(
         <<tag::binary-size(4), _checksum::32-big, offset::32-big, length::32-big, rest::binary>>,
         data,
         sfnt_version,
         reverse_table_order,
         tables
       ) do
    data_size = byte_size(data)

    if offset <= data_size and length <= data_size - offset do
      table_data = binary_part(data, offset, length)

      parse_sfnt_table_records(
        rest,
        data,
        sfnt_version,
        [tag | reverse_table_order],
        Map.put(tables, tag, table_data)
      )
    else
      :error
    end
  end

  defp parse_sfnt_table_records(
         _invalid_records,
         _data,
         _sfnt_version,
         _reverse_table_order,
         _tables
       ),
       do: :error

  defp build_sfnt(sfnt_version, table_order, tables)
       when is_binary(sfnt_version) and byte_size(sfnt_version) == 4 and is_list(table_order) and
              is_map(tables) do
    num_tables = length(table_order)
    {search_range, entry_selector, range_shift} = sfnt_search_fields(num_tables)

    header =
      <<sfnt_version::binary-size(4), num_tables::16-big, search_range::16-big,
        entry_selector::16-big, range_shift::16-big>>

    table_dir_size = num_tables * 16
    base_offset = byte_size(header) + table_dir_size

    {reverse_records, reverse_binaries, _next_offset, head_offset, head_length} =
      Enum.reduce(
        table_order,
        {[], [], base_offset, nil, nil},
        fn tag, {rec_acc, bin_acc, offset, head_offset_acc, head_length_acc} ->
          table_data = Map.fetch!(tables, tag)
          length = byte_size(table_data)
          checksum_data = sfnt_table_checksum_data(tag, table_data)
          checksum = sfnt_table_checksum(checksum_data)
          padded_table_data = pad_sfnt_table_data(table_data)
          record = <<tag::binary-size(4), checksum::32-big, offset::32-big, length::32-big>>
          next_offset = offset + byte_size(padded_table_data)
          next_head_offset = if tag == "head", do: offset, else: head_offset_acc
          next_head_length = if tag == "head", do: length, else: head_length_acc

          {[record | rec_acc], [padded_table_data | bin_acc], next_offset, next_head_offset,
           next_head_length}
        end
      )

    sfnt =
      IO.iodata_to_binary([header, Enum.reverse(reverse_records), Enum.reverse(reverse_binaries)])

    apply_sfnt_head_check_sum_adjustment(sfnt, head_offset, head_length)
  end

  defp sfnt_search_fields(num_tables) when is_integer(num_tables) and num_tables > 0 do
    max_power_of_two = highest_power_of_two_leq(num_tables)
    entry_selector = log2_power_of_two(max_power_of_two)
    search_range = max_power_of_two * 16
    range_shift = num_tables * 16 - search_range
    {search_range, entry_selector, range_shift}
  end

  defp sfnt_search_fields(_num_tables), do: {0, 0, 0}

  defp highest_power_of_two_leq(num_tables) when is_integer(num_tables) and num_tables > 0 do
    do_highest_power_of_two_leq(1, num_tables)
  end

  defp do_highest_power_of_two_leq(power, num_tables) when power * 2 <= num_tables do
    do_highest_power_of_two_leq(power * 2, num_tables)
  end

  defp do_highest_power_of_two_leq(power, _num_tables), do: power
  defp log2_power_of_two(1), do: 0

  defp log2_power_of_two(power) when is_integer(power) and power > 1,
    do: 1 + log2_power_of_two(div(power, 2))

  defp pad_sfnt_table_data(table_data) when is_binary(table_data) do
    case rem(byte_size(table_data), 4) do
      0 -> table_data
      remainder -> <<table_data::binary, 0::size((4 - remainder) * 8)>>
    end
  end

  defp sfnt_table_checksum_data("head", table_data) when is_binary(table_data) do
    zero_head_check_sum_adjustment(table_data)
  end

  defp sfnt_table_checksum_data(_tag, table_data) when is_binary(table_data), do: table_data

  defp zero_head_check_sum_adjustment(table_data) when is_binary(table_data) do
    if byte_size(table_data) >= 12 do
      write_u32_big_at(table_data, 8, 0)
    else
      table_data
    end
  end

  defp apply_sfnt_head_check_sum_adjustment(sfnt, head_offset, head_length)
       when is_binary(sfnt) and is_integer(head_offset) and is_integer(head_length) and
              head_offset >= 0 and head_length >= 12 and
              head_offset + head_length <= byte_size(sfnt) do
    sfnt_with_zero_adjustment = write_u32_big_at(sfnt, head_offset + 8, 0)
    checksum = sfnt_table_checksum(sfnt_with_zero_adjustment)
    check_sum_adjustment = @sfnt_checksum_magic - checksum &&& 0xFFFF_FFFF
    write_u32_big_at(sfnt_with_zero_adjustment, head_offset + 8, check_sum_adjustment)
  end

  defp apply_sfnt_head_check_sum_adjustment(sfnt, _head_offset, _head_length), do: sfnt

  defp write_u32_big_at(binary, offset, value)
       when is_binary(binary) and is_integer(offset) and is_integer(value) and offset >= 0 and
              offset + 4 <= byte_size(binary) do
    prefix_size = offset
    suffix_size = byte_size(binary) - offset - 4

    <<prefix::binary-size(prefix_size), _old_value::32-big, suffix::binary-size(suffix_size)>> =
      binary

    <<prefix::binary, value::32-big, suffix::binary>>
  end

  defp sfnt_table_checksum(table_data) when is_binary(table_data) do
    padding =
      case rem(byte_size(table_data), 4) do
        0 -> 0
        rem_bytes -> 4 - rem_bytes
      end

    padded_data =
      if padding == 0 do
        table_data
      else
        <<table_data::binary, 0::size(padding)-unit(8)>>
      end

    sfnt_table_checksum_words(padded_data, 0)
  end

  defp sfnt_table_checksum_words(<<>>, sum), do: sum

  defp sfnt_table_checksum_words(<<word::32-big, rest::binary>>, sum) do
    sfnt_table_checksum_words(rest, sum + word &&& 0xFFFF_FFFF)
  end

  # No /CIDSet. It is optional in PDF 1.7 and deprecated in PDF 2.0, required
  # only by PDF/A-1, and it must identify exactly the CIDs present in the
  # embedded program. Subsetting here falls back to the whole font on several
  # paths while the name keeps its subset tag, so the retained set is not
  # reliably knowable at this point - and an inaccurate CIDSet is a conformance
  # failure where an absent one is not. Reinstating it correctly is a
  # prerequisite for PDF/A-1, not for PDF/UA.
  defp embedded_font_descriptor_object(embedded_font, font_file_id) do
    font_name = embedded_pdf_font_name(embedded_font)
    font_file_ref = embedded_font_descriptor_font_file_ref(embedded_font, font_file_id)
    stretch_ref = embedded_font_stretch_ref(embedded_font)
    family_ref = embedded_font_family_ref(embedded_font)
    weight_ref = embedded_font_weight_ref(embedded_font)
    avg_width_ref = embedded_font_avg_width_ref(embedded_font)
    max_width_ref = embedded_font_max_width_ref(embedded_font)
    missing_width_ref = embedded_font_missing_width_ref(embedded_font)
    fs_type_ref = embedded_font_fs_type_ref(embedded_font)
    style_ref = embedded_font_style_ref(embedded_font)
    {x_min, y_min, x_max, y_max} = embedded_font_bbox(embedded_font)

    {ascent, descent, leading, x_height, cap_height} =
      embedded_font_vertical_metrics(embedded_font)

    {flags, italic_angle} = embedded_font_descriptor_style_metrics(embedded_font)
    stem_v = embedded_font_stem_v(embedded_font)
    stem_h = embedded_font_stem_h(embedded_font, stem_v)

    "<< /Type /FontDescriptor /FontName /#{font_name} /Flags #{flags} /FontBBox [#{x_min} #{y_min} #{x_max} #{y_max}]#{stretch_ref}#{family_ref}#{weight_ref}#{avg_width_ref}#{max_width_ref}#{missing_width_ref}#{fs_type_ref}#{style_ref} /ItalicAngle #{Object.num(italic_angle)} /Ascent #{ascent} /Descent #{descent} /Leading #{leading} /XHeight #{x_height} /CapHeight #{cap_height} /StemV #{stem_v} /StemH #{stem_h}#{font_file_ref} >>"
  end

  defp embedded_font_descriptor_font_file_ref(embedded_font, font_file_id) do
    case Map.fetch!(embedded_font, :format) do
      :ttf -> " /FontFile2 #{font_file_id} 0 R"
      :otf -> " /FontFile3 #{font_file_id} 0 R"
    end
  end

  defp build_embedded_font_family_objects(
         embedded_font,
         next_id,
         used_char_codes,
         used_cids,
         scalar_codepoints,
         variation_sequences,
         to_unicode_mappings,
         true
       ) do
    font_file_id = next_id
    descriptor_id = next_id + 1
    cid_to_gid_map_id = next_id + 2

    {cid_to_gid_map_ref, cid_to_gid_map_object, cid_font_id} =
      embedded_cid_to_gid_map_object(
        embedded_font,
        used_cids,
        scalar_codepoints,
        variation_sequences,
        cid_to_gid_map_id
      )

    to_unicode_id = cid_font_id + 1

    if Map.get(embedded_font, :subset, :none) != :none do
      type0_font_id = to_unicode_id + 1

      objects =
        [
          embedded_font_file_object(embedded_font, used_char_codes, scalar_codepoints),
          embedded_font_descriptor_object(embedded_font, font_file_id),
          cid_to_gid_map_object,
          embedded_cid_font_object(
            embedded_font,
            descriptor_id,
            used_cids,
            scalar_codepoints,
            variation_sequences,
            cid_to_gid_map_ref
          ),
          to_unicode_cmap_object(to_unicode_mappings),
          embedded_type0_font_object(embedded_font, cid_font_id, to_unicode_id)
        ]
        |> Enum.reject(&is_nil/1)

      {type0_font_id, objects, type0_font_id + 1, :identity_h}
    else
      type0_font_id = to_unicode_id + 1

      objects =
        [
          embedded_font_file_object(embedded_font, used_char_codes, scalar_codepoints),
          embedded_font_descriptor_object(embedded_font, font_file_id),
          cid_to_gid_map_object,
          embedded_cid_font_object(
            embedded_font,
            descriptor_id,
            used_cids,
            scalar_codepoints,
            variation_sequences,
            cid_to_gid_map_ref
          ),
          to_unicode_cmap_object(to_unicode_mappings),
          embedded_type0_font_object(embedded_font, cid_font_id, to_unicode_id)
        ]
        |> Enum.reject(&is_nil/1)

      {type0_font_id, objects, type0_font_id + 1, :identity_h}
    end
  end

  defp build_embedded_font_family_objects(
         embedded_font,
         next_id,
         used_char_codes,
         _used_cids,
         _scalar_codepoints,
         _variation_sequences,
         _to_unicode_mappings,
         false
       ) do
    font_file_id = next_id
    descriptor_id = next_id + 1
    font_id = next_id + 2

    objects = [
      embedded_font_file_object(embedded_font, used_char_codes, []),
      embedded_font_descriptor_object(embedded_font, font_file_id),
      embedded_font_object(embedded_font, descriptor_id, used_char_codes)
    ]

    {font_id, objects, next_id + 3, :pdf_text}
  end

  defp embedded_cid_font_object(
         embedded_font,
         descriptor_id,
         used_cids,
         scalar_codepoints,
         variation_sequences,
         cid_to_gid_map_ref
       ) do
    font_name = embedded_pdf_font_name(embedded_font)
    default_width = embedded_cid_default_width(embedded_font)

    width_entries =
      embedded_cid_width_entries(
        embedded_font,
        used_cids,
        scalar_codepoints,
        variation_sequences
      )

    width_section = if width_entries == "", do: "", else: " /W [#{width_entries}]"
    subtype = embedded_cid_font_subtype(embedded_font)

    "<< /Type /Font /Subtype /#{subtype} /BaseFont /#{font_name} /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor #{descriptor_id} 0 R#{cid_to_gid_map_ref} /DW #{default_width}#{width_section} >>"
  end

  defp embedded_cid_font_subtype(embedded_font) do
    case Map.fetch!(embedded_font, :format) do
      :ttf -> "CIDFontType2"
      :otf -> "CIDFontType0"
    end
  end

  defp embedded_cid_to_gid_map_object(
         embedded_font,
         used_cids,
         scalar_codepoints,
         variation_sequences,
         object_id
       )
       when is_integer(object_id) and object_id > 0 do
    case Map.fetch!(embedded_font, :format) do
      :otf ->
        {"", nil, object_id}

      :ttf ->
        case embedded_cid_to_gid_map_binary(
               embedded_font,
               used_cids,
               scalar_codepoints,
               variation_sequences
             ) do
          data when is_binary(data) and byte_size(data) > 0 ->
            {" /CIDToGIDMap #{object_id} 0 R", cid_to_gid_map_object(data), object_id + 1}

          :ambiguous ->
            Logger.warning(
              "embedded TTF Type0 CIDToGIDMap fallback to /Identity for font #{Map.get(embedded_font, :name, "unknown")} due to ambiguous non-BMP surrogate mappings"
            )

            {" /CIDToGIDMap /Identity", nil, object_id}

          _ ->
            {" /CIDToGIDMap /Identity", nil, object_id}
        end
    end
  end

  defp embedded_cid_to_gid_map_binary(
         embedded_font,
         used_cids,
         scalar_codepoints,
         variation_sequences
       ) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{cmap_by_code: cmap_by_code} when is_map(cmap_by_code) and map_size(cmap_by_code) > 0 ->
        with {:ok, surrogate_overrides} <-
               non_bmp_cid_to_gid_overrides(cmap_by_code, scalar_codepoints),
             {:ok, variation_overrides} <-
               variation_cid_to_gid_overrides(embedded_font, variation_sequences),
             {:ok, cid_overrides} <- merge_override_maps(surrogate_overrides, variation_overrides) do
          max_cid =
            case normalize_used_cids(used_cids) do
              [] -> 0
              cids -> List.last(cids)
            end

          0..max_cid
          |> Enum.map(fn cid ->
            glyph_id =
              case Map.get(cid_overrides, cid) do
                override when is_integer(override) and override >= 0 ->
                  override

                _ ->
                  mapped_cmap_glyph_id(cmap_by_code, cid)
              end

            <<normalize_cid_to_gid_value(glyph_id)::16-big>>
          end)
          |> IO.iodata_to_binary()
        else
          :ambiguous ->
            :ambiguous
        end

      _ ->
        nil
    end
  end

  defp normalize_cid_to_gid_value(glyph_id)
       when is_integer(glyph_id) and glyph_id >= 0 and glyph_id <= 65_535,
       do: glyph_id

  defp normalize_cid_to_gid_value(_glyph_id), do: 0

  defp mapped_cmap_glyph_id(cmap_by_code, codepoint)
       when is_map(cmap_by_code) and is_integer(codepoint) and codepoint >= 0 do
    case Map.get(cmap_by_code, codepoint) do
      glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
        glyph_id

      _ ->
        0
    end
  end

  defp mapped_cmap_glyph_id(_cmap_by_code, _codepoint), do: 0

  defp mapped_cmap_glyph_id_or_nil(cmap_by_code, codepoint)
       when is_map(cmap_by_code) and is_integer(codepoint) and codepoint >= 0 do
    case Map.get(cmap_by_code, codepoint) do
      glyph_id when is_integer(glyph_id) and glyph_id >= 0 -> glyph_id
      _ -> nil
    end
  end

  defp mapped_cmap_glyph_id_or_nil(_cmap_by_code, _codepoint), do: nil

  defp non_bmp_cid_to_gid_overrides(cmap_by_code, scalar_codepoints)
       when is_map(cmap_by_code) do
    scalar_codepoints
    |> List.wrap()
    |> Enum.filter(&(is_integer(&1) and &1 > 0xFFFF and &1 <= 0x10FFFF))
    |> Enum.reduce_while({:ok, %{}}, fn codepoint, {:ok, acc} ->
      case Map.get(cmap_by_code, codepoint) do
        glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
          case utf16_code_units(<<codepoint::utf8>>) do
            [hi, lo] ->
              case Map.get(acc, hi) do
                nil ->
                  {:cont, {:ok, acc |> Map.put(hi, glyph_id) |> Map.put(lo, 0)}}

                existing when existing == glyph_id ->
                  {:cont, {:ok, Map.put(acc, lo, 0)}}

                _different_existing ->
                  {:halt, :ambiguous}
              end

            _ ->
              {:cont, {:ok, acc}}
          end

        _ ->
          {:cont, {:ok, acc}}
      end
    end)
  end

  defp non_bmp_cid_to_gid_overrides(_cmap_by_code, _scalar_codepoints), do: {:ok, %{}}

  defp cid_to_gid_map_object(data) when is_binary(data) do
    compressed = :zlib.compress(data)
    length = byte_size(compressed)
    ["<< /Length #{length} /Filter /FlateDecode >>\nstream\n", compressed, "\nendstream"]
  end

  defp embedded_cid_default_width(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{advance_widths: advance_widths, units_per_em: units_per_em}
      when is_list(advance_widths) and is_integer(units_per_em) and units_per_em > 0 ->
        width_for_glyph_id(advance_widths, 0, units_per_em)

      _ ->
        600
    end
  end

  defp embedded_type0_font_object(embedded_font, cid_font_id, to_unicode_id) do
    font_name = embedded_pdf_font_name(embedded_font)

    "<< /Type /Font /Subtype /Type0 /BaseFont /#{font_name} /Encoding /Identity-H /DescendantFonts [#{cid_font_id} 0 R] /ToUnicode #{to_unicode_id} 0 R >>"
  end

  defp to_unicode_cmap_object(used_mappings) do
    mappings = normalize_to_unicode_mappings(used_mappings)
    codespace_ranges = to_unicode_codespace_ranges(mappings)
    {bfrange_entries, bfchar_entries} = compact_to_unicode_mappings(mappings)

    bfrange_sections =
      bfrange_entries
      |> Enum.chunk_every(100)
      |> Enum.map(fn chunk ->
        lines =
          chunk
          |> Enum.map_join("\n", fn {start_src_hex, end_src_hex, start_dst_hex} ->
            "<#{start_src_hex}> <#{end_src_hex}> <#{start_dst_hex}>"
          end)

        ["#{length(chunk)} beginbfrange\n", lines, "\nendbfrange\n"]
      end)

    bfchar_sections =
      bfchar_entries
      |> Enum.chunk_every(100)
      |> Enum.map(fn chunk ->
        lines =
          chunk
          |> Enum.map_join("\n", fn {source_hex, destination_hex} ->
            "<#{source_hex}> <#{destination_hex}>"
          end)

        ["#{length(chunk)} beginbfchar\n", lines, "\nendbfchar\n"]
      end)

    cmap_stream = [
      "/CIDInit /ProcSet findresource begin\n",
      "12 dict begin\n",
      "begincmap\n",
      "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def\n",
      "/CMapName /Adobe-Identity-UCS def\n",
      "/CMapType 2 def\n",
      "#{length(codespace_ranges)} begincodespacerange\n",
      Enum.map(codespace_ranges, fn {start_hex, end_hex} -> "<#{start_hex}> <#{end_hex}>\n" end),
      "endcodespacerange\n",
      bfrange_sections,
      bfchar_sections,
      "endcmap\n",
      "CMapName currentdict /CMap defineresource pop\n",
      "end\n",
      "end\n"
    ]

    length = IO.iodata_length(cmap_stream)
    ["<< /Length #{length} >>\nstream\n", cmap_stream, "endstream"]
  end

  defp normalize_to_unicode_mappings(used_mappings) do
    used_mappings
    |> List.wrap()
    |> Enum.filter(fn
      {source_hex, destination_hex} when is_binary(source_hex) and is_binary(destination_hex) ->
        byte_size(source_hex) in [4, 8] and byte_size(destination_hex) in [4, 8]

      _ ->
        false
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> case do
      [] -> [{"0000", "0000"}]
      entries -> entries
    end
  end

  defp to_unicode_codespace_ranges(mappings) do
    lengths =
      mappings
      |> Enum.map(fn {source_hex, _destination_hex} -> byte_size(source_hex) end)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.flat_map(lengths, fn
      4 -> [{"0000", "FFFF"}]
      8 -> [{"00000000", "FFFFFFFF"}]
      _ -> []
    end)
  end

  defp embedded_cid_width_entries(
         embedded_font,
         used_cids,
         scalar_codepoints,
         variation_sequences
       ) do
    cids = normalize_used_cids(used_cids)

    scalar_overrides =
      with {:ok, non_bmp_overrides} <-
             non_bmp_cid_width_overrides(embedded_font, scalar_codepoints),
           {:ok, variation_overrides} <-
             variation_cid_width_overrides(embedded_font, variation_sequences),
           {:ok, merged} <- merge_override_maps(non_bmp_overrides, variation_overrides) do
        merged
      else
        :ambiguous ->
          Logger.warning(
            "embedded TTF Type0 width override fallback for font #{Map.get(embedded_font, :name, "unknown")} due to ambiguous non-BMP surrogate widths"
          )

          %{}
      end

    cid_width_pairs =
      case Map.get(embedded_font, :ttf_metrics) do
        %{advance_widths: advance_widths, units_per_em: units_per_em} = ttf_metrics
        when is_list(advance_widths) and is_integer(units_per_em) and units_per_em > 0 ->
          cmap_by_code = Map.get(ttf_metrics, :cmap_by_code, %{})

          cids
          |> Enum.map(fn cid ->
            width =
              case Map.get(scalar_overrides, cid) do
                nil ->
                  case mapped_cmap_glyph_id_or_nil(cmap_by_code, cid) do
                    glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
                      width_for_glyph_id(advance_widths, glyph_id, units_per_em)

                    nil ->
                      if Unicode.zero_advance_codepoint?(cid) do
                        0
                      else
                        glyph_id = glyph_id_for_char_code(cid, cmap_by_code)
                        width_for_glyph_id(advance_widths, glyph_id, units_per_em)
                      end
                  end

                override_width ->
                  override_width
              end

            {cid, width}
          end)

        _ ->
          Enum.map(cids, fn cid ->
            width =
              case Map.get(scalar_overrides, cid) do
                nil -> if(Unicode.zero_advance_codepoint?(cid), do: 0, else: 600)
                override_width -> override_width
              end

            {cid, width}
          end)
      end

    cid_width_pairs
    |> compact_cid_width_pairs()
    |> Enum.join(" ")
  end

  defp non_bmp_cid_width_overrides(embedded_font, scalar_codepoints) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{advance_widths: advance_widths, units_per_em: units_per_em} = ttf_metrics
      when is_list(advance_widths) and is_integer(units_per_em) and units_per_em > 0 ->
        cmap_by_code = Map.get(ttf_metrics, :cmap_by_code, %{})

        scalar_codepoints
        |> List.wrap()
        |> Enum.filter(&(is_integer(&1) and &1 > 0xFFFF and &1 <= 0x10FFFF))
        |> Enum.reduce_while({:ok, %{}}, fn codepoint, {:ok, acc} ->
          case Map.get(cmap_by_code, codepoint) do
            glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
              width = width_for_glyph_id(advance_widths, glyph_id, units_per_em)

              case utf16_code_units(<<codepoint::utf8>>) do
                [hi, lo] ->
                  case Map.get(acc, hi) do
                    nil ->
                      {:cont, {:ok, acc |> Map.put(hi, width) |> Map.put(lo, 0)}}

                    existing when existing == width ->
                      {:cont, {:ok, Map.put(acc, lo, 0)}}

                    _different_existing ->
                      {:halt, :ambiguous}
                  end

                _ ->
                  {:cont, {:ok, acc}}
              end

            _ ->
              {:cont, {:ok, acc}}
          end
        end)

      _ ->
        {:ok, %{}}
    end
  end

  defp variation_cid_width_overrides(embedded_font, variation_sequences) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{
        advance_widths: advance_widths,
        units_per_em: units_per_em,
        cmap_non_default_uvs: cmap_non_default_uvs
      }
      when is_list(advance_widths) and is_integer(units_per_em) and units_per_em > 0 and
             is_map(cmap_non_default_uvs) ->
        variation_sequences
        |> List.wrap()
        |> Enum.reduce_while({:ok, %{}}, fn
          {base_codepoint, selector_codepoint}, {:ok, acc}
          when is_integer(base_codepoint) and is_integer(selector_codepoint) ->
            case Map.get(cmap_non_default_uvs, {base_codepoint, selector_codepoint}) do
              glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
                width = width_for_glyph_id(advance_widths, glyph_id, units_per_em)

                with {:ok, next_acc} <- put_base_codepoint_override(acc, base_codepoint, width),
                     {:ok, selector_units} <- utf16_units_for_codepoint(selector_codepoint),
                     {:ok, final_acc} <- put_units_override(next_acc, selector_units, 0) do
                  {:cont, {:ok, final_acc}}
                else
                  _ -> {:halt, :ambiguous}
                end

              _ ->
                {:cont, {:ok, acc}}
            end

          _other, {:ok, acc} ->
            {:cont, {:ok, acc}}
        end)

      _ ->
        {:ok, %{}}
    end
  end

  defp variation_cid_to_gid_overrides(embedded_font, variation_sequences) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{cmap_non_default_uvs: cmap_non_default_uvs}
      when is_map(cmap_non_default_uvs) ->
        variation_sequences
        |> List.wrap()
        |> Enum.reduce_while({:ok, %{}}, fn
          {base_codepoint, selector_codepoint}, {:ok, acc}
          when is_integer(base_codepoint) and is_integer(selector_codepoint) ->
            case Map.get(cmap_non_default_uvs, {base_codepoint, selector_codepoint}) do
              glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
                with {:ok, next_acc} <-
                       put_base_codepoint_override(acc, base_codepoint, glyph_id),
                     {:ok, selector_units} <- utf16_units_for_codepoint(selector_codepoint),
                     {:ok, final_acc} <- put_units_override(next_acc, selector_units, 0) do
                  {:cont, {:ok, final_acc}}
                else
                  _ -> {:halt, :ambiguous}
                end

              _ ->
                {:cont, {:ok, acc}}
            end

          _other, {:ok, acc} ->
            {:cont, {:ok, acc}}
        end)

      _ ->
        {:ok, %{}}
    end
  end

  defp put_base_codepoint_override(acc, codepoint, value)
       when is_integer(codepoint) and codepoint >= 0 and codepoint <= 0x10FFFF and
              is_integer(value) and value >= 0 do
    with {:ok, units} <- utf16_units_for_codepoint(codepoint) do
      case units do
        [single] ->
          put_override(acc, single, value)

        [hi, lo] ->
          with {:ok, hi_acc} <- put_override(acc, hi, value) do
            put_override(hi_acc, lo, 0)
          end

        _ ->
          :ambiguous
      end
    end
  end

  defp put_base_codepoint_override(_acc, _codepoint, _value), do: :ambiguous

  defp put_units_override(acc, units, value)
       when is_list(units) and is_integer(value) and value >= 0 do
    Enum.reduce_while(units, {:ok, acc}, fn unit, {:ok, map_acc} ->
      case put_override(map_acc, unit, value) do
        {:ok, next} -> {:cont, {:ok, next}}
        :ambiguous -> {:halt, :ambiguous}
      end
    end)
  end

  defp put_units_override(_acc, _units, _value), do: :ambiguous

  defp put_override(acc, key, value)
       when is_map(acc) and is_integer(key) and key >= 0 and key <= 0xFFFF and
              is_integer(value) and value >= 0 do
    case Map.get(acc, key) do
      nil -> {:ok, Map.put(acc, key, value)}
      ^value -> {:ok, acc}
      _different -> :ambiguous
    end
  end

  defp put_override(_acc, _key, _value), do: :ambiguous

  defp merge_override_maps(left, right) when is_map(left) and is_map(right) do
    Enum.reduce_while(right, {:ok, left}, fn {key, value}, {:ok, acc} ->
      case put_override(acc, key, value) do
        {:ok, merged} -> {:cont, {:ok, merged}}
        :ambiguous -> {:halt, :ambiguous}
      end
    end)
  end

  defp merge_override_maps(_left, _right), do: :ambiguous

  defp normalize_used_cids(used_cids) do
    used_cids
    |> List.wrap()
    |> Enum.filter(&(is_integer(&1) and &1 >= 0 and &1 <= 0xFFFF))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp compact_to_unicode_mappings(mappings) do
    parsed =
      mappings
      |> Enum.map(fn {source_hex, destination_hex} ->
        %{
          source_hex: source_hex,
          destination_hex: destination_hex,
          source_int: String.to_integer(source_hex, 16),
          destination_int: String.to_integer(destination_hex, 16),
          hex_len: byte_size(source_hex)
        }
      end)
      |> Enum.sort_by(fn entry -> {entry.hex_len, entry.source_int, entry.destination_int} end)

    runs = split_mapping_runs(parsed)

    Enum.reduce(runs, {[], []}, fn run, {ranges_acc, chars_acc} ->
      if length(run) >= 2 do
        first = hd(run)
        last = List.last(run)

        {
          ranges_acc ++ [{first.source_hex, last.source_hex, first.destination_hex}],
          chars_acc
        }
      else
        entry = hd(run)
        {ranges_acc, chars_acc ++ [{entry.source_hex, entry.destination_hex}]}
      end
    end)
  end

  defp split_mapping_runs([]), do: []

  defp split_mapping_runs([first | rest]) do
    {run, remaining} = take_mapping_run(rest, first, [first])
    [Enum.reverse(run) | split_mapping_runs(remaining)]
  end

  defp take_mapping_run([], _prev, acc), do: {acc, []}

  defp take_mapping_run([next | rest] = remaining, prev, acc) do
    if next.hex_len == prev.hex_len and next.source_int == prev.source_int + 1 and
         next.destination_int == prev.destination_int + 1 do
      take_mapping_run(rest, next, [next | acc])
    else
      {acc, remaining}
    end
  end

  defp compact_cid_width_pairs([]), do: []

  defp compact_cid_width_pairs([{cid, width} | rest]) do
    {run, remaining} = take_cid_width_run(rest, cid, width, [{cid, width}])

    entry =
      case run do
        [{single_cid, single_width}] ->
          "#{single_cid} [#{single_width}]"

        many ->
          {start_cid, run_width} = hd(many)
          {end_cid, _} = List.last(many)
          "#{start_cid} #{end_cid} #{run_width}"
      end

    [entry | compact_cid_width_pairs(remaining)]
  end

  defp take_cid_width_run([], _prev_cid, _width, acc), do: {Enum.reverse(acc), []}

  defp take_cid_width_run([{cid, width} | rest] = remaining, prev_cid, run_width, acc) do
    if cid == prev_cid + 1 and width == run_width do
      take_cid_width_run(rest, cid, run_width, [{cid, width} | acc])
    else
      {Enum.reverse(acc), remaining}
    end
  end

  defp utf16_code_units(text) when is_binary(text) do
    text
    |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
    |> decode_u16_words([])
    |> Enum.reverse()
  end

  defp utf16_units_for_codepoint(codepoint)
       when is_integer(codepoint) and codepoint >= 0 and codepoint <= 0x10FFFF do
    {:ok, utf16_code_units(<<codepoint::utf8>>)}
  rescue
    _ -> :error
  end

  defp utf16_units_for_codepoint(_codepoint), do: :error

  defp scalar_to_utf16_hex_mappings(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.filter(&(&1 >= 0 and &1 <= 0x10FFFF))
    |> Enum.map(fn codepoint ->
      utf16_hex = codepoint_to_utf16_hex(codepoint)
      {utf16_hex, utf16_hex}
    end)
  end

  defp codepoint_to_utf16_hex(codepoint) when codepoint >= 0 and codepoint <= 0x10FFFF do
    <<codepoint::utf8>>
    |> :unicode.characters_to_binary(:utf8, {:utf16, :big})
    |> Base.encode16(case: :upper)
  end

  defp decode_u16_words(<<>>, acc), do: acc

  defp decode_u16_words(<<word::16-big, rest::binary>>, acc),
    do: decode_u16_words(rest, [word | acc])

  defp embedded_font_object(embedded_font, descriptor_id, used_char_codes) do
    font_name = embedded_pdf_font_name(embedded_font)
    {first_char, last_char} = embedded_font_char_range(embedded_font, used_char_codes)
    widths = embedded_font_widths(embedded_font, first_char, last_char)

    "<< /Type /Font /Subtype /TrueType /BaseFont /#{font_name} /Encoding /WinAnsiEncoding /FirstChar #{first_char} /LastChar #{last_char} /Widths [#{widths}] /FontDescriptor #{descriptor_id} 0 R >>"
  end

  defp embedded_pdf_font_name(embedded_font) do
    base_name = embedded_font |> Map.fetch!(:name) |> Object.sanitize_name()

    case Map.get(embedded_font, :subset, :none) do
      :ascii_basic ->
        "#{subset_prefix(base_name)}+#{base_name}"

      :used_text ->
        "#{subset_prefix(base_name)}+#{base_name}"

      _ ->
        base_name
    end
  end

  defp embedded_font_char_range(embedded_font, used_char_codes) do
    case Map.get(embedded_font, :subset, :none) do
      :ascii_basic -> {32, 126}
      :used_text -> used_text_range(used_char_codes)
      _ -> embedded_font_default_char_range(embedded_font)
    end
  end

  defp embedded_font_default_char_range(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_first_char_index: first_char, os2_last_char_index: last_char}
      when is_integer(first_char) and is_integer(last_char) and first_char >= 0 and
             last_char >= first_char and last_char <= 255 and
             not (first_char == 0 and last_char == 0) ->
        {first_char, last_char}

      _ ->
        {32, 255}
    end
  end

  defp used_text_range([]), do: {32, 255}

  defp used_text_range(used_char_codes) do
    {Enum.min(used_char_codes), Enum.max(used_char_codes)}
  end

  defp subset_prefix(seed) do
    value = :erlang.phash2(seed, 308_915_776)
    encode_base26(value, 6, "")
  end

  defp encode_base26(_value, 0, acc), do: acc

  defp encode_base26(value, remaining, acc) do
    digit = rem(value, 26)
    encode_base26(div(value, 26), remaining - 1, <<?A + digit>> <> acc)
  end

  defp embedded_font_bbox(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{font_bbox: {x_min, y_min, x_max, y_max}, units_per_em: units_per_em}
      when is_integer(units_per_em) and units_per_em > 0 ->
        {
          scale_font_unit(x_min, units_per_em),
          scale_font_unit(y_min, units_per_em),
          scale_font_unit(x_max, units_per_em),
          scale_font_unit(y_max, units_per_em)
        }

      %{head_bbox: {x_min, y_min, x_max, y_max}, units_per_em: units_per_em}
      when is_integer(units_per_em) and units_per_em > 0 ->
        {
          scale_font_unit(x_min, units_per_em),
          scale_font_unit(y_min, units_per_em),
          scale_font_unit(x_max, units_per_em),
          scale_font_unit(y_max, units_per_em)
        }

      _ ->
        {0, -200, 1000, 900}
    end
  end

  defp embedded_font_vertical_metrics(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{units_per_em: units_per_em} = ttf_metrics
      when is_integer(units_per_em) and units_per_em > 0 ->
        ascent_source =
          nonzero_metric(Map.get(ttf_metrics, :typo_ascender)) ||
            nonzero_metric(Map.get(ttf_metrics, :hhea_ascender)) ||
            nonzero_metric(Map.get(ttf_metrics, :os2_win_ascent))

        descent_source =
          nonzero_metric(Map.get(ttf_metrics, :typo_descender)) ||
            nonzero_metric(Map.get(ttf_metrics, :hhea_descender)) ||
            case nonzero_metric(Map.get(ttf_metrics, :os2_win_descent)) do
              nil -> nil
              win_descent -> -abs(win_descent)
            end

        leading_source =
          nonzero_metric(Map.get(ttf_metrics, :typo_line_gap)) ||
            nonzero_metric(Map.get(ttf_metrics, :hhea_line_gap))

        x_height_source = Map.get(ttf_metrics, :x_height)
        cap_source = Map.get(ttf_metrics, :cap_height) || ascent_source

        {
          metric_or_default(ascent_source, 800, units_per_em),
          metric_or_default(descent_source, -200, units_per_em),
          metric_or_default(leading_source, 0, units_per_em),
          metric_or_default(x_height_source, 500, units_per_em),
          metric_or_default(cap_source, 700, units_per_em)
        }

      _ ->
        {800, -200, 0, 500, 700}
    end
  end

  defp nonzero_metric(value) when is_integer(value) and value != 0, do: value
  defp nonzero_metric(_value), do: nil

  defp embedded_font_descriptor_style_metrics(embedded_font) do
    ttf_metrics =
      case Map.get(embedded_font, :ttf_metrics) do
        metrics when is_map(metrics) -> metrics
        _ -> %{}
      end

    italic_angle =
      case Map.get(ttf_metrics, :italic_angle) do
        value when is_number(value) -> value * 1.0
        _ -> 0.0
      end

    italic? =
      case Map.get(ttf_metrics, :italic) do
        value when is_boolean(value) -> value or abs(italic_angle) > 0.0001
        _ -> abs(italic_angle) > 0.0001
      end

    fixed_pitch? = Map.get(ttf_metrics, :fixed_pitch) == true

    force_bold? =
      Map.get(ttf_metrics, :bold) == true or
        Map.get(ttf_metrics, :cff_force_bold) == true or
        case Map.get(ttf_metrics, :os2_weight_class) do
          weight when is_integer(weight) and weight >= 700 -> true
          _ -> false
        end

    flags =
      32 + if(italic?, do: 64, else: 0) + if(fixed_pitch?, do: 1, else: 0) +
        if(force_bold?, do: 262_144, else: 0)

    {flags, italic_angle}
  end

  defp embedded_font_stem_v(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_weight_class: weight_class} when is_integer(weight_class) and weight_class > 0 ->
        max(1, round(weight_class / 5))

      %{cff_stem_v: stem_v} when is_integer(stem_v) and stem_v > 0 ->
        stem_v

      %{cff_stem_h: stem_h} when is_integer(stem_h) and stem_h > 0 ->
        stem_h

      %{cff_weight_class: weight_class} when is_integer(weight_class) and weight_class > 0 ->
        max(1, round(weight_class / 5))

      _ ->
        80
    end
  end

  defp embedded_font_stem_h(embedded_font, stem_v)
       when is_integer(stem_v) and stem_v > 0 do
    case Map.get(embedded_font, :ttf_metrics) do
      %{cff_stem_h: stem_h} when is_integer(stem_h) and stem_h > 0 ->
        stem_h

      _ ->
        stem_v
    end
  end

  defp embedded_font_stem_h(_embedded_font, _stem_v), do: 80

  defp embedded_font_stretch_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_width_class: width_class} when is_integer(width_class) ->
        case font_stretch_name(width_class) do
          nil -> ""
          stretch_name -> " /FontStretch /#{stretch_name}"
        end

      _ ->
        ""
    end
  end

  defp embedded_font_family_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{font_family: family} when is_binary(family) and family != "" ->
        " /FontFamily " <> Object.format_text(family)

      _ ->
        ""
    end
  end

  defp embedded_font_weight_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_weight_class: weight_class}
      when is_integer(weight_class) and weight_class >= 1 and weight_class <= 1000 ->
        " /FontWeight #{weight_class}"

      %{cff_weight_class: weight_class}
      when is_integer(weight_class) and weight_class >= 1 and weight_class <= 1000 ->
        " /FontWeight #{weight_class}"

      _ ->
        ""
    end
  end

  defp embedded_font_avg_width_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_avg_char_width: avg_char_width, units_per_em: units_per_em}
      when is_integer(avg_char_width) and is_integer(units_per_em) and units_per_em > 0 ->
        " /AvgWidth #{scale_font_unit(avg_char_width, units_per_em)}"

      _ ->
        ""
    end
  end

  defp embedded_font_max_width_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{hhea_advance_width_max: hhea_max_width, units_per_em: units_per_em}
      when is_integer(hhea_max_width) and hhea_max_width > 0 and is_integer(units_per_em) and
             units_per_em > 0 ->
        " /MaxWidth #{scale_font_unit(hhea_max_width, units_per_em)}"

      %{max_advance_width: max_advance_width, units_per_em: units_per_em}
      when is_integer(max_advance_width) and max_advance_width >= 0 and is_integer(units_per_em) and
             units_per_em > 0 ->
        " /MaxWidth #{scale_font_unit(max_advance_width, units_per_em)}"

      %{advance_widths: advance_widths, units_per_em: units_per_em}
      when is_list(advance_widths) and advance_widths != [] and is_integer(units_per_em) and
             units_per_em > 0 ->
        " /MaxWidth #{scale_font_unit(Enum.max(advance_widths), units_per_em)}"

      _ ->
        ""
    end
  end

  defp embedded_font_missing_width_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{advance_widths: advance_widths, units_per_em: units_per_em} = ttf_metrics
      when is_list(advance_widths) and advance_widths != [] and is_integer(units_per_em) and
             units_per_em > 0 ->
        default_glyph_id = missing_width_glyph_id(ttf_metrics)
        " /MissingWidth #{width_for_glyph_id(advance_widths, default_glyph_id, units_per_em)}"

      _ ->
        ""
    end
  end

  defp missing_width_glyph_id(ttf_metrics) when is_map(ttf_metrics) do
    cmap_by_code = Map.get(ttf_metrics, :cmap_by_code, %{})

    default_char_candidates =
      [Map.get(ttf_metrics, :os2_default_char), Map.get(ttf_metrics, :os2_break_char)]
      |> Enum.filter(fn value -> is_integer(value) and value >= 0 end)

    if is_map(cmap_by_code) do
      case Enum.find_value(default_char_candidates, fn codepoint ->
             case Map.get(cmap_by_code, codepoint) do
               glyph_id when is_integer(glyph_id) and glyph_id >= 0 -> glyph_id
               _ -> nil
             end
           end) do
        nil -> 0
        glyph_id -> glyph_id
      end
    else
      0
    end
  end

  defp embedded_font_fs_type_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_fs_type: fs_type} when is_integer(fs_type) and fs_type >= 0 ->
        " /FSType #{fs_type}"

      _ ->
        ""
    end
  end

  defp embedded_font_style_ref(embedded_font) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{os2_panose: panose} when is_binary(panose) and byte_size(panose) == 10 ->
        panose_hex = Base.encode16(panose, case: :upper)
        " /Style << /Panose <#{panose_hex}> >>"

      _ ->
        ""
    end
  end

  defp font_stretch_name(1), do: "UltraCondensed"
  defp font_stretch_name(2), do: "ExtraCondensed"
  defp font_stretch_name(3), do: "Condensed"
  defp font_stretch_name(4), do: "SemiCondensed"
  defp font_stretch_name(5), do: "Normal"
  defp font_stretch_name(6), do: "SemiExpanded"
  defp font_stretch_name(7), do: "Expanded"
  defp font_stretch_name(8), do: "ExtraExpanded"
  defp font_stretch_name(9), do: "UltraExpanded"
  defp font_stretch_name(_other), do: nil

  defp embedded_font_widths(embedded_font, first_char, last_char) do
    case Map.get(embedded_font, :ttf_metrics) do
      %{advance_widths: advance_widths, units_per_em: units_per_em} = ttf_metrics
      when is_list(advance_widths) and is_integer(units_per_em) and units_per_em > 0 ->
        cmap_by_code = Map.get(ttf_metrics, :cmap_by_code, %{})

        first_char..last_char
        |> Enum.map_join(" ", fn char_code ->
          glyph_id = glyph_id_for_char_code(char_code, cmap_by_code)
          width = width_for_glyph_id(advance_widths, glyph_id, units_per_em)
          Integer.to_string(width)
        end)

      _ ->
        default_embedded_widths(first_char, last_char)
    end
  end

  defp glyph_id_for_char_code(char_code, cmap_by_code) when is_map(cmap_by_code) do
    case Map.get(cmap_by_code, char_code, char_code) do
      glyph_id when is_integer(glyph_id) and glyph_id >= 0 -> glyph_id
      _ -> 0
    end
  end

  defp width_for_glyph_id(advance_widths, glyph_id, units_per_em)
       when is_list(advance_widths) and is_integer(glyph_id) and glyph_id >= 0 do
    case Enum.fetch(advance_widths, glyph_id) do
      {:ok, raw_width} when is_integer(raw_width) and raw_width >= 0 ->
        max(0, round(raw_width * 1000 / units_per_em))

      _ ->
        600
    end
  end

  defp default_embedded_widths(first_char, last_char) do
    Enum.map_join(first_char..last_char, " ", fn _ -> "600" end)
  end

  defp metric_or_default(value, _default, units_per_em) when is_integer(value) do
    scale_font_unit(value, units_per_em)
  end

  defp metric_or_default(_value, default, _units_per_em), do: default

  defp scale_font_unit(value, units_per_em) when is_integer(value) and is_integer(units_per_em) do
    round(value * 1000 / units_per_em)
  end

  defp cff_charstrings_tail_droppable?(top_dict, charstrings_end, cff_size)
       when is_binary(top_dict) and is_integer(charstrings_end) and is_integer(cff_size) and
              charstrings_end >= 0 and cff_size >= 0 do
    if charstrings_end >= cff_size do
      true
    else
      case cff_has_offset_ref_at_or_after?(top_dict, charstrings_end, cff_size) do
        {:ok, true} -> false
        {:ok, false} -> true
        :error -> false
      end
    end
  end

  defp cff_charstrings_tail_droppable?(_top_dict, _charstrings_end, _cff_size), do: false

  defp parse_cff_index(index_data) when is_binary(index_data) do
    case parse_cff_index_with_offsets(index_data) do
      {:ok, %{objects: objects, rest: rest, size: size}} -> {:ok, {objects, rest, size}}
      _ -> :error
    end
  end

  defp parse_cff_index(_invalid), do: :error

  # Delegates to Tincture.Font.CFF, which owns the INDEX container format and
  # is shared with the metadata reader in Tincture.Font.TTF. The offsets and
  # byte sizes CFF returns are what the top-DICT patching below needs.
  defp parse_cff_dict_number(data), do: CFF.parse_dict_number(data)

  defp use_type0_embedded_font?(embedded_font, unicode_text?) do
    Map.fetch!(embedded_font, :format) in [:ttf, :otf] and unicode_text?
  end

  defp cff_has_offset_ref_at_or_after?(top_dict, tail_start, cff_size)
       when is_binary(top_dict) and is_integer(tail_start) and is_integer(cff_size) do
    scan_cff_offset_refs(top_dict, [], tail_start, cff_size, false)
  end

  defp cff_has_offset_ref_at_or_after?(_top_dict, _tail_start, _cff_size), do: :error

  defp scan_cff_offset_refs(<<>>, _operands, _tail_start, _cff_size, referenced?),
    do: {:ok, referenced?}

  defp scan_cff_offset_refs(
         <<12, escaped_op::8, rest::binary>>,
         operands,
         tail_start,
         cff_size,
         referenced?
       ) do
    ordered = Enum.reverse(operands)

    escaped_referenced? =
      case escaped_op do
        36 -> single_offset_operand_references_tail?(ordered, tail_start, cff_size)
        37 -> single_offset_operand_references_tail?(ordered, tail_start, cff_size)
        _ -> false
      end

    scan_cff_offset_refs(rest, [], tail_start, cff_size, referenced? or escaped_referenced?)
  end

  defp scan_cff_offset_refs(
         <<op::8, rest::binary>>,
         operands,
         tail_start,
         cff_size,
         referenced?
       )
       when op <= 21 do
    ordered = Enum.reverse(operands)

    op_referenced? =
      case op do
        15 -> single_offset_operand_references_tail?(ordered, tail_start, cff_size)
        16 -> single_offset_operand_references_tail?(ordered, tail_start, cff_size)
        17 -> single_offset_operand_references_tail?(ordered, tail_start, cff_size)
        18 -> private_offset_operand_references_tail?(ordered, tail_start, cff_size)
        _ -> false
      end

    scan_cff_offset_refs(rest, [], tail_start, cff_size, referenced? or op_referenced?)
  end

  defp scan_cff_offset_refs(dict_data, operands, tail_start, cff_size, referenced?) do
    case parse_cff_dict_number(dict_data) do
      {:ok, number, rest} ->
        scan_cff_offset_refs(rest, [number | operands], tail_start, cff_size, referenced?)

      :error ->
        :error
    end
  end

  defp single_offset_operand_references_tail?([offset | _rest], tail_start, cff_size)
       when is_integer(offset) and is_integer(tail_start) and is_integer(cff_size) do
    offset >= tail_start and offset < cff_size
  end

  defp single_offset_operand_references_tail?(_operands, _tail_start, _cff_size), do: false

  defp private_offset_operand_references_tail?(
         [_private_size, private_offset | _rest],
         tail_start,
         cff_size
       )
       when is_integer(private_offset) and is_integer(tail_start) and is_integer(cff_size) do
    private_offset >= tail_start and private_offset < cff_size
  end

  defp private_offset_operand_references_tail?(_operands, _tail_start, _cff_size), do: false
end
