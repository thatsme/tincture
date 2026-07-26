defmodule Tincture.PDF.Image do
  @moduledoc false

  import Bitwise

  @sof_markers [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
  @standalone_markers [0x01, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7]
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @spec load_jpeg!(Path.t()) :: map()
  def load_jpeg!(path) when is_binary(path) and byte_size(path) > 0 do
    data = read_file!(path, "JPEG")

    case parse_jpeg_metadata(data) do
      {:ok, metadata} ->
        Map.merge(metadata, %{format: :jpeg, data: data})

      {:error, :invalid_jpeg} ->
        raise ArgumentError, "invalid JPEG file: #{path}"
    end
  end

  @spec load_png!(Path.t()) :: map()
  def load_png!(path) when is_binary(path) and byte_size(path) > 0 do
    data = read_file!(path, "PNG")

    case parse_png(data) do
      {:ok, image} ->
        image

      {:error, :invalid_png} ->
        raise ArgumentError, "invalid PNG file: #{path}"
    end
  end

  defp read_file!(path, type_name) do
    case File.read(path) do
      {:ok, data} ->
        data

      {:error, _reason} ->
        raise ArgumentError, "unable to read #{type_name} file: #{path}"
    end
  end

  defp parse_png(<<@png_signature, rest::binary>>) do
    with {:ok, ihdr, idat_chunks} <- parse_png_chunks(rest, nil, []) do
      build_png_image(ihdr, idat_chunks)
    end
  end

  defp parse_png(_), do: {:error, :invalid_png}

  defp parse_png_chunks(<<length::32-big, type::binary-size(4), chunk_tail::binary>>, ihdr, idats)
       when byte_size(chunk_tail) >= length + 4 do
    <<data::binary-size(length), _crc::32-big, rest::binary>> = chunk_tail

    case type do
      "IHDR" ->
        case parse_png_ihdr(data) do
          {:ok, parsed} -> parse_png_chunks(rest, parsed, idats)
          {:error, :invalid_png} -> {:error, :invalid_png}
        end

      "IDAT" ->
        parse_png_chunks(rest, ihdr, [data | idats])

      "IEND" ->
        finalize_png_chunks(ihdr, idats)

      _ ->
        parse_png_chunks(rest, ihdr, idats)
    end
  end

  defp parse_png_chunks(_, _, _), do: {:error, :invalid_png}

  defp finalize_png_chunks(nil, _), do: {:error, :invalid_png}
  defp finalize_png_chunks(_ihdr, []), do: {:error, :invalid_png}

  defp finalize_png_chunks(ihdr, idats) do
    {:ok, ihdr, Enum.reverse(idats)}
  end

  defp parse_png_ihdr(
         <<width::32-big, height::32-big, bit_depth, color_type, compression, filter, interlace>>
       )
       when width > 0 and height > 0 and compression == 0 and filter == 0 and interlace == 0 do
    {:ok, %{width: width, height: height, bit_depth: bit_depth, color_type: color_type}}
  end

  defp parse_png_ihdr(_), do: {:error, :invalid_png}

  defp build_png_image(ihdr, idat_chunks) do
    with {:ok, channels, color_space, has_alpha} <- png_color_type_info(ihdr.color_type),
         true <- ihdr.bit_depth == 8,
         compressed <- IO.iodata_to_binary(idat_chunks),
         {:ok, rows} <- decode_png_rows(compressed, ihdr.width, ihdr.height, channels) do
      {:ok, assemble_png_image(rows, ihdr.width, ihdr.height, color_space, channels, has_alpha)}
    else
      false -> {:error, :invalid_png}
      {:error, _reason} -> {:error, :invalid_png}
    end
  end

  defp png_color_type_info(0), do: {:ok, 1, :device_gray, false}
  defp png_color_type_info(2), do: {:ok, 3, :device_rgb, false}
  defp png_color_type_info(4), do: {:ok, 2, :device_gray, true}
  defp png_color_type_info(6), do: {:ok, 4, :device_rgb, true}
  defp png_color_type_info(_), do: {:error, :invalid_png}

  defp decode_png_rows(compressed, width, height, channels) do
    case :zlib.uncompress(compressed) do
      raw ->
        row_bytes = width * channels
        expected = height * (row_bytes + 1)

        if byte_size(raw) == expected do
          parse_png_rows(raw, height, row_bytes, channels, <<0::size(row_bytes)-unit(8)>>, [])
        else
          {:error, :invalid_png}
        end
    end
  rescue
    _ -> {:error, :invalid_png}
  end

  defp parse_png_rows(<<>>, 0, _row_bytes, _bpp, _prev_row, rows) do
    {:ok, Enum.reverse(rows)}
  end

  defp parse_png_rows(<<filter, rest::binary>>, rows_left, row_bytes, bpp, prev_row, rows)
       when rows_left > 0 do
    if byte_size(rest) >= row_bytes do
      <<row::binary-size(row_bytes), tail::binary>> = rest

      case unfilter_png_row(filter, row, prev_row, bpp) do
        {:ok, unfiltered} ->
          parse_png_rows(tail, rows_left - 1, row_bytes, bpp, unfiltered, [unfiltered | rows])

        {:error, :invalid_png} ->
          {:error, :invalid_png}
      end
    else
      {:error, :invalid_png}
    end
  end

  defp parse_png_rows(_, _, _, _, _, _), do: {:error, :invalid_png}

  defp unfilter_png_row(0, row, _prev, _bpp), do: {:ok, row}

  defp unfilter_png_row(filter, row, prev, bpp) when filter in [1, 2, 3, 4] do
    raw = :binary.bin_to_list(row)
    prev_bytes = :binary.bin_to_list(prev)

    {decoded_reversed, _, _} =
      Enum.zip(raw, prev_bytes)
      |> Enum.reduce({[], [], []}, fn {raw_byte, up_byte}, {acc, left_window, up_window} ->
        left = window_head(left_window, bpp)
        up_left = window_head(up_window, bpp)

        value =
          case filter do
            1 -> raw_byte + left
            2 -> raw_byte + up_byte
            3 -> raw_byte + div(left + up_byte, 2)
            4 -> raw_byte + paeth_predictor(left, up_byte, up_left)
          end
          |> band(255)

        next_left_window = push_window(left_window, bpp, value)
        next_up_window = push_window(up_window, bpp, up_byte)
        {[value | acc], next_left_window, next_up_window}
      end)

    {:ok, decoded_reversed |> Enum.reverse() |> :erlang.list_to_binary()}
  end

  defp unfilter_png_row(_, _row, _prev, _bpp), do: {:error, :invalid_png}

  defp push_window(window, max, value) when length(window) < max, do: window ++ [value]

  defp push_window([_oldest | rest], _max, value), do: rest ++ [value]

  defp window_head(window, max) when length(window) < max, do: 0
  defp window_head([head | _], _max), do: head

  defp paeth_predictor(a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp assemble_png_image(rows, width, height, color_space, channels, false) do
    %{
      format: :png,
      data: rows_to_png_flate(rows),
      width: width,
      height: height,
      bits_per_component: 8,
      color_space: color_space,
      decode_parms: decode_parms(width, channels)
    }
  end

  defp assemble_png_image(rows, width, height, :device_rgb, 4, true) do
    {rgb_rows, alpha_rows} = split_rgba_rows(rows)

    %{
      format: :png,
      data: rows_to_png_flate(rgb_rows),
      width: width,
      height: height,
      bits_per_component: 8,
      color_space: :device_rgb,
      decode_parms: decode_parms(width, 3),
      alpha_data: rows_to_png_flate(alpha_rows),
      alpha_decode_parms: decode_parms(width, 1)
    }
  end

  defp assemble_png_image(rows, width, height, :device_gray, 2, true) do
    {gray_rows, alpha_rows} = split_gray_alpha_rows(rows)

    %{
      format: :png,
      data: rows_to_png_flate(gray_rows),
      width: width,
      height: height,
      bits_per_component: 8,
      color_space: :device_gray,
      decode_parms: decode_parms(width, 1),
      alpha_data: rows_to_png_flate(alpha_rows),
      alpha_decode_parms: decode_parms(width, 1)
    }
  end

  defp rows_to_png_flate(rows) do
    rows
    |> Enum.map(fn row -> [<<0>>, row] end)
    |> IO.iodata_to_binary()
    |> :zlib.compress()
  end

  defp decode_parms(columns, colors) do
    %{predictor: 15, colors: colors, bits_per_component: 8, columns: columns}
  end

  defp split_rgba_rows(rows) do
    rows
    |> Enum.map(&split_rgba_row/1)
    |> Enum.unzip()
  end

  defp split_rgba_row(row), do: split_rgba_row(row, [], [])

  defp split_rgba_row(<<>>, rgb, alpha) do
    {IO.iodata_to_binary(Enum.reverse(rgb)), IO.iodata_to_binary(Enum.reverse(alpha))}
  end

  defp split_rgba_row(<<r, g, b, a, rest::binary>>, rgb, alpha) do
    split_rgba_row(rest, [<<r, g, b>> | rgb], [<<a>> | alpha])
  end

  defp split_gray_alpha_rows(rows) do
    rows
    |> Enum.map(&split_gray_alpha_row/1)
    |> Enum.unzip()
  end

  defp split_gray_alpha_row(row), do: split_gray_alpha_row(row, [], [])

  defp split_gray_alpha_row(<<>>, gray, alpha) do
    {IO.iodata_to_binary(Enum.reverse(gray)), IO.iodata_to_binary(Enum.reverse(alpha))}
  end

  defp split_gray_alpha_row(<<gray, alpha, rest::binary>>, gray_acc, alpha_acc) do
    split_gray_alpha_row(rest, [<<gray>> | gray_acc], [<<alpha>> | alpha_acc])
  end

  defp parse_jpeg_metadata(<<0xFF, 0xD8, rest::binary>>) do
    parse_segments(rest)
  end

  defp parse_jpeg_metadata(_), do: {:error, :invalid_jpeg}

  defp parse_segments(<<>>), do: {:error, :invalid_jpeg}

  defp parse_segments(<<0xFF, marker, rest::binary>>) when marker in @standalone_markers do
    parse_segments(rest)
  end

  defp parse_segments(<<0xFF, marker, rest::binary>>) do
    cond do
      marker == 0xD9 ->
        {:error, :invalid_jpeg}

      marker == 0xDA ->
        {:error, :invalid_jpeg}

      true ->
        case read_segment(rest) do
          {:ok, segment, _tail} when marker in @sof_markers ->
            decode_sof_segment(segment)

          {:ok, _segment, tail} ->
            parse_segments(tail)

          {:error, :invalid_segment} ->
            {:error, :invalid_jpeg}
        end
    end
  end

  defp parse_segments(<<_byte, rest::binary>>) do
    parse_segments(rest)
  end

  defp read_segment(<<length::16-big, payload_and_tail::binary>>) when length >= 2 do
    payload_len = length - 2

    if byte_size(payload_and_tail) >= payload_len do
      <<payload::binary-size(payload_len), tail::binary>> = payload_and_tail
      {:ok, payload, tail}
    else
      {:error, :invalid_segment}
    end
  end

  defp read_segment(_), do: {:error, :invalid_segment}

  defp decode_sof_segment(<<precision, height::16-big, width::16-big, components, _rest::binary>>)
       when width > 0 and height > 0 and precision > 0 do
    with {:ok, color_space} <- color_space(components) do
      {:ok,
       %{
         width: width,
         height: height,
         bits_per_component: precision,
         color_space: color_space
       }}
    end
  end

  defp decode_sof_segment(_), do: {:error, :invalid_jpeg}

  defp color_space(1), do: {:ok, :device_gray}
  defp color_space(3), do: {:ok, :device_rgb}
  defp color_space(4), do: {:ok, :device_cmyk}
  defp color_space(_), do: {:error, :invalid_jpeg}
end
