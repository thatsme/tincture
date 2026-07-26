defmodule Tincture.Font.Context do
  @moduledoc """
  A measurement context — how wide a string will be, in any font a document knows.

  `Tincture.Font.text_width/3` is pure, and can only resolve the standard 14
  fonts and AFM files on disk. An embedded TrueType font has no AFM: its
  metrics are parsed out of the file at registration time and live on the
  `t:Tincture.PDF.t/0` struct. So a pure function cannot measure one, and for a
  long time the layout and typography layer — which measured through
  `text_width/3` — simply raised `unknown font` for every embedded font.

  A context closes that gap. It carries the embedded metrics alongside the
  static ones, so anything holding a document can measure any font that
  document can draw:

      context = Context.from_pdf(pdf)
      Context.text_width(context, "Body", 11, "Hello")

  Callers that already have a `%Tincture.PDF{}` — `Tincture.text_paragraph/6`,
  `Tincture.Layout.Table.render/6`, `Tincture.Layout.Box.flow_text/7` — build
  one themselves, so using an embedded font for layout needs nothing extra.
  Build one by hand only when measuring outside a document, or when
  constructing a `t:Tincture.Typography.RichText.t/0` up front.

  ## What it measures

  For an embedded font: per-glyph advance widths from `hmtx`, resolved through
  `cmap`, scaled by the font's units-per-em, with GPOS pair kerning applied and
  Unicode variation sequences honoured. That is the same arithmetic the drawing
  path uses, so a measured width matches what is actually rendered.

  For everything else it defers to `Tincture.Font.text_width/3`.

  ## Name precedence

  A name registered as an embedded font and also naming a standard font
  resolves to the *standard* metrics, which is what the pre-existing drawing
  path did. Registering a TTF as `"Helvetica"` is therefore not a way to
  override the built-in metrics.
  """

  alias Tincture.Font
  alias Tincture.Unicode

  # What an unmeasurable font is assumed to advance per character, as a
  # fraction of the point size. Only reachable with `on_unknown: :estimate`.
  @estimated_advance_ratio 0.6

  # `hmtx` is allowed to be shorter than the glyph count - trailing glyphs
  # inherit the last advance. A glyph past the end of a table we could not read
  # at all falls back to this rather than collapsing to zero width.
  @missing_glyph_width 600

  defstruct embedded: %{}

  @type t :: %__MODULE__{embedded: %{optional(String.t()) => map()}}

  @doc """
  An empty context, resolving only the standard 14 fonts and AFM files.

  Equivalent to measuring through `Tincture.Font.text_width/3` directly.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Build a context from a document, carrying every font registered on it.
  """
  @spec from_pdf(map()) :: t()
  def from_pdf(%{embedded_fonts: embedded}) when is_map(embedded) do
    %__MODULE__{embedded: embedded}
  end

  def from_pdf(_pdf), do: new()

  @doc """
  Whether this context can measure the given font without falling back.
  """
  @spec measurable?(t(), String.t()) :: boolean()
  def measurable?(%__MODULE__{} = context, font_name) when is_binary(font_name) do
    Font.font_available?(font_name) or match?({:ok, _}, embedded_metrics(context, font_name))
  end

  @doc """
  The width of `text` in `font_name` at `size`, in points.

  ## Options

    * `:on_unknown` — what to do with a font this context cannot resolve.
      `:raise` (the default) lets `Tincture.Font.text_width/3` raise, which
      catches a mistyped font name during layout. `:estimate` returns a rough
      width from the point size instead, which is what the drawing path needs:
      `Tincture.set_font/3` does not validate, so a document can already be
      drawing with a font nothing knows about, and a raise there would turn a
      cosmetic problem into a crash.
  """
  @spec text_width(t(), String.t(), number(), String.t(), keyword()) :: float()
  def text_width(context, font_name, size, text, opts \\ [])

  def text_width(%__MODULE__{} = context, font_name, size, text, opts)
      when is_binary(font_name) and is_number(size) and size > 0 and is_binary(text) and
             is_list(opts) do
    if Font.font_available?(font_name) do
      Font.text_width(font_name, size, text)
    else
      measure_embedded(context, font_name, size, text, Keyword.get(opts, :on_unknown, :raise))
    end
  end

  @doc """
  Measure `text`, reporting whether the font could actually be resolved.

  Returns `{:ok, width}` when the width is real, and `{:unresolved, estimate}`
  when this context has never heard of the font — carrying a rough width from
  the point size so a caller can carry on and decide later.

  This exists because rich text is measured when it is built, which may be
  before the document it will be drawn into is known. An embedded font is
  unresolvable at that moment but perfectly resolvable at layout time, and is
  indistinguishable from a typo until then. Callers use this to hold the
  question open rather than guessing, and
  `Tincture.Typography.RichText.remeasure/2` closes it.
  """
  @spec measure(t(), String.t(), number(), String.t()) ::
          {:ok, float()} | {:unresolved, float()}
  def measure(%__MODULE__{} = context, font_name, size, text)
      when is_binary(font_name) and is_number(size) and size > 0 and is_binary(text) do
    if Font.font_available?(font_name) or match?({:ok, _}, embedded_metrics(context, font_name)) do
      {:ok, text_width(context, font_name, size, text)}
    else
      {:unresolved, String.length(text) * size * @estimated_advance_ratio}
    end
  end

  defp measure_embedded(context, font_name, size, text, on_unknown) do
    case embedded_metrics(context, font_name) do
      {:ok, ttf_metrics} ->
        embedded_text_width(ttf_metrics, size, text)

      :error when on_unknown == :estimate ->
        String.length(text) * size * @estimated_advance_ratio

      :error ->
        # Deliberately raised by Font rather than here, so an unknown font
        # reports identically whether or not a context was involved.
        Font.text_width(font_name, size, text)
    end
  end

  defp embedded_metrics(%__MODULE__{embedded: embedded}, font_name) do
    case Map.get(embedded, font_name) do
      %{ttf_metrics: %{advance_widths: widths, units_per_em: upem} = ttf_metrics}
      when is_list(widths) and is_integer(upem) and upem > 0 ->
        {:ok, ttf_metrics}

      _other ->
        :error
    end
  end

  defp embedded_text_width(ttf_metrics, size, text) do
    %{advance_widths: advance_widths, units_per_em: units_per_em} = ttf_metrics
    cmap_by_code = Map.get(ttf_metrics, :cmap_by_code, %{})
    gpos_pair_kerns = Map.get(ttf_metrics, :gpos_pair_kerns, %{})
    codepoints = String.to_charlist(text)

    {base_units, kerning_codepoints} =
      variation_aware_width_units(codepoints, ttf_metrics, advance_widths, cmap_by_code)

    kerning_units = total_pair_kerning_units(kerning_codepoints, gpos_pair_kerns)
    units = max(base_units + kerning_units, 0)

    units * size / units_per_em
  end

  @doc """
  The GPOS kerning adjustment between two codepoints, in font design units.

  Exposed because the drawing path positions each grapheme individually when
  kerning is on, and so needs the adjustment for one pair at a time rather than
  the total across a string.
  """
  @spec pair_kerning_units(integer() | nil, integer() | nil, map()) :: integer()
  def pair_kerning_units(left, right, gpos_pair_kerns)
      when is_integer(left) and is_integer(right) and is_map(gpos_pair_kerns) do
    case Map.get(gpos_pair_kerns, {left, right}) do
      adjustment when is_integer(adjustment) -> adjustment
      _other -> 0
    end
  end

  def pair_kerning_units(_left, _right, _gpos_pair_kerns), do: 0

  @doc """
  The codepoint within a grapheme that participates in kerning.

  A grapheme cluster can carry combining marks and variation selectors, none of
  which take part in a kerning pair. This picks the base character.
  """
  @spec kerning_codepoint(String.t()) :: integer() | nil
  def kerning_codepoint(grapheme) when is_binary(grapheme) do
    grapheme
    |> String.to_charlist()
    |> Enum.find(fn codepoint ->
      not Unicode.zero_advance_codepoint?(codepoint) and
        not Unicode.variation_selector_codepoint?(codepoint)
    end)
  end

  defp total_pair_kerning_units(codepoints, gpos_pair_kerns)
       when is_list(codepoints) and is_map(gpos_pair_kerns) and map_size(gpos_pair_kerns) > 0 do
    codepoints
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn
      [left, right], acc -> acc + pair_kerning_units(left, right, gpos_pair_kerns)
      _other, acc -> acc
    end)
  end

  defp total_pair_kerning_units(_codepoints, _gpos_pair_kerns), do: 0

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

        _other ->
          consume_base_codepoint(
            [base_codepoint, selector_codepoint | rest],
            cmap_non_default_uvs,
            advance_widths,
            cmap_by_code,
            width_acc,
            kerning_acc
          )
      end
    else
      consume_base_codepoint(
        [base_codepoint, selector_codepoint | rest],
        cmap_non_default_uvs,
        advance_widths,
        cmap_by_code,
        width_acc,
        kerning_acc
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

  # The pair was not a variation sequence after all, so the base codepoint is
  # measured on its own and the second codepoint goes back on the list to be
  # considered as a base in its own right.
  defp consume_base_codepoint(
         [base_codepoint | rest],
         cmap_non_default_uvs,
         advance_widths,
         cmap_by_code,
         width_acc,
         kerning_acc
       ) do
    {next_width_acc, next_kerning_acc} =
      add_codepoint_width_and_kerning(
        base_codepoint,
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
      _other -> nil
    end
  end

  defp glyph_id_for_codepoint(codepoint, cmap_by_code) when is_map(cmap_by_code) do
    case Map.get(cmap_by_code, codepoint, if(codepoint <= 255, do: codepoint, else: 0)) do
      glyph_id when is_integer(glyph_id) and glyph_id >= 0 -> glyph_id
      _other -> 0
    end
  end

  defp glyph_width_for_id(advance_widths, glyph_id) do
    case Enum.fetch(advance_widths, glyph_id) do
      {:ok, width} when is_integer(width) and width >= 0 -> width
      _other -> @missing_glyph_width
    end
  end
end
