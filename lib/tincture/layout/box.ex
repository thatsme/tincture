defmodule Tincture.Layout.Box do
  @moduledoc false

  alias Tincture.PDF
  alias Tincture.Typography
  alias Tincture.Typography.LayoutResult
  alias Tincture.Typography.Line
  alias Tincture.Typography.RichText
  alias Tincture.Typography.RichText.Break
  alias Tincture.Typography.RichText.Run
  alias Tincture.Typography.RichText.Space
  alias Tincture.Typography.RichText.Word

  @type option :: Typography.option() | {:rotate, number()}
  @type box :: {number(), number(), number(), number()}

  defmodule FlowResult do
    @moduledoc false

    @type t :: %__MODULE__{
            box_results: [LayoutResult.t()],
            boxes_used: non_neg_integer(),
            overflow?: boolean(),
            spill_text: String.t()
          }

    defstruct box_results: [],
              boxes_used: 0,
              overflow?: false,
              spill_text: ""
  end

  @spec flow_text(PDF.t(), number(), number(), number(), number(), RichText.t(), [option()]) ::
          {PDF.t(), LayoutResult.t()}
  def flow_text(%PDF{} = pdf, x, y, width, height, %RichText{} = rich_text, opts \\ [])
      when is_number(x) and is_number(y) and is_number(width) and width > 0 and is_number(height) and
             height > 0 and is_list(opts) do
    rotate = Keyword.get(opts, :rotate)

    if not is_nil(rotate) and not is_number(rotate) do
      raise ArgumentError, "rotate option must be a number of degrees"
    end

    layout_opts = Keyword.drop(opts, [:rotate])
    line_height = resolve_line_height(rich_text, layout_opts)
    max_lines = floor(height / line_height)

    result =
      if max_lines < 1 do
        spill = Typography.layout_paragraph(rich_text, width, layout_opts)

        %LayoutResult{
          lines: [],
          spill_lines: spill,
          spill_text: Enum.map_join(spill, "\n", & &1.text),
          overflow?: spill != []
        }
      else
        Typography.layout_paragraph_with_spill(rich_text, width, max_lines, layout_opts)
      end

    rendered_pdf = render_lines(pdf, x, y, result.lines, rotate)
    {rendered_pdf, result}
  end

  @spec flow_across_boxes(PDF.t(), RichText.t(), [box()], [option()]) :: {PDF.t(), FlowResult.t()}
  def flow_across_boxes(%PDF{} = pdf, %RichText{} = rich_text, boxes, opts \\ [])
      when is_list(boxes) and is_list(opts) do
    {final_pdf, final_rich, box_results, boxes_used} =
      Enum.reduce_while(boxes, {pdf, rich_text, [], 0}, fn box,
                                                           {acc_pdf, current_rich, results, used} ->
        if rich_blank?(current_rich) do
          {:halt, {acc_pdf, current_rich, results, used}}
        else
          {x, y, width, height} = validate_box(box)
          {next_pdf, result} = flow_text(acc_pdf, x, y, width, height, current_rich, opts)

          next_results = results ++ [result]
          next_used = used + 1

          if result.overflow? do
            next_rich = rich_from_spill_lines(result.spill_lines)
            {:cont, {next_pdf, next_rich, next_results, next_used}}
          else
            {:halt, {next_pdf, empty_rich_text(), next_results, next_used}}
          end
        end
      end)

    spill_text = rich_to_text(final_rich)

    flow_result = %FlowResult{
      box_results: box_results,
      boxes_used: boxes_used,
      overflow?: spill_text != "",
      spill_text: spill_text
    }

    {final_pdf, flow_result}
  end

  defp resolve_line_height(%RichText{} = rich_text, opts) do
    case Keyword.get(opts, :line_height) do
      value when is_number(value) and value > 0 ->
        value * 1.0

      nil ->
        rich_text
        |> max_run_size()
        |> Kernel.*(1.2)

      _ ->
        raise ArgumentError, "line_height must be a positive number"
    end
  end

  defp max_run_size(%RichText{} = rich_text) do
    max_size =
      Enum.reduce(rich_text.runs, 0, fn run, acc ->
        max(acc, Map.get(run, :size, 0))
      end)

    if max_size > 0, do: max_size, else: 12
  end

  defp render_lines(pdf, base_x, base_y, lines, rotate) do
    Enum.reduce(lines, pdf, fn %Line{} = line, acc_pdf ->
      render_line(acc_pdf, base_x + line.x, base_y + line.y, line.tokens, rotate)
    end)
  end

  defp render_line(pdf, start_x, line_y, tokens, rotate) do
    {next_pdf, _cursor_x} =
      Enum.reduce(tokens, {pdf, start_x * 1.0}, fn token, {acc_pdf, cursor_x} ->
        render_token(token, acc_pdf, cursor_x, line_y * 1.0, rotate)
      end)

    next_pdf
  end

  defp render_token(%Word{} = word, pdf, cursor_x, line_y, rotate) do
    next_pdf =
      pdf
      |> Tincture.set_font(word.font, word.size)
      |> then(fn doc ->
        case rotate do
          degrees when is_number(degrees) ->
            Tincture.text_at_rotated(doc, cursor_x, line_y, degrees, word.text)

          _ ->
            Tincture.text_at(doc, cursor_x, line_y, word.text)
        end
      end)

    {next_pdf, cursor_x + word.width}
  end

  defp render_token(%Space{} = space, pdf, cursor_x, _line_y, _rotate) do
    {pdf, cursor_x + space.width}
  end

  defp render_token(%Break{}, pdf, cursor_x, _line_y, _rotate) do
    {pdf, cursor_x}
  end

  defp validate_box({x, y, width, height})
       when is_number(x) and is_number(y) and is_number(width) and width > 0 and is_number(height) and
              height > 0 do
    {x, y, width, height}
  end

  defp validate_box(other) do
    raise ArgumentError, "invalid box tuple: #{inspect(other)}"
  end

  defp rich_from_spill_lines([]), do: empty_rich_text()

  defp rich_from_spill_lines(lines) do
    last_index = length(lines) - 1

    tokens =
      lines
      |> Enum.with_index()
      |> Enum.flat_map(fn {%Line{} = line, idx} ->
        if idx < last_index do
          line.tokens ++ [%Break{}]
        else
          line.tokens
        end
      end)

    case tokens do
      [] -> empty_rich_text()
      _ -> RichText.from_tokens(tokens)
    end
  end

  defp rich_blank?(%RichText{} = rich) do
    String.trim(rich_to_text(rich)) == ""
  end

  defp rich_to_text(%RichText{} = rich) do
    case rich.tokens do
      [] ->
        Enum.map_join(rich.runs, "", fn %Run{text: text} -> text end)

      tokens ->
        Enum.map_join(tokens, "", fn
          %Break{} -> "\n"
          token -> Map.get(token, :text, "")
        end)
    end
  end

  defp empty_rich_text do
    %RichText{runs: [], tokens: []}
  end
end
