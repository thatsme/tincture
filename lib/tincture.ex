defmodule Tincture do
  @moduledoc """
  Typographic-quality PDF generation, in pure Elixir.

  A document is an immutable struct threaded through a pipeline. Nothing is
  written until `export/1`, so a document can be built, inspected and tested
  before any bytes exist.

      Tincture.new()
      |> Tincture.page_size(:a4)
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(72, 700, "Hello")
      |> Tincture.export()

  ## Coordinates

  PDF user space has its origin at the **bottom-left** of the page, with y
  increasing upwards — the opposite of most screen coordinate systems. A y of
  700 on A4 is near the top. All positions and sizes are in points (1/72
  inch), so A4 is 595 x 842 and US Letter is 612 x 792.

  ## Text

  `text_at/4` draws a single string at a point. For anything that needs to
  wrap, use `text_paragraph/6`, which runs the typography engine: TeX
  hyphenation and Knuth-Plass line breaking, the same global optimisation TeX
  uses, rather than greedy first-fit.

      rich = Tincture.Typography.RichText.from_plain(body, font: "Times-Roman", size: 11)

      Tincture.text_paragraph(pdf, 72, 700, rich, 450,
        align: :justified,
        line_break: :optimal
      )

  For multi-page documents with headers, footers and page numbering, see
  `Tincture.Layout.Template`.

  ## Fonts

  The 14 standard PDF fonts are always available by name. TrueType and
  OpenType fonts are embedded with `register_ttf_font/4` and
  `register_otf_font/4`, and are **subsetted by default** — only the glyphs
  the document draws are embedded, which typically cuts an embedded font by
  70-90%.

  ## Architecture

  Each layer is usable on its own; the one above it is a convenience.

  ```mermaid
  flowchart TD
      A["Tincture<br/>drawing, text, links, images"] --> B
      B["Tincture.Layout<br/>boxes, tables, page templates"] --> C
      C["Tincture.Typography<br/>hyphenation, line breaking, kerning"] --> D
      D["Tincture.PDF<br/>document state, fonts, serialisation"] --> E
      E["Tincture.Font<br/>TrueType, OpenType, CFF parsing"]
  ```

  ## Zero runtime dependencies

  No Chrome, no wkhtmltopdf, no NIFs, no ports. The whole pipeline — font
  parsing, subsetting, hyphenation, line breaking, PDF serialisation — is
  Elixir and Erlang/OTP. It runs anywhere the BEAM runs.
  """

  import Bitwise

  alias Tincture.Font
  alias Tincture.Font.UnicodeRanges
  alias Tincture.PDF
  alias Tincture.PDF.Ops
  alias Tincture.PDF.Serialize
  alias Tincture.Typography
  alias Tincture.Typography.Line
  alias Tincture.Typography.RichText
  alias Tincture.Typography.RichText.Break
  alias Tincture.Typography.RichText.Space
  alias Tincture.Typography.RichText.Word
  alias Tincture.Unicode

  @type page_size :: :a4 | :letter | :legal | {number(), number()}
  @type rich_text :: RichText.t()
  @type paragraph_option ::
          {:align, :left | :center | :right | :justified}
          | {:line_height, number()}
          | {:line_break, :greedy | :optimal}
          | {:optimal_cost_model, :quadratic | :box_glue}
          | {:justify_max_space_multiplier, number() | :infinity}
          | {:justify_min_space_multiplier, number()}
          | {:widow_penalty, number()}
          | {:orphan_penalty, number()}
          | {:hyphen_penalty, number()}
          | {:fitness_class_penalty, number()}
          | {:consecutive_hyphen_penalty, number()}
          | {:rotate, number()}
          | {:fallback_fonts, [String.t()]}
          | {:bidi, :off | :basic}
          | {:shaping, :off | :latin_ligatures | :gsub_ligatures}
          | {:kerning, :off | :gpos}

  @doc """
  Create a new PDF state struct.
  """
  @spec new() :: PDF.t()
  def new do
    %PDF{}
  end

  @doc """
  Set the current page size.
  """
  @spec page_size(PDF.t(), page_size()) :: PDF.t()
  def page_size(%PDF{} = pdf, size) when size in [:a4, :letter, :legal] do
    %PDF{pdf | page_size: size}
  end

  def page_size(%PDF{} = pdf, {width, height})
      when is_number(width) and is_number(height) and width > 0 and height > 0 do
    %PDF{pdf | page_size: {width, height}}
  end

  @doc """
  Set document metadata fields (for example: `:title`, `:author`, `:keywords`).
  """
  @spec set_metadata(PDF.t(), map() | keyword()) :: PDF.t()
  def set_metadata(%PDF{} = pdf, metadata) when is_map(metadata) or is_list(metadata) do
    PDF.set_metadata(pdf, metadata)
  end

  @doc """
  Add a new page and make it the current page.
  """
  @spec add_page(PDF.t()) :: PDF.t()
  def add_page(%PDF{} = pdf) do
    PDF.add_page(pdf)
  end

  @doc """
  Switch the current page by page number (1-based).
  """
  @spec set_page(PDF.t(), pos_integer()) :: PDF.t()
  def set_page(%PDF{} = pdf, page_number) when is_integer(page_number) and page_number > 0 do
    PDF.set_page(pdf, page_number)
  end

  @doc """
  Add a document bookmark pointing to a page number.
  """
  @spec add_bookmark(PDF.t(), String.t(), pos_integer()) :: PDF.t()
  def add_bookmark(%PDF{} = pdf, title, page_number) do
    PDF.add_bookmark(pdf, title, page_number)
  end

  @doc """
  Add a clickable link over a rectangular region of the current page.

  `target` is either a URL string (or `{:url, url}`) for an external link, or
  `{:page, page_number}` for an internal cross-reference.

  Coordinates are in PDF user space, with the origin at the bottom-left of the
  page — the same space `text_at/4` and `rectangle/5` use. The rectangle is
  given as `x`, `y`, `width`, `height`; corners are normalised, so a negative
  width or height still produces a valid region rather than a dead link.

  Linking does not draw anything. Use `text_link/5` to draw text and make it
  clickable in one call, or pair this with your own `rectangle/5` and
  `set_fill_color/2` calls.

  ## Options

    * `:page` — which page to attach the link to. Defaults to the current page.
    * `:border` — `:none` (default) or `{horizontal, vertical, width}`. The
      default suppresses the black rectangle most viewers would otherwise draw
      around every link.

  ## Examples

      pdf
      |> Tincture.link(72, 700, 120, 14, "https://elixir-lang.org")

      # Internal cross-reference to page 3.
      Tincture.link(pdf, 72, 680, 120, 14, {:page, 3})

      # Attach a link to a page other than the current one.
      Tincture.link(pdf, 72, 660, 120, 14, "https://hex.pm", page: 1)

  """
  @spec link(PDF.t(), number(), number(), number(), number(), PDF.link_target() | String.t()) ::
          PDF.t()
  def link(%PDF{} = pdf, x, y, width, height, target) do
    link(pdf, x, y, width, height, target, [])
  end

  @spec link(
          PDF.t(),
          number(),
          number(),
          number(),
          number(),
          PDF.link_target() | String.t(),
          keyword()
        ) :: PDF.t()
  def link(%PDF{} = pdf, x, y, width, height, target, opts)
      when is_number(x) and is_number(y) and is_number(width) and is_number(height) and
             is_list(opts) do
    PDF.add_link(pdf, {x, y, x + width, y + height}, target, opts)
  end

  @doc """
  Draw text at X/Y and make it clickable.

  The link rectangle is measured from the text using the current font, so it
  covers exactly the drawn glyphs. Takes the same options as `link/7`, plus:

    * `:color` — an `{r, g, b}` fill colour to draw the text in. The colour
      change is wrapped in a save/restore of the graphics state, so it does not
      leak into later drawing. Defaults to leaving the colour alone, so links
      are not silently recoloured.

  ## Examples

      pdf
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_link(72, 700, "Elixir", "https://elixir-lang.org")

      # Conventional blue link.
      Tincture.text_link(pdf, 72, 680, "Hex", "https://hex.pm", color: {0.0, 0.3, 0.8})

  """
  @spec text_link(PDF.t(), number(), number(), String.t(), PDF.link_target() | String.t()) ::
          PDF.t()
  def text_link(%PDF{} = pdf, x, y, text, target) do
    text_link(pdf, x, y, text, target, [])
  end

  @spec text_link(
          PDF.t(),
          number(),
          number(),
          String.t(),
          PDF.link_target() | String.t(),
          keyword()
        ) :: PDF.t()
  def text_link(%PDF{} = pdf, x, y, text, target, opts)
      when is_number(x) and is_number(y) and is_binary(text) and is_list(opts) do
    {font_name, font_size} = pdf.current_font
    width = Font.text_width(font_name, font_size, text)

    # Approximate the drawn extent from the font size: PDF has no notion of a
    # text bounding box at draw time, and ascender/descender metrics are not
    # available for every registered font.
    ascent = font_size * 0.75
    descent = font_size * 0.25

    {drawn, link_opts} =
      case Keyword.pop(opts, :color) do
        {nil, rest} ->
          {text_at(pdf, x, y, text), rest}

        {{_r, _g, _b} = rgb, rest} ->
          drawn =
            pdf
            |> save_state()
            |> set_fill_color(rgb)
            |> text_at(x, y, text)
            |> restore_state()

          {drawn, rest}
      end

    link(drawn, x, y - descent, width, ascent + descent, target, link_opts)
  end

  @doc """
  Set the current font name and size.
  """
  @spec set_font(PDF.t(), String.t(), number()) :: PDF.t()
  def set_font(%PDF{} = pdf, font_name, size) do
    Ops.set_font(pdf, font_name, size)
  end

  @doc """
  Register an embedded TrueType font by name from a `.ttf` file path.
  """
  @spec register_ttf_font(PDF.t(), String.t(), Path.t()) :: PDF.t()
  def register_ttf_font(%PDF{} = pdf, font_name, path) do
    register_ttf_font(pdf, font_name, path, [])
  end

  @doc """
  Register an embedded TrueType font by name from a `.ttf` file path with embedding options.

  ## Options

    * `:subset` — how much of the font to embed. Defaults to `:used_text`.

      * `:used_text` — embed only the glyphs the document actually draws.
        Typically cuts an embedded font by 70-90%.
      * `:ascii_basic` — embed the printable ASCII range (32..126). Useful when
        you intend to edit the text later with an external tool.
      * `:none` — embed the font verbatim.

      Subsetted fonts carry the six-letter `/BaseFont` tag the PDF
      specification requires (for example `ABCDEF+Inter`). If a font cannot be
      subsetted safely, Tincture logs a warning and embeds it in full rather
      than producing a broken document.

    * `:enforce_embedding_permissions` — when `true`, raise instead of warn if
      the font's OS/2 `fsType` restricts embedding or subsetting. Defaults to
      `false`.

  ## Examples

      Tincture.new()
      |> Tincture.register_ttf_font("Inter", "priv/fonts/Inter.ttf")
      |> Tincture.set_font("Inter", 12)

      # Embed the whole font, e.g. for a template others will edit.
      Tincture.register_ttf_font(pdf, "Inter", path, subset: :none)

  """
  @spec register_ttf_font(PDF.t(), String.t(), Path.t(), keyword()) :: PDF.t()
  def register_ttf_font(%PDF{} = pdf, font_name, path, opts) when is_list(opts) do
    PDF.register_ttf_font(pdf, font_name, path, opts)
  end

  @doc """
  Register an embedded OpenType font by name from an `.otf` file path.
  """
  @spec register_otf_font(PDF.t(), String.t(), Path.t()) :: PDF.t()
  def register_otf_font(%PDF{} = pdf, font_name, path) do
    register_otf_font(pdf, font_name, path, [])
  end

  @doc """
  Register an embedded OpenType font by name from an `.otf` file path with embedding options.

  Takes the same options as `register_ttf_font/4`, including `:subset`, which
  defaults to `:used_text`.
  """
  @spec register_otf_font(PDF.t(), String.t(), Path.t(), keyword()) :: PDF.t()
  def register_otf_font(%PDF{} = pdf, font_name, path, opts) when is_list(opts) do
    PDF.register_otf_font(pdf, font_name, path, opts)
  end

  @doc """
  Place text at X/Y coordinates on the current page.
  """
  @spec text_at(PDF.t(), number(), number(), String.t()) :: PDF.t()
  def text_at(%PDF{} = pdf, x, y, text) do
    Ops.text_at(pdf, x, y, text)
  end

  @doc """
  Place text at X/Y coordinates, splitting glyph runs across fallback fonts when needed.
  """
  @spec text_at_with_fallback(PDF.t(), number(), number(), String.t(), [String.t()]) :: PDF.t()
  def text_at_with_fallback(%PDF{} = pdf, x, y, text, fallback_fonts \\ [])
      when is_number(x) and is_number(y) and is_binary(text) and is_list(fallback_fonts) do
    text_at_with_fallback(pdf, x, y, text, fallback_fonts, [])
  end

  @spec text_at_with_fallback(
          PDF.t(),
          number(),
          number(),
          String.t(),
          [String.t()],
          keyword()
        ) :: PDF.t()
  def text_at_with_fallback(%PDF{} = pdf, x, y, text, fallback_fonts, opts)
      when is_number(x) and is_number(y) and is_binary(text) and is_list(fallback_fonts) and
             is_list(opts) do
    shaping = normalize_shaping_option(Keyword.get(opts, :shaping, :off))
    kerning = normalize_kerning_option(Keyword.get(opts, :kerning, :off))

    {next_pdf, _rendered_width} =
      draw_text_with_fallback(
        pdf,
        x,
        y,
        text,
        fallback_fonts,
        shaping,
        kerning,
        fn doc, draw_x, draw_y, segment ->
          text_at(doc, draw_x, draw_y, segment)
        end
      )

    next_pdf
  end

  @doc """
  Place rotated text at X/Y, splitting glyph runs across fallback fonts when needed.
  """
  @spec text_at_rotated_with_fallback(
          PDF.t(),
          number(),
          number(),
          number(),
          String.t(),
          [String.t()]
        ) :: PDF.t()
  def text_at_rotated_with_fallback(
        %PDF{} = pdf,
        x,
        y,
        angle_degrees,
        text,
        fallback_fonts \\ []
      )
      when is_number(x) and is_number(y) and is_number(angle_degrees) and is_binary(text) and
             is_list(fallback_fonts) do
    text_at_rotated_with_fallback(pdf, x, y, angle_degrees, text, fallback_fonts, [])
  end

  @spec text_at_rotated_with_fallback(
          PDF.t(),
          number(),
          number(),
          number(),
          String.t(),
          [String.t()],
          keyword()
        ) :: PDF.t()
  def text_at_rotated_with_fallback(
        %PDF{} = pdf,
        x,
        y,
        angle_degrees,
        text,
        fallback_fonts,
        opts
      )
      when is_number(x) and is_number(y) and is_number(angle_degrees) and is_binary(text) and
             is_list(fallback_fonts) and is_list(opts) do
    shaping = normalize_shaping_option(Keyword.get(opts, :shaping, :off))
    kerning = normalize_kerning_option(Keyword.get(opts, :kerning, :off))

    {next_pdf, _rendered_width} =
      draw_text_with_fallback(
        pdf,
        x,
        y,
        text,
        fallback_fonts,
        shaping,
        kerning,
        fn doc, draw_x, draw_y, segment ->
          text_at_rotated(doc, draw_x, draw_y, angle_degrees, segment)
        end
      )

    next_pdf
  end

  defp draw_text_with_fallback(
         %PDF{} = pdf,
         x,
         y,
         text,
         fallback_fonts,
         shaping,
         kerning,
         draw_fun
       ) do
    {primary_font, size} = pdf.current_font
    entry_font = pdf.current_font
    fallback_fonts = normalize_fallback_fonts(pdf, fallback_fonts, primary_font)
    font_order = [primary_font | fallback_fonts]
    shaped_text = shape_text_for_fonts(text, shaping, pdf, font_order)

    if shaped_text == "" do
      {pdf, 0.0}
    else
      shaped_text
      |> split_text_by_fallback_font(pdf, font_order, primary_font)
      |> Enum.reduce({pdf, x * 1.0, 0.0}, fn {font_name, segment},
                                             {acc_pdf, cursor_x, total_width} ->
        {next_pdf, segment_width} =
          acc_pdf
          |> set_font(font_name, size)
          |> draw_text_segment(
            cursor_x,
            y,
            segment,
            font_name,
            size,
            kerning,
            draw_fun
          )

        next_x = cursor_x + segment_width
        {next_pdf, next_x, total_width + segment_width}
      end)
      |> then(fn {next_pdf, _cursor_x, total_width} ->
        restored_pdf =
          if next_pdf.current_font == entry_font do
            next_pdf
          else
            {entry_name, entry_size} = entry_font
            set_font(next_pdf, entry_name, entry_size)
          end

        {restored_pdf, total_width}
      end)
    end
  end

  defp draw_text_segment(
         %PDF{} = pdf,
         cursor_x,
         y,
         segment,
         font_name,
         size,
         :gpos,
         draw_fun
       ) do
    graphemes = String.graphemes(segment)

    with true <- length(graphemes) > 1,
         %{ttf_metrics: ttf_metrics} <- Map.get(pdf.embedded_fonts, font_name),
         true <- is_map(ttf_metrics),
         units_per_em when is_integer(units_per_em) and units_per_em > 0 <-
           Map.get(ttf_metrics, :units_per_em),
         gpos_pair_kerns when is_map(gpos_pair_kerns) and map_size(gpos_pair_kerns) > 0 <-
           Map.get(ttf_metrics, :gpos_pair_kerns) do
      {next_pdf, next_x, _prev_codepoint} =
        Enum.reduce(graphemes, {pdf, cursor_x, nil}, fn grapheme,
                                                        {acc_pdf, acc_x, prev_codepoint} ->
          current_codepoint = kerning_codepoint_for_grapheme(grapheme)

          kerning_units =
            gpos_pair_kerning_units_for_pair(prev_codepoint, current_codepoint, gpos_pair_kerns)

          draw_x = acc_x + kerning_units * size / units_per_em
          next_pdf = draw_fun.(acc_pdf, draw_x, y, grapheme)
          grapheme_width = text_width_for_font(next_pdf, font_name, size, grapheme)

          next_prev_codepoint =
            if is_integer(current_codepoint) and current_codepoint >= 0 do
              current_codepoint
            else
              prev_codepoint
            end

          {next_pdf, draw_x + grapheme_width, next_prev_codepoint}
        end)

      {next_pdf, next_x - cursor_x}
    else
      _other ->
        next_pdf = draw_fun.(pdf, cursor_x, y, segment)
        {next_pdf, text_width_for_font(next_pdf, font_name, size, segment)}
    end
  end

  defp draw_text_segment(
         %PDF{} = pdf,
         cursor_x,
         y,
         segment,
         font_name,
         size,
         _kerning,
         draw_fun
       ) do
    next_pdf = draw_fun.(pdf, cursor_x, y, segment)
    {next_pdf, text_width_for_font(next_pdf, font_name, size, segment)}
  end

  @doc """
  Place text at X/Y coordinates rotated by the given angle in degrees.
  """
  @spec text_at_rotated(PDF.t(), number(), number(), number(), String.t()) :: PDF.t()
  def text_at_rotated(%PDF{} = pdf, x, y, angle_degrees, text) do
    Ops.text_at_rotated(pdf, x, y, angle_degrees, text)
  end

  @doc """
  Draw a stroked line between two points.
  """
  @spec line(PDF.t(), number(), number(), number(), number()) :: PDF.t()
  def line(%PDF{} = pdf, x1, y1, x2, y2) do
    Ops.line(pdf, x1, y1, x2, y2)
  end

  @doc """
  Draw a stroked rectangle.
  """
  @spec rectangle(PDF.t(), number(), number(), number(), number()) :: PDF.t()
  def rectangle(%PDF{} = pdf, x, y, width, height) do
    Ops.rectangle(pdf, x, y, width, height)
  end

  @doc """
  Draw a stroked circle.
  """
  @spec circle(PDF.t(), number(), number(), number()) :: PDF.t()
  def circle(%PDF{} = pdf, cx, cy, radius) do
    Ops.circle(pdf, cx, cy, radius)
  end

  @doc """
  Set stroke color using normalized RGB values (0..1).
  """
  @spec set_stroke_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  def set_stroke_color(%PDF{} = pdf, rgb) do
    Ops.set_stroke_color(pdf, rgb)
  end

  @doc """
  Set fill color using normalized RGB values (0..1).
  """
  @spec set_fill_color(PDF.t(), {number(), number(), number()}) :: PDF.t()
  def set_fill_color(%PDF{} = pdf, rgb) do
    Ops.set_fill_color(pdf, rgb)
  end

  @doc """
  Move current path point to X/Y.
  """
  @spec move_to(PDF.t(), number(), number()) :: PDF.t()
  def move_to(%PDF{} = pdf, x, y) do
    Ops.move_to(pdf, x, y)
  end

  @doc """
  Add a line segment from current path point to X/Y.
  """
  @spec line_to(PDF.t(), number(), number()) :: PDF.t()
  def line_to(%PDF{} = pdf, x, y) do
    Ops.line_to(pdf, x, y)
  end

  @doc """
  Add a cubic Bezier segment to the current path.
  """
  @spec bezier(PDF.t(), number(), number(), number(), number(), number(), number()) :: PDF.t()
  def bezier(%PDF{} = pdf, x1, y1, x2, y2, x3, y3) do
    Ops.bezier(pdf, x1, y1, x2, y2, x3, y3)
  end

  @doc """
  Stroke the current path.
  """
  @spec stroke(PDF.t()) :: PDF.t()
  def stroke(%PDF{} = pdf) do
    Ops.stroke(pdf)
  end

  @doc """
  Fill the current path.
  """
  @spec fill(PDF.t()) :: PDF.t()
  def fill(%PDF{} = pdf) do
    Ops.fill(pdf)
  end

  @doc """
  Fill the current path using the even-odd rule.
  """
  @spec fill_even_odd(PDF.t()) :: PDF.t()
  def fill_even_odd(%PDF{} = pdf) do
    Ops.fill_even_odd(pdf)
  end

  @doc """
  Set the clipping path from the current path.
  """
  @spec clip(PDF.t()) :: PDF.t()
  def clip(%PDF{} = pdf) do
    Ops.clip(pdf)
  end

  @doc """
  Set the clipping path from the current path using the even-odd rule.
  """
  @spec clip_even_odd(PDF.t()) :: PDF.t()
  def clip_even_odd(%PDF{} = pdf) do
    Ops.clip_even_odd(pdf)
  end

  @doc """
  Set stroke line width.
  """
  @spec set_line_width(PDF.t(), number()) :: PDF.t()
  def set_line_width(%PDF{} = pdf, width) do
    Ops.set_line_width(pdf, width)
  end

  @doc """
  Set line cap style: 0 butt, 1 round, 2 projecting square.
  """
  @spec set_line_cap(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_cap(%PDF{} = pdf, cap) do
    Ops.set_line_cap(pdf, cap)
  end

  @doc """
  Set line join style: 0 miter, 1 round, 2 bevel.
  """
  @spec set_line_join(PDF.t(), 0 | 1 | 2) :: PDF.t()
  def set_line_join(%PDF{} = pdf, join) do
    Ops.set_line_join(pdf, join)
  end

  @doc """
  Set dash pattern and phase.
  """
  @spec set_dash(PDF.t(), [number()], number()) :: PDF.t()
  def set_dash(%PDF{} = pdf, pattern, phase) do
    Ops.set_dash(pdf, pattern, phase)
  end

  @doc """
  Set miter limit for stroked joins.
  """
  @spec set_miter_limit(PDF.t(), number()) :: PDF.t()
  def set_miter_limit(%PDF{} = pdf, limit) do
    Ops.set_miter_limit(pdf, limit)
  end

  @doc """
  Save graphics state.
  """
  @spec save_state(PDF.t()) :: PDF.t()
  def save_state(%PDF{} = pdf) do
    Ops.save_state(pdf)
  end

  @doc """
  Restore graphics state.
  """
  @spec restore_state(PDF.t()) :: PDF.t()
  def restore_state(%PDF{} = pdf) do
    Ops.restore_state(pdf)
  end

  @doc """
  Draw a JPEG image at X/Y with the given width and height.
  """
  @spec image_jpeg(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_jpeg(%PDF{} = pdf, x, y, width, height, path) do
    Ops.image_jpeg(pdf, x, y, width, height, path)
  end

  @doc """
  Draw a PNG image at X/Y with the given width and height.
  """
  @spec image_png(PDF.t(), number(), number(), number(), number(), Path.t()) :: PDF.t()
  def image_png(%PDF{} = pdf, x, y, width, height, path) do
    Ops.image_png(pdf, x, y, width, height, path)
  end

  @doc """
  Export a PDF struct to a binary.
  """
  @spec export(PDF.t()) :: binary()
  def export(%PDF{} = pdf) do
    Serialize.export(pdf)
  end

  @doc """
  Export and write a PDF to disk.
  """
  @spec save(PDF.t(), Path.t()) :: :ok | {:error, term()}
  def save(%PDF{} = pdf, path) when is_binary(path) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, export(pdf))
    end
  end

  @doc """
  Render a laid-out paragraph of rich text at X/Y origin using typography layout.
  """
  @spec text_paragraph(PDF.t(), number(), number(), rich_text(), number(), [paragraph_option()]) ::
          PDF.t()
  def text_paragraph(%PDF{} = pdf, x, y, %RichText{} = rich_text, max_width, opts \\ [])
      when is_number(x) and is_number(y) and is_number(max_width) and max_width > 0 and
             is_list(opts) do
    rotate = Keyword.get(opts, :rotate)
    fallback_fonts = Keyword.get(opts, :fallback_fonts, [])
    bidi = Keyword.get(opts, :bidi, :off)
    shaping = Keyword.get(opts, :shaping, :off)
    kerning = Keyword.get(opts, :kerning, :off)

    if not is_nil(rotate) and not is_number(rotate) do
      raise ArgumentError, "rotate option must be a number of degrees"
    end

    if not is_list(fallback_fonts) do
      raise ArgumentError, "fallback_fonts option must be a list"
    end

    bidi = normalize_bidi_option(bidi)
    shaping = normalize_shaping_option(shaping)
    kerning = normalize_kerning_option(kerning)

    layout_opts = Keyword.drop(opts, [:rotate, :fallback_fonts, :bidi, :shaping, :kerning])

    Typography.layout_paragraph(rich_text, max_width, layout_opts)
    |> Enum.reduce(pdf, fn %Line{} = line, acc_pdf ->
      render_line(
        acc_pdf,
        x + line.x,
        y + line.y,
        line.tokens,
        rotate,
        fallback_fonts,
        bidi,
        shaping,
        kerning
      )
    end)
  end

  defp render_line(pdf, start_x, line_y, tokens, rotate, fallback_fonts, bidi, shaping, kerning) do
    visual_tokens = bidi_visual_tokens(tokens, bidi)

    {pdf, _cursor_x} =
      Enum.reduce(visual_tokens, {pdf, start_x * 1.0}, fn token, {acc_pdf, cursor_x} ->
        render_token(
          token,
          acc_pdf,
          cursor_x,
          line_y * 1.0,
          rotate,
          fallback_fonts,
          shaping,
          kerning
        )
      end)

    pdf
  end

  defp render_token(
         %Word{} = word,
         pdf,
         cursor_x,
         line_y,
         rotate,
         fallback_fonts,
         shaping,
         kerning
       ) do
    {next_pdf, rendered_width} =
      pdf
      |> set_font(word.font, word.size)
      |> then(fn doc ->
        case rotate do
          degrees when is_number(degrees) ->
            draw_text_with_fallback(
              doc,
              cursor_x,
              line_y,
              word.text,
              fallback_fonts,
              shaping,
              kerning,
              fn draw_doc, draw_x, draw_y, segment ->
                text_at_rotated(draw_doc, draw_x, draw_y, degrees, segment)
              end
            )

          _ ->
            draw_text_with_fallback(
              doc,
              cursor_x,
              line_y,
              word.text,
              fallback_fonts,
              shaping,
              kerning,
              fn draw_doc, draw_x, draw_y, segment ->
                text_at(draw_doc, draw_x, draw_y, segment)
              end
            )
        end
      end)

    {next_pdf, cursor_x + rendered_width}
  end

  defp render_token(
         %Space{} = space,
         pdf,
         cursor_x,
         _line_y,
         _rotate,
         _fallback_fonts,
         _shaping,
         _kerning
       ) do
    {pdf, cursor_x + space.width}
  end

  defp render_token(
         %Break{},
         pdf,
         cursor_x,
         _line_y,
         _rotate,
         _fallback_fonts,
         _shaping,
         _kerning
       ) do
    {pdf, cursor_x}
  end

  defp normalize_bidi_option(:off), do: :off
  defp normalize_bidi_option(:basic), do: :basic

  defp normalize_bidi_option(_other),
    do: raise(ArgumentError, "bidi option must be :off or :basic")

  defp normalize_shaping_option(:off), do: :off
  defp normalize_shaping_option(:latin_ligatures), do: :latin_ligatures
  defp normalize_shaping_option(:gsub_ligatures), do: :gsub_ligatures

  defp normalize_shaping_option(_other),
    do:
      raise(
        ArgumentError,
        "shaping option must be :off, :latin_ligatures, or :gsub_ligatures"
      )

  defp normalize_kerning_option(:off), do: :off
  defp normalize_kerning_option(:gpos), do: :gpos

  defp normalize_kerning_option(_other),
    do: raise(ArgumentError, "kerning option must be :off or :gpos")

  defp bidi_visual_tokens(tokens, :off), do: tokens

  defp bidi_visual_tokens(tokens, :basic) do
    entries =
      tokens
      |> Enum.map(fn token -> %{token: token, dir: token_direction(token)} end)

    base_dir = first_strong_dir(entries) || :ltr
    resolved = resolve_neutral_token_dirs(entries, base_dir)
    runs = chunk_by_dir(resolved)

    runs =
      case base_dir do
        :rtl -> Enum.reverse(runs)
        _ -> runs
      end

    runs
    |> Enum.flat_map(fn {dir, run_entries} ->
      run_tokens = Enum.map(run_entries, & &1.token)

      if dir == :rtl do
        run_tokens
        |> Enum.reverse()
        |> Enum.map(&reverse_rtl_token_text/1)
      else
        run_tokens
      end
    end)
  end

  defp token_direction(%Word{text: text}), do: word_direction(text)
  defp token_direction(%Space{}), do: :neutral
  defp token_direction(%Break{}), do: :neutral

  defp word_direction(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.find_value(:neutral, fn codepoint ->
      cond do
        rtl_codepoint?(codepoint) -> :rtl
        ltr_codepoint?(codepoint) -> :ltr
        true -> nil
      end
    end)
  end

  defp rtl_codepoint?(cp) do
    (cp >= 0x0590 and cp <= 0x08FF) or (cp >= 0xFB1D and cp <= 0xFEFC)
  end

  defp ltr_codepoint?(cp) do
    (cp >= ?A and cp <= ?Z) or (cp >= ?a and cp <= ?z) or (cp >= ?0 and cp <= ?9) or
      (cp >= 0x00C0 and cp <= 0x02AF)
  end

  defp first_strong_dir(entries) do
    entries
    |> Enum.find_value(fn entry ->
      if entry.dir in [:ltr, :rtl], do: entry.dir, else: nil
    end)
  end

  defp resolve_neutral_token_dirs(entries, base_dir) do
    Enum.with_index(entries)
    |> Enum.map(fn {entry, idx} ->
      if entry.dir == :neutral do
        prev = prev_strong_dir(entries, idx)
        next = next_strong_dir(entries, idx)
        %{entry | dir: prev || next || base_dir}
      else
        entry
      end
    end)
  end

  defp prev_strong_dir(entries, idx) do
    entries
    |> Enum.take(idx)
    |> Enum.reverse()
    |> Enum.find_value(fn entry -> if entry.dir in [:ltr, :rtl], do: entry.dir, else: nil end)
  end

  defp next_strong_dir(entries, idx) do
    entries
    |> Enum.drop(idx + 1)
    |> Enum.find_value(fn entry -> if entry.dir in [:ltr, :rtl], do: entry.dir, else: nil end)
  end

  defp chunk_by_dir([]), do: []

  defp chunk_by_dir([first | rest]) do
    {runs_reversed, current_dir, current_entries} =
      Enum.reduce(rest, {[], first.dir, [first]}, fn entry, {runs_acc, dir, entries_acc} ->
        if entry.dir == dir do
          {runs_acc, dir, [entry | entries_acc]}
        else
          {[{dir, Enum.reverse(entries_acc)} | runs_acc], entry.dir, [entry]}
        end
      end)

    Enum.reverse([{current_dir, Enum.reverse(current_entries)} | runs_reversed])
  end

  defp reverse_rtl_token_text(%Word{text: text} = word) do
    %Word{word | text: reverse_graphemes(text)}
  end

  defp reverse_rtl_token_text(token), do: token

  defp reverse_graphemes(text) do
    text
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end

  defp shape_text_for_fonts(text, :off, _pdf, _font_order), do: text

  defp shape_text_for_fonts(text, shaping_mode, pdf, font_order)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    Enum.reduce(
      ordered_ligature_replacements(pdf, font_order, shaping_mode),
      text,
      fn {source, target}, acc ->
        target_codepoint =
          target
          |> String.to_charlist()
          |> hd()

        source_length = source |> String.graphemes() |> length()

        if Enum.any?(font_order, fn font_name ->
             font_supports_ligature_replacement?(
               pdf,
               font_name,
               source,
               target,
               target_codepoint,
               source_length,
               shaping_mode
             )
           end) do
          String.replace(acc, source, target)
        else
          acc
        end
      end
    )
  end

  defp ordered_ligature_replacements(%PDF{} = pdf, font_order, shaping_mode)
       when is_list(font_order) and shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    gsub_ligature_replacements =
      font_order
      |> Enum.reduce([], fn font_name, acc ->
        acc ++ font_gsub_ligature_replacements(pdf, font_name, shaping_mode)
      end)
      |> Enum.uniq()

    defaults =
      latin_ligature_replacements()
      |> Enum.reject(fn replacement -> Enum.member?(gsub_ligature_replacements, replacement) end)

    (gsub_ligature_replacements ++ defaults)
    |> Enum.sort_by(fn {source, _target} -> {-String.length(source), source} end)
  end

  defp font_gsub_ligature_replacements(%PDF{} = pdf, font_name, shaping_mode)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: ttf_metrics} when is_map(ttf_metrics) ->
        gsub_ligatures = font_gsub_ligature_map(ttf_metrics, shaping_mode)

        gsub_ligatures
        |> Enum.filter(fn {source, target} ->
          is_binary(source) and byte_size(source) > 0 and is_binary(target) and
            byte_size(target) > 0
        end)
        |> Enum.map(fn {source, target} -> {source, target} end)

      _ ->
        []
    end
  end

  defp font_gsub_ligature_map(ttf_metrics, :latin_ligatures) when is_map(ttf_metrics) do
    case Map.get(ttf_metrics, :gsub_ligatures) do
      gsub_ligatures when is_map(gsub_ligatures) -> gsub_ligatures
      _other -> %{}
    end
  end

  defp font_gsub_ligature_map(ttf_metrics, :gsub_ligatures) when is_map(ttf_metrics) do
    case Map.get(ttf_metrics, :gsub_substitutions_all) do
      gsub_substitutions_all
      when is_map(gsub_substitutions_all) and map_size(gsub_substitutions_all) > 0 ->
        gsub_substitutions_all

      _other ->
        case Map.get(ttf_metrics, :gsub_ligatures_all) do
          gsub_ligatures_all when is_map(gsub_ligatures_all) ->
            gsub_ligatures_all

          _other ->
            case Map.get(ttf_metrics, :gsub_ligatures) do
              gsub_ligatures when is_map(gsub_ligatures) -> gsub_ligatures
              _other -> %{}
            end
        end
    end
  end

  defp font_supports_ligature_replacement?(
         %PDF{} = pdf,
         font_name,
         source,
         target,
         target_codepoint,
         source_length,
         shaping_mode
       )
       when is_binary(source) and byte_size(source) > 0 and is_binary(target) and
              byte_size(target) > 0 and is_integer(target_codepoint) and target_codepoint >= 0 and
              is_integer(source_length) and source_length >= 1 and
              shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    font_supports_codepoint?(pdf, font_name, target_codepoint) and
      ligature_mapping_supported?(pdf, font_name, source, target, shaping_mode) and
      ligature_feature_supported?(pdf, font_name, shaping_mode) and
      ligature_context_length_allowed?(pdf, font_name, source_length)
  end

  defp ligature_mapping_supported?(%PDF{} = pdf, font_name, source, target, shaping_mode)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: ttf_metrics} when is_map(ttf_metrics) ->
        gsub_ligatures = font_gsub_ligature_map(ttf_metrics, shaping_mode)

        if map_size(gsub_ligatures) > 0 do
          Map.get(gsub_ligatures, source) == target
        else
          Enum.member?(latin_ligature_replacements(), {source, target})
        end

      _ ->
        Enum.member?(latin_ligature_replacements(), {source, target})
    end
  end

  defp ligature_feature_supported?(%PDF{} = pdf, font_name, shaping_mode)
       when shaping_mode in [:latin_ligatures, :gsub_ligatures] do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{gsub_features: gsub_features, gsub_scripts: gsub_scripts}}
      when is_list(gsub_features) and is_list(gsub_scripts) ->
        feature_ok? =
          case shaping_mode do
            :latin_ligatures ->
              gsub_features == [] or Enum.member?(gsub_features, "liga")

            :gsub_ligatures ->
              gsub_features == [] or
                Enum.any?(["liga", "rlig", "ccmp"], &Enum.member?(gsub_features, &1))
          end

        script_ok? = ligature_script_supported?(gsub_scripts, shaping_mode)
        feature_ok? and script_ok?

      _ ->
        true
    end
  end

  defp ligature_script_supported?(gsub_scripts, :latin_ligatures) when is_list(gsub_scripts),
    do: gsub_scripts == [] or Enum.member?(gsub_scripts, "latn")

  defp ligature_script_supported?(_gsub_scripts, :gsub_ligatures), do: true

  defp ligature_context_length_allowed?(%PDF{} = pdf, font_name, source_length)
       when is_integer(source_length) and source_length >= 1 do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{os2_max_context: max_context}}
      when is_integer(max_context) and max_context > 0 ->
        source_length <= max_context

      _ ->
        true
    end
  end

  defp latin_ligature_replacements do
    [
      {"ffl", "ﬄ"},
      {"ffi", "ﬃ"},
      {"ff", "ﬀ"},
      {"fi", "ﬁ"},
      {"fl", "ﬂ"}
    ]
  end

  defp normalize_fallback_fonts(%PDF{} = pdf, fallback_fonts, primary_font) do
    fallback_fonts
    |> Enum.map(fn font_name ->
      if is_binary(font_name) and byte_size(font_name) > 0 do
        font_name
      else
        raise ArgumentError, "fallback fonts must be non-empty font-name strings"
      end
    end)
    |> Enum.reject(&(&1 == primary_font))
    |> Enum.uniq()
    |> Enum.map(fn font_name ->
      if font_available_in_pdf?(pdf, font_name) do
        font_name
      else
        raise ArgumentError, "unknown font: #{font_name}"
      end
    end)
  end

  defp append_segment([], font_name, segment), do: [{font_name, segment}]

  defp append_segment([{font_name, text} | rest], font_name, segment),
    do: [{font_name, text <> segment} | rest]

  defp append_segment(segments, font_name, segment), do: [{font_name, segment} | segments]

  defp split_text_by_fallback_font(text, pdf, font_order, primary_font) do
    text
    |> String.graphemes()
    |> Enum.reduce([], fn grapheme, acc ->
      selected_font = select_fallback_font_for_grapheme(pdf, font_order, primary_font, grapheme)
      append_segment(acc, selected_font, grapheme)
    end)
    |> Enum.reverse()
  end

  defp select_fallback_font_for_grapheme(%PDF{} = pdf, font_order, primary_font, grapheme) do
    case String.to_charlist(grapheme) do
      [base_codepoint, selector_codepoint] ->
        if Unicode.variation_selector_codepoint?(selector_codepoint) do
          Enum.find(font_order, fn font_name ->
            font_has_non_default_variation?(pdf, font_name, base_codepoint, selector_codepoint)
          end) ||
            Enum.find(font_order, primary_font, fn font_name ->
              font_supports_variation_grapheme?(
                pdf,
                font_name,
                base_codepoint,
                selector_codepoint
              )
            end)
        else
          Enum.find(font_order, primary_font, fn font_name ->
            font_supports_grapheme_codepoints?(pdf, font_name, [
              base_codepoint,
              selector_codepoint
            ])
          end)
        end

      codepoints ->
        Enum.find(font_order, primary_font, fn font_name ->
          font_supports_grapheme_codepoints?(pdf, font_name, codepoints)
        end)
    end
  end

  defp font_supports_variation_grapheme?(
         %PDF{} = pdf,
         font_name,
         base_codepoint,
         selector_codepoint
       )
       when is_integer(base_codepoint) and is_integer(selector_codepoint) do
    font_has_non_default_variation?(pdf, font_name, base_codepoint, selector_codepoint) or
      font_supports_codepoint?(pdf, font_name, base_codepoint)
  end

  defp font_supports_grapheme_codepoints?(%PDF{} = pdf, font_name, codepoints)
       when is_list(codepoints) do
    Enum.all?(codepoints, fn codepoint ->
      Unicode.zero_advance_codepoint?(codepoint) or
        font_supports_codepoint?(pdf, font_name, codepoint)
    end)
  end

  defp font_has_non_default_variation?(
         %PDF{} = pdf,
         font_name,
         base_codepoint,
         selector_codepoint
       )
       when is_integer(base_codepoint) and is_integer(selector_codepoint) do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{cmap_non_default_uvs: cmap_non_default_uvs}}
      when is_map(cmap_non_default_uvs) ->
        Map.has_key?(cmap_non_default_uvs, {base_codepoint, selector_codepoint})

      _ ->
        false
    end
  end

  defp font_available_in_pdf?(%PDF{} = pdf, font_name) do
    Font.font_available?(font_name) or Map.has_key?(pdf.embedded_fonts, font_name)
  end

  defp font_supports_codepoint?(%PDF{} = pdf, font_name, codepoint)
       when is_integer(codepoint) and codepoint >= 0 do
    if Font.font_available?(font_name) do
      codepoint <= 255
    else
      embedded_font_supports_codepoint?(Map.get(pdf.embedded_fonts, font_name), codepoint)
    end
  end

  defp embedded_font_supports_codepoint?(
         %{ttf_metrics: %{cmap_by_code: cmap_by_code}},
         codepoint
       )
       when is_map(cmap_by_code) and map_size(cmap_by_code) > 0 do
    Map.has_key?(cmap_by_code, codepoint)
  end

  defp embedded_font_supports_codepoint?(
         %{ttf_metrics: %{cmap_by_code: cmap_by_code} = ttf_metrics},
         codepoint
       )
       when is_map(cmap_by_code) and map_size(cmap_by_code) == 0 do
    unicode_ranges = Map.get(ttf_metrics, :os2_unicode_ranges)
    code_page_ranges = Map.get(ttf_metrics, :os2_code_page_ranges)

    cond do
      is_tuple(unicode_ranges) and not UnicodeRanges.all_zero?(unicode_ranges) ->
        UnicodeRanges.supports_codepoint?(unicode_ranges, codepoint)

      is_tuple(code_page_ranges) and not code_page_ranges_all_zero?(code_page_ranges) ->
        code_page_ranges_support_codepoint?(code_page_ranges, codepoint)

      true ->
        codepoint <= 255
    end
  end

  defp embedded_font_supports_codepoint?(%{}, codepoint), do: codepoint <= 255
  defp embedded_font_supports_codepoint?(_other, _codepoint), do: false

  defp code_page_ranges_support_codepoint?({range1, range2}, codepoint)
       when is_integer(range1) and is_integer(range2) and is_integer(codepoint) do
    cond do
      codepoint < 0 ->
        false

      codepoint <= 0x7F ->
        true

      codepoint <= 0xFF ->
        latin_1_supported? = (range1 &&& 1 <<< 0) != 0
        latin_1_supported?

      codepoint >= 0x0100 and codepoint <= 0x024F ->
        latin_2_supported? = (range1 &&& 1 <<< 1) != 0
        turkish_supported? = (range1 &&& 1 <<< 4) != 0 and turkish_codepoint?(codepoint)
        baltic_supported? = (range1 &&& 1 <<< 7) != 0 and baltic_codepoint?(codepoint)
        vietnamese_supported? = (range1 &&& 1 <<< 8) != 0 and vietnamese_codepoint?(codepoint)
        latin_2_supported? or turkish_supported? or baltic_supported? or vietnamese_supported?

      codepoint >= 0x0400 and codepoint <= 0x04FF ->
        cyrillic_supported? = (range1 &&& 1 <<< 2) != 0
        cyrillic_supported?

      codepoint >= 0x0370 and codepoint <= 0x03FF ->
        greek_supported? = (range1 &&& 1 <<< 3) != 0
        greek_supported?

      codepoint >= 0x0590 and codepoint <= 0x05FF ->
        hebrew_supported? = (range1 &&& 1 <<< 5) != 0
        hebrew_supported?

      codepoint >= 0x0600 and codepoint <= 0x06FF ->
        arabic_supported? = (range1 &&& 1 <<< 6) != 0
        arabic_supported?

      codepoint >= 0x0E00 and codepoint <= 0x0E7F ->
        thai_supported? = (range2 &&& 1 <<< 0) != 0
        thai_supported?

      true ->
        false
    end
  end

  defp code_page_ranges_support_codepoint?(_ranges, _codepoint), do: false

  defp turkish_codepoint?(0x011E), do: true
  defp turkish_codepoint?(0x011F), do: true
  defp turkish_codepoint?(0x0130), do: true
  defp turkish_codepoint?(0x0131), do: true
  defp turkish_codepoint?(0x015E), do: true
  defp turkish_codepoint?(0x015F), do: true
  defp turkish_codepoint?(_codepoint), do: false

  defp baltic_codepoint?(0x0104), do: true
  defp baltic_codepoint?(0x0105), do: true
  defp baltic_codepoint?(0x010C), do: true
  defp baltic_codepoint?(0x010D), do: true
  defp baltic_codepoint?(0x0112), do: true
  defp baltic_codepoint?(0x0113), do: true
  defp baltic_codepoint?(0x0116), do: true
  defp baltic_codepoint?(0x0117), do: true
  defp baltic_codepoint?(0x0122), do: true
  defp baltic_codepoint?(0x0123), do: true
  defp baltic_codepoint?(0x012A), do: true
  defp baltic_codepoint?(0x012B), do: true
  defp baltic_codepoint?(0x012E), do: true
  defp baltic_codepoint?(0x012F), do: true
  defp baltic_codepoint?(0x0136), do: true
  defp baltic_codepoint?(0x0137), do: true
  defp baltic_codepoint?(0x013B), do: true
  defp baltic_codepoint?(0x013C), do: true
  defp baltic_codepoint?(0x0145), do: true
  defp baltic_codepoint?(0x0146), do: true
  defp baltic_codepoint?(0x014C), do: true
  defp baltic_codepoint?(0x014D), do: true
  defp baltic_codepoint?(0x0156), do: true
  defp baltic_codepoint?(0x0157), do: true
  defp baltic_codepoint?(0x0160), do: true
  defp baltic_codepoint?(0x0161), do: true
  defp baltic_codepoint?(0x016A), do: true
  defp baltic_codepoint?(0x016B), do: true
  defp baltic_codepoint?(0x0172), do: true
  defp baltic_codepoint?(0x0173), do: true
  defp baltic_codepoint?(0x017D), do: true
  defp baltic_codepoint?(0x017E), do: true
  defp baltic_codepoint?(_codepoint), do: false

  defp vietnamese_codepoint?(0x01A0), do: true
  defp vietnamese_codepoint?(0x01A1), do: true
  defp vietnamese_codepoint?(0x01AF), do: true
  defp vietnamese_codepoint?(0x01B0), do: true
  defp vietnamese_codepoint?(_codepoint), do: false

  defp code_page_ranges_all_zero?({0, 0}), do: true
  defp code_page_ranges_all_zero?(_ranges), do: false

  defp text_width_for_font(%PDF{} = pdf, font_name, size, text) do
    if Font.font_available?(font_name) do
      Font.text_width(font_name, size, text)
    else
      embedded_text_width(pdf, font_name, size, text)
    end
  end

  defp embedded_text_width(%PDF{} = pdf, font_name, size, text) do
    case Map.get(pdf.embedded_fonts, font_name) do
      %{ttf_metrics: %{advance_widths: advance_widths, units_per_em: units_per_em} = ttf_metrics}
      when is_list(advance_widths) and is_integer(units_per_em) and units_per_em > 0 ->
        cmap_by_code = Map.get(ttf_metrics, :cmap_by_code, %{})
        gpos_pair_kerns = Map.get(ttf_metrics, :gpos_pair_kerns, %{})
        codepoints = String.to_charlist(text)

        {base_units, kerning_codepoints} =
          variation_aware_width_units(codepoints, ttf_metrics, advance_widths, cmap_by_code)

        kerning_units = gpos_pair_kerning_units(kerning_codepoints, gpos_pair_kerns)
        units = max(base_units + kerning_units, 0)

        units * size / units_per_em

      _ ->
        String.length(text) * size * 0.6
    end
  end

  defp variation_aware_width_units(codepoints, ttf_metrics, advance_widths, cmap_by_code)
       when is_list(codepoints) and is_map(ttf_metrics) and is_list(advance_widths) and
              is_map(cmap_by_code) do
    cmap_non_default_uvs = Map.get(ttf_metrics, :cmap_non_default_uvs, %{})

    do_variation_aware_width_units(
      codepoints,
      cmap_non_default_uvs,
      advance_widths,
      cmap_by_code,
      0,
      []
    )
  end

  defp do_variation_aware_width_units(
         [base_codepoint, selector_codepoint | rest],
         cmap_non_default_uvs,
         advance_widths,
         cmap_by_code,
         width_acc,
         kerning_acc
       ) do
    if Unicode.variation_selector_codepoint?(selector_codepoint) and is_map(cmap_non_default_uvs) do
      case Map.get(cmap_non_default_uvs, {base_codepoint, selector_codepoint}) do
        glyph_id when is_integer(glyph_id) and glyph_id >= 0 ->
          glyph_width = glyph_width_for_id(advance_widths, glyph_id)

          do_variation_aware_width_units(
            rest,
            cmap_non_default_uvs,
            advance_widths,
            cmap_by_code,
            width_acc + glyph_width,
            [base_codepoint | kerning_acc]
          )

        _ ->
          {next_width_acc, next_kerning_acc} =
            add_codepoint_width_and_kerning(
              base_codepoint,
              advance_widths,
              cmap_by_code,
              width_acc,
              kerning_acc
            )

          do_variation_aware_width_units(
            [selector_codepoint | rest],
            cmap_non_default_uvs,
            advance_widths,
            cmap_by_code,
            next_width_acc,
            next_kerning_acc
          )
      end
    else
      {next_width_acc, next_kerning_acc} =
        add_codepoint_width_and_kerning(
          base_codepoint,
          advance_widths,
          cmap_by_code,
          width_acc,
          kerning_acc
        )

      do_variation_aware_width_units(
        [selector_codepoint | rest],
        cmap_non_default_uvs,
        advance_widths,
        cmap_by_code,
        next_width_acc,
        next_kerning_acc
      )
    end
  end

  defp do_variation_aware_width_units(
         [codepoint | rest],
         cmap_non_default_uvs,
         advance_widths,
         cmap_by_code,
         width_acc,
         kerning_acc
       ) do
    {next_width_acc, next_kerning_acc} =
      add_codepoint_width_and_kerning(
        codepoint,
        advance_widths,
        cmap_by_code,
        width_acc,
        kerning_acc
      )

    do_variation_aware_width_units(
      rest,
      cmap_non_default_uvs,
      advance_widths,
      cmap_by_code,
      next_width_acc,
      next_kerning_acc
    )
  end

  defp do_variation_aware_width_units(
         [],
         _cmap_non_default_uvs,
         _advance_widths,
         _cmap_by_code,
         width_acc,
         kerning_acc
       ) do
    {width_acc, Enum.reverse(kerning_acc)}
  end

  defp add_codepoint_width_and_kerning(
         codepoint,
         advance_widths,
         cmap_by_code,
         width_acc,
         kerning_acc
       ) do
    if Unicode.zero_advance_codepoint?(codepoint) and
         is_nil(mapped_glyph_id_for_codepoint(codepoint, cmap_by_code)) do
      {width_acc, kerning_acc}
    else
      glyph_id = glyph_id_for_codepoint(codepoint, cmap_by_code)
      glyph_width = glyph_width_for_id(advance_widths, glyph_id)

      next_kerning_acc =
        if Unicode.zero_advance_codepoint?(codepoint) do
          kerning_acc
        else
          [codepoint | kerning_acc]
        end

      {width_acc + glyph_width, next_kerning_acc}
    end
  end

  defp mapped_glyph_id_for_codepoint(codepoint, cmap_by_code)
       when is_integer(codepoint) and is_map(cmap_by_code) do
    case Map.get(cmap_by_code, codepoint) do
      glyph_id when is_integer(glyph_id) and glyph_id >= 0 -> glyph_id
      _ -> nil
    end
  end

  defp glyph_id_for_codepoint(codepoint, cmap_by_code) when is_map(cmap_by_code) do
    case Map.get(cmap_by_code, codepoint, if(codepoint <= 255, do: codepoint, else: 0)) do
      glyph_id when is_integer(glyph_id) and glyph_id >= 0 -> glyph_id
      _ -> 0
    end
  end

  defp glyph_width_for_id(advance_widths, glyph_id) do
    case Enum.fetch(advance_widths, glyph_id) do
      {:ok, width} when is_integer(width) and width >= 0 -> width
      _ -> 600
    end
  end

  defp gpos_pair_kerning_units(codepoints, gpos_pair_kerns)
       when is_list(codepoints) and is_map(gpos_pair_kerns) and map_size(gpos_pair_kerns) > 0 do
    codepoints
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn
      [left, right], acc ->
        case Map.get(gpos_pair_kerns, {left, right}) do
          adjustment when is_integer(adjustment) -> acc + adjustment
          _ -> acc
        end

      _other, acc ->
        acc
    end)
  end

  defp gpos_pair_kerning_units(_codepoints, _gpos_pair_kerns), do: 0

  defp gpos_pair_kerning_units_for_pair(left, right, gpos_pair_kerns)
       when is_integer(left) and is_integer(right) and is_map(gpos_pair_kerns) do
    case Map.get(gpos_pair_kerns, {left, right}) do
      adjustment when is_integer(adjustment) -> adjustment
      _ -> 0
    end
  end

  defp gpos_pair_kerning_units_for_pair(_left, _right, _gpos_pair_kerns), do: 0

  defp kerning_codepoint_for_grapheme(grapheme) when is_binary(grapheme) do
    grapheme
    |> String.to_charlist()
    |> Enum.find(fn codepoint ->
      not Unicode.zero_advance_codepoint?(codepoint) and
        not Unicode.variation_selector_codepoint?(codepoint)
    end)
  end
end
