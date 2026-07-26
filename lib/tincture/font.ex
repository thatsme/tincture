defmodule Tincture.Font do
  @moduledoc false

  alias Tincture.Font.AFM
  alias Tincture.Font.Metrics
  alias Tincture.Font.Standard
  alias Tincture.Unicode

  @spec registered_fonts() :: [String.t()]
  def registered_fonts do
    Metrics.registered_fonts()
  end

  @spec afm(String.t()) :: {:ok, AFM.t()} | :error
  def afm(font_name) when is_binary(font_name) do
    Metrics.fetch_afm(font_name)
  end

  @spec standard_font?(String.t()) :: boolean()
  def standard_font?(font_name) when is_binary(font_name) do
    Standard.standard_font?(font_name)
  end

  @spec font_available?(String.t()) :: boolean()
  def font_available?(font_name) when is_binary(font_name) do
    standard_font?(font_name) or match?({:ok, _}, afm(font_name))
  end

  @spec text_width(String.t(), number(), String.t()) :: float()
  def text_width(font_name, size, text)
      when is_binary(font_name) and is_number(size) and size > 0 and is_binary(text) do
    total_units =
      cond do
        standard_font?(font_name) ->
          text_width_standard(font_name, text)

        true ->
          text_width_afm(font_name, text)
      end

    total_units * size / 1000
  end

  defp text_width_afm(font_name, text) do
    afm_metrics =
      case afm(font_name) do
        {:ok, parsed_afm} -> parsed_afm
        :error -> raise ArgumentError, "unknown font: #{font_name}"
      end

    {total_units, _prev_glyph} =
      text
      |> String.to_charlist()
      |> Enum.reduce({0, nil}, fn codepoint, {acc, prev_glyph} ->
        if skip_unmapped_zero_advance_codepoint?(codepoint) do
          {acc, prev_glyph}
        else
          code = if codepoint >= 0 and codepoint <= 255, do: codepoint, else: -1
          width = AFM.width_for_code(afm_metrics, code)
          glyph = AFM.glyph_name_for_code(afm_metrics, code)
          kern = AFM.kerning_adjust(afm_metrics, prev_glyph, glyph)
          {acc + width + kern, glyph}
        end
      end)

    total_units
  end

  defp text_width_standard(font_name, text) do
    metrics =
      case Standard.fetch_metrics(font_name) do
        {:ok, parsed_metrics} -> parsed_metrics
        :error -> raise ArgumentError, "unknown font: #{font_name}"
      end

    {total_units, _prev_code} =
      text
      |> String.to_charlist()
      |> Enum.reduce({0, nil}, fn codepoint, {acc, prev_code} ->
        if skip_unmapped_zero_advance_codepoint?(codepoint) do
          {acc, prev_code}
        else
          code = if codepoint >= 0 and codepoint <= 255, do: codepoint, else: -1
          width = Map.get(metrics.widths_by_code, code, 0)

          kern =
            case prev_code do
              nil -> 0
              left -> Map.get(metrics.kern_by_code, {left, code}, 0)
            end

          {acc + width + kern, code}
        end
      end)

    total_units
  end

  defp skip_unmapped_zero_advance_codepoint?(codepoint)
       when is_integer(codepoint) and codepoint > 255 do
    Unicode.zero_advance_codepoint?(codepoint)
  end

  defp skip_unmapped_zero_advance_codepoint?(_codepoint), do: false
end
