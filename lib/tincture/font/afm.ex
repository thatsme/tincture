defmodule Tincture.Font.AFM do
  @moduledoc false

  @type t :: %__MODULE__{
          font_name: String.t() | nil,
          widths_by_code: %{optional(integer()) => number()},
          glyph_by_code: %{optional(integer()) => String.t()},
          kerning: %{optional({String.t(), String.t()}) => number()}
        }

  defstruct font_name: nil,
            widths_by_code: %{},
            glyph_by_code: %{},
            kerning: %{}

  @spec parse_file(Path.t()) :: t()
  def parse_file(path) when is_binary(path) do
    path
    |> File.read!()
    |> parse_string()
  end

  @spec parse_string(String.t()) :: t()
  def parse_string(contents) when is_binary(contents) do
    {_mode, afm} =
      contents
      |> String.split(~r/\R/, trim: true)
      |> Enum.reduce({:none, %__MODULE__{}}, &parse_line/2)

    afm
  end

  @spec width_for_code(t(), integer()) :: number()
  def width_for_code(%__MODULE__{} = afm, code) when is_integer(code) do
    Map.get(afm.widths_by_code, code, 0)
  end

  @spec glyph_name_for_code(t(), integer()) :: String.t() | nil
  def glyph_name_for_code(%__MODULE__{} = afm, code) when is_integer(code) do
    Map.get(afm.glyph_by_code, code)
  end

  @spec kerning_adjust(t(), String.t() | nil, String.t() | nil) :: number()
  def kerning_adjust(%__MODULE__{}, nil, _right), do: 0
  def kerning_adjust(%__MODULE__{}, _left, nil), do: 0

  def kerning_adjust(%__MODULE__{} = afm, left, right)
      when is_binary(left) and is_binary(right) do
    Map.get(afm.kerning, {left, right}, 0)
  end

  defp parse_line("FontName " <> font_name, {mode, afm}) do
    {mode, %__MODULE__{afm | font_name: String.trim(font_name)}}
  end

  defp parse_line("StartCharMetrics" <> _rest, {_mode, afm}), do: {:char_metrics, afm}
  defp parse_line("EndCharMetrics", {_mode, afm}), do: {:none, afm}
  defp parse_line("StartKernPairs" <> _rest, {_mode, afm}), do: {:kern_pairs, afm}
  defp parse_line("EndKernPairs", {_mode, afm}), do: {:none, afm}

  defp parse_line(line, {:char_metrics, afm}) do
    case parse_char_metric_line(line) do
      {code, width, glyph_name} ->
        afm =
          afm
          |> put_width(code, width)
          |> put_glyph(code, glyph_name)

        {:char_metrics, afm}

      :skip ->
        {:char_metrics, afm}
    end
  end

  defp parse_line("KPX " <> rest, {:kern_pairs, afm}) do
    case String.split(rest, ~r/\s+/, trim: true) do
      [left, right, value] ->
        case parse_number(value) do
          {:ok, amount} ->
            {:kern_pairs, %__MODULE__{afm | kerning: Map.put(afm.kerning, {left, right}, amount)}}

          :error ->
            {:kern_pairs, afm}
        end

      _ ->
        {:kern_pairs, afm}
    end
  end

  defp parse_line(_line, {mode, afm}), do: {mode, afm}

  defp parse_char_metric_line(line) do
    fields =
      line
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    code = find_prefixed(fields, "C ")
    width = find_prefixed(fields, "WX ")
    glyph_name = find_prefixed(fields, "N ")

    with {:ok, c} <- parse_integer(code),
         true <- c >= 0,
         {:ok, w} <- parse_number(width),
         true <- is_binary(glyph_name) and glyph_name != "" do
      {c, w, glyph_name}
    else
      _ -> :skip
    end
  end

  defp find_prefixed(fields, prefix) do
    fields
    |> Enum.find_value(fn field ->
      if String.starts_with?(field, prefix) do
        String.trim_leading(field, prefix)
      end
    end)
  end

  defp parse_integer(nil), do: :error

  defp parse_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parse_number(nil), do: :error

  defp parse_number(value) do
    case Integer.parse(value) do
      {number, ""} ->
        {:ok, number}

      _ ->
        case Float.parse(value) do
          {number, ""} -> {:ok, number}
          _ -> :error
        end
    end
  end

  defp put_width(afm, code, width) do
    %__MODULE__{afm | widths_by_code: Map.put(afm.widths_by_code, code, width)}
  end

  defp put_glyph(afm, code, glyph_name) do
    %__MODULE__{afm | glyph_by_code: Map.put(afm.glyph_by_code, code, glyph_name)}
  end
end
