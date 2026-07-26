defmodule Tincture.PDF.Ops do
  @moduledoc false

  alias Tincture.Font
  alias Tincture.PDF
  alias Tincture.PDF.Image

  @spec set_font(PDF.t(), String.t(), number()) :: PDF.t()
  def set_font(%PDF{} = pdf, font_name, size)
      when is_binary(font_name) and byte_size(font_name) > 0 and is_number(size) and size > 0 do
    if Font.font_available?(font_name) or Map.has_key?(pdf.embedded_fonts, font_name) do
      %PDF{pdf | current_font: {font_name, size}}
    else
      raise ArgumentError, "unknown font: #{font_name}"
    end
  end

  @spec text_at(PDF.t(), number(), number(), String.t()) :: PDF.t()
  def text_at(%PDF{} = pdf, x, y, text)
      when is_number(x) and is_number(y) and is_binary(text) do
    op = {:text_at, x, y, text, pdf.current_font}
    PDF.append_current_op(pdf, op)
  end

  @spec text_at_rotated(PDF.t(), number(), number(), number(), String.t()) :: PDF.t()
  def text_at_rotated(%PDF{} = pdf, x, y, angle_degrees, text)
      when is_number(x) and is_number(y) and is_number(angle_degrees) and is_binary(text) do
    op = {:text_at_rotated, x, y, angle_degrees, text, pdf.current_font}
    PDF.append_current_op(pdf, op)
  end

  @spec line(PDF.t(), number(), number(), number(), number()) :: PDF.t()
  def line(%PDF{} = pdf, x1, y1, x2, y2)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) do
    PDF.append_current_op(pdf, {:line, x1, y1, x2, y2})
  end

  @spec rectangle(PDF.t(), number(), number(), number(), number()) :: PDF.t()
  def rectangle(%PDF{} = pdf, x, y, width, height)
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) do
    PDF.append_current_op(pdf, {:rectangle, x, y, width, height})
  end

  @spec circle(PDF.t(), number(), number(), number()) :: PDF.t()
  def circle(%PDF{} = pdf, cx, cy, radius)
      when is_number(cx) and is_number(cy) and is_number(radius) and radius > 0 do
    PDF.append_current_op(pdf, {:circle, cx, cy, radius})
  end

  @spec set_stroke_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  def set_stroke_color(%PDF{} = pdf, {r, g, b})
      when is_number(r) and is_number(g) and is_number(b) and r >= 0 and r <= 1 and g >= 0 and
             g <= 1 and b >= 0 and b <= 1 do
    PDF.append_current_op(pdf, {:set_stroke_color, {r, g, b}})
  end

  @spec set_fill_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  def set_fill_color(%PDF{} = pdf, {r, g, b})
      when is_number(r) and is_number(g) and is_number(b) and r >= 0 and r <= 1 and g >= 0 and
             g <= 1 and b >= 0 and b <= 1 do
    PDF.append_current_op(pdf, {:set_fill_color, {r, g, b}})
  end

  @spec move_to(PDF.t(), number(), number()) :: PDF.t()
  def move_to(%PDF{} = pdf, x, y) when is_number(x) and is_number(y) do
    PDF.append_current_op(pdf, {:move_to, x, y})
  end

  @spec line_to(PDF.t(), number(), number()) :: PDF.t()
  def line_to(%PDF{} = pdf, x, y) when is_number(x) and is_number(y) do
    PDF.append_current_op(pdf, {:line_to, x, y})
  end

  @spec bezier(PDF.t(), number(), number(), number(), number(), number(), number()) :: PDF.t()
  def bezier(%PDF{} = pdf, x1, y1, x2, y2, x3, y3)
      when is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) and is_number(x3) and
             is_number(y3) do
    PDF.append_current_op(pdf, {:bezier, x1, y1, x2, y2, x3, y3})
  end

  @spec stroke(PDF.t()) :: PDF.t()
  def stroke(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :stroke)
  end

  @spec fill(PDF.t()) :: PDF.t()
  def fill(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :fill)
  end

  @spec fill_even_odd(PDF.t()) :: PDF.t()
  def fill_even_odd(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :fill_even_odd)
  end

  @spec clip(PDF.t()) :: PDF.t()
  def clip(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :clip)
  end

  @spec clip_even_odd(PDF.t()) :: PDF.t()
  def clip_even_odd(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :clip_even_odd)
  end

  @spec set_line_width(PDF.t(), number()) :: PDF.t()
  def set_line_width(%PDF{} = pdf, width) when is_number(width) and width >= 0 do
    PDF.append_current_op(pdf, {:set_line_width, width})
  end

  @spec set_line_cap(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_cap(%PDF{} = pdf, cap) when cap in [0, 1, 2] do
    PDF.append_current_op(pdf, {:set_line_cap, cap})
  end

  @spec set_line_join(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_join(%PDF{} = pdf, join) when join in [0, 1, 2] do
    PDF.append_current_op(pdf, {:set_line_join, join})
  end

  @spec set_dash(PDF.t(), [number()], number()) :: PDF.t()
  def set_dash(%PDF{} = pdf, pattern, phase)
      when is_list(pattern) and pattern != [] and is_number(phase) and phase >= 0 do
    if Enum.all?(pattern, &is_number/1) do
      PDF.append_current_op(pdf, {:set_dash, pattern, phase})
    else
      raise ArgumentError, "dash pattern must contain only numbers"
    end
  end

  @spec set_miter_limit(PDF.t(), number()) :: PDF.t()
  def set_miter_limit(%PDF{} = pdf, limit) when is_number(limit) and limit > 0 do
    PDF.append_current_op(pdf, {:set_miter_limit, limit})
  end

  @spec save_state(PDF.t()) :: PDF.t()
  def save_state(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :save_state)
  end

  @spec restore_state(PDF.t()) :: PDF.t()
  def restore_state(%PDF{} = pdf) do
    PDF.append_current_op(pdf, :restore_state)
  end

  @spec image_jpeg(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_jpeg(%PDF{} = pdf, x, y, width, height, path)
      when is_number(x) and is_number(y) and is_number(width) and width > 0 and is_number(height) and
             height > 0 and is_binary(path) do
    image = Image.load_jpeg!(path)
    {pdf, image_id} = PDF.register_image(pdf, image)
    PDF.append_current_op(pdf, {:image, x, y, width, height, image_id})
  end

  @spec image_png(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_png(%PDF{} = pdf, x, y, width, height, path)
      when is_number(x) and is_number(y) and is_number(width) and width > 0 and is_number(height) and
             height > 0 and is_binary(path) do
    image = Image.load_png!(path)
    {pdf, image_id} = PDF.register_image(pdf, image)
    PDF.append_current_op(pdf, {:image, x, y, width, height, image_id})
  end
end
