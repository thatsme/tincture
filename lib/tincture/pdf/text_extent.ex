defmodule Tincture.PDF.TextExtent do
  @moduledoc false

  # An estimate of the rectangle a line of text occupies, for the places that
  # need one: a text link's clickable area, and a tagged figure's bounding box.
  #
  # PDF has no notion of a text bounding box at draw time, and ascender and
  # descender metrics are not available for every registered font, so the
  # vertical extent is taken from the font size: three quarters above the
  # baseline, a quarter below. The width is the font's metric width.

  alias Tincture.Font.Context
  alias Tincture.PDF

  @doc """
  `{width, ascent, descent}` of `text` set in `font_name` at `size`.
  """
  @spec extent(PDF.t(), String.t(), number(), String.t()) :: {number(), number(), number()}
  def extent(%PDF{} = pdf, font_name, size, text) do
    width =
      pdf
      |> Context.from_pdf()
      |> Context.text_width(font_name, size, text, on_unknown: :estimate)

    {width, size * 0.75, size * 0.25}
  end

  @doc """
  The corners of that extent for text whose baseline starts at `{x, y}`,
  rotated by `angle_degrees` about that point, as `text_at_rotated/5` draws it.
  """
  @spec corners({number(), number(), number()}, number(), number(), number()) ::
          [{number(), number()}]
  def corners({width, ascent, descent}, x, y, angle_degrees) when angle_degrees == 0,
    do: [{x, y - descent}, {x + width, y + ascent}]

  def corners({width, ascent, descent}, x, y, angle_degrees) do
    radians = angle_degrees * :math.pi() / 180
    {cos_a, sin_a} = {snap(:math.cos(radians)), snap(:math.sin(radians))}

    for u <- [0, width], v <- [-descent, ascent] do
      {x + u * cos_a - v * sin_a, y + u * sin_a + v * cos_a}
    end
  end

  # As the serialiser's rotation matrix does: cos(90°) is 6.1e-17, not 0.
  defp snap(value) when abs(value) < 1.0e-12, do: 0.0
  defp snap(value), do: value
end
