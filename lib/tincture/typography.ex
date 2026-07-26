defmodule Tincture.Typography do
  @moduledoc false

  alias Tincture.Typography.RichText
  alias Tincture.Typography.RichText.Break
  alias Tincture.Typography.RichText.Space

  @type align :: :left | :center | :right | :justified
  @type line_break_mode :: :greedy | :optimal
  @type optimal_cost_model :: :quadratic | :box_glue
  @type option ::
          {:align, align()}
          | {:line_height, number()}
          | {:line_break, line_break_mode()}
          | {:optimal_cost_model, optimal_cost_model()}
          | {:justify_max_space_multiplier, number()}
          | {:justify_min_space_multiplier, number()}
          | {:widow_penalty, number()}
          | {:orphan_penalty, number()}
          | {:hyphen_penalty, number()}
          | {:fitness_class_penalty, number()}
          | {:consecutive_hyphen_penalty, number()}

  defmodule Line do
    @moduledoc false

    @type t :: %__MODULE__{
            text: String.t(),
            tokens: [RichText.token()],
            width: float(),
            x: float(),
            y: float()
          }

    defstruct text: "",
              tokens: [],
              width: 0.0,
              x: 0.0,
              y: 0.0
  end

  defmodule LayoutResult do
    @moduledoc false

    @type t :: %__MODULE__{
            lines: [Line.t()],
            spill_lines: [Line.t()],
            spill_text: String.t(),
            overflow?: boolean()
          }

    defstruct lines: [],
              spill_lines: [],
              spill_text: "",
              overflow?: false
  end

  @spec layout_paragraph(RichText.t(), number(), [option()]) :: [Line.t()]
  def layout_paragraph(%RichText{} = rich, max_width, opts \\ [])
      when is_number(max_width) and max_width > 0 and is_list(opts) do
    align = Keyword.get(opts, :align, :left)
    line_break = normalize_line_break(Keyword.get(opts, :line_break, :greedy))

    justify_space_tuning = %{
      max_multiplier:
        normalize_justify_max_space_multiplier(
          Keyword.get(opts, :justify_max_space_multiplier, :infinity)
        ),
      min_multiplier:
        normalize_justify_min_space_multiplier(
          Keyword.get(opts, :justify_min_space_multiplier, 1.0)
        )
    }

    lines =
      case line_break do
        :greedy -> greedy_lines(rich.tokens, max_width, align, justify_space_tuning)
        :optimal -> optimal_lines(rich.tokens, max_width, align, opts, justify_space_tuning)
      end

    lines =
      case align do
        :justified -> justify_lines(lines, max_width, justify_space_tuning)
        _ -> lines
      end

    place_lines(lines, opts)
  end

  defp normalize_line_break(:greedy), do: :greedy
  defp normalize_line_break(:optimal), do: :optimal

  defp normalize_line_break(_other),
    do: raise(ArgumentError, "line_break must be :greedy or :optimal")

  defp normalize_justify_max_space_multiplier(value)
       when is_number(value) and value >= 1.0,
       do: value * 1.0

  defp normalize_justify_max_space_multiplier(:infinity), do: :infinity

  defp normalize_justify_max_space_multiplier(_other),
    do: raise(ArgumentError, "justify_max_space_multiplier must be >= 1.0")

  defp normalize_justify_min_space_multiplier(value)
       when is_number(value) and value > 0 and value <= 1.0,
       do: value * 1.0

  defp normalize_justify_min_space_multiplier(_other),
    do: raise(ArgumentError, "justify_min_space_multiplier must be > 0 and <= 1.0")

  defp greedy_lines(tokens, max_width, align, justify_space_tuning) do
    {lines, current_tokens, _current_width} =
      Enum.reduce(tokens, {[], [], 0.0}, fn token, {acc_lines, acc_tokens, acc_width} ->
        reduce_token(
          token,
          max_width,
          align,
          justify_space_tuning,
          acc_lines,
          acc_tokens,
          acc_width
        )
      end)

    case emit_line(current_tokens, max_width, align) do
      nil -> lines
      line -> lines ++ [line]
    end
  end

  defp optimal_lines(tokens, max_width, align, opts, justify_space_tuning) do
    penalties = optimal_penalties(opts)

    tokens
    |> split_paragraph_tokens()
    |> Enum.flat_map(fn paragraph_tokens ->
      optimal_paragraph_lines(paragraph_tokens, max_width, align, penalties, justify_space_tuning)
    end)
  end

  defp optimal_penalties(opts) do
    %{
      widow: normalize_penalty(Keyword.get(opts, :widow_penalty, 0), :widow_penalty),
      orphan: normalize_penalty(Keyword.get(opts, :orphan_penalty, 0), :orphan_penalty),
      hyphen: normalize_penalty(Keyword.get(opts, :hyphen_penalty, 0), :hyphen_penalty),
      fitness_class:
        normalize_penalty(Keyword.get(opts, :fitness_class_penalty, 0), :fitness_class_penalty),
      consecutive_hyphen:
        normalize_penalty(
          Keyword.get(opts, :consecutive_hyphen_penalty, 0),
          :consecutive_hyphen_penalty
        ),
      cost_model: normalize_optimal_cost_model(Keyword.get(opts, :optimal_cost_model, :box_glue))
    }
  end

  defp normalize_penalty(value, _field) when is_number(value) and value >= 0, do: value * 1.0
  defp normalize_penalty(_value, field), do: raise(ArgumentError, "#{field} must be >= 0")

  defp normalize_optimal_cost_model(:quadratic), do: :quadratic
  defp normalize_optimal_cost_model(:box_glue), do: :box_glue

  defp normalize_optimal_cost_model(_other),
    do: raise(ArgumentError, "optimal_cost_model must be :quadratic or :box_glue")

  defp split_paragraph_tokens(tokens) do
    {paragraphs_rev, current_rev} =
      Enum.reduce(tokens, {[], []}, fn
        %Break{}, {acc_paragraphs, []} ->
          {acc_paragraphs, []}

        %Break{}, {acc_paragraphs, acc_current} ->
          {[Enum.reverse(acc_current) | acc_paragraphs], []}

        token, {acc_paragraphs, acc_current} ->
          {acc_paragraphs, [token | acc_current]}
      end)

    paragraphs =
      case current_rev do
        [] -> paragraphs_rev
        _ -> [Enum.reverse(current_rev) | paragraphs_rev]
      end

    Enum.reverse(paragraphs)
  end

  defp optimal_paragraph_lines(
         paragraph_tokens,
         max_width,
         align,
         penalties,
         justify_space_tuning
       ) do
    trimmed_paragraph = trim_line_edges(paragraph_tokens)

    cond do
      trimmed_paragraph == [] ->
        []

      has_oversized_non_space_token?(trimmed_paragraph, max_width) ->
        greedy_lines(trimmed_paragraph, max_width, align, justify_space_tuning)

      true ->
        case optimal_spans(trimmed_paragraph, max_width, penalties, align, justify_space_tuning) do
          nil ->
            greedy_lines(trimmed_paragraph, max_width, align, justify_space_tuning)

          spans ->
            Enum.map(spans, fn {start_idx, end_idx} ->
              trimmed_paragraph
              |> Enum.slice(start_idx, end_idx - start_idx)
              |> trim_line_edges()
              |> build_line(max_width, align)
            end)
        end
    end
  end

  defp optimal_spans(tokens, max_width, penalties, align, justify_space_tuning) do
    line_index = build_line_index(tokens)
    n = line_index.n
    fitness_classes = [:none, 0, 1, 2, 3]
    hyphen_states = [false, true]

    base_costs =
      Enum.reduce(fitness_classes, %{}, fn cls, acc ->
        Enum.reduce(hyphen_states, acc, fn prev_hyphen, acc2 ->
          Map.put(acc2, {n, cls, prev_hyphen}, 0.0)
        end)
      end)

    {costs, next_break} =
      Enum.reduce((n - 1)..0//-1, {base_costs, %{}}, fn idx, {cost_acc, next_acc} ->
        start_idx = skip_leading_spaces_index(line_index, idx)

        Enum.reduce(fitness_classes, {cost_acc, next_acc}, fn prev_cls, {cost_acc2, next_acc2} ->
          Enum.reduce(hyphen_states, {cost_acc2, next_acc2}, fn prev_hyphen,
                                                                {cost_acc3, next_acc3} ->
            cond do
              start_idx >= n ->
                {
                  Map.put(cost_acc3, {idx, prev_cls, prev_hyphen}, 0.0),
                  Map.put(next_acc3, {idx, prev_cls, prev_hyphen}, {n, :none, false})
                }

              start_idx > idx ->
                {
                  Map.put(
                    cost_acc3,
                    {idx, prev_cls, prev_hyphen},
                    Map.get(cost_acc3, {start_idx, prev_cls, prev_hyphen}, :infinity)
                  ),
                  Map.put(
                    next_acc3,
                    {idx, prev_cls, prev_hyphen},
                    Map.get(next_acc3, {start_idx, prev_cls, prev_hyphen})
                  )
                }

              true ->
                candidates =
                  Enum.reduce((start_idx + 1)..n, [], fn end_idx, acc ->
                    trimmed_end_idx = trim_trailing_spaces_index(line_index, start_idx, end_idx)

                    cond do
                      trimmed_end_idx <= start_idx ->
                        acc

                      true ->
                        width = range_width(line_index, start_idx, trimmed_end_idx)
                        line_hyphen = line_ends_with_hyphen_index?(line_index, trimmed_end_idx)
                        next_idx = skip_leading_spaces_index(line_index, end_idx)
                        last_line? = next_idx >= n

                        space_count = range_space_count(line_index, start_idx, trimmed_end_idx)

                        space_total_width =
                          range_space_width(line_index, start_idx, trimmed_end_idx)

                        adjustment =
                          line_adjustment_from_space_stats(
                            width,
                            max_width,
                            align,
                            justify_space_tuning,
                            last_line?,
                            space_count,
                            space_total_width
                          )

                        if not adjustment.fits? do
                          acc
                        else
                          adjusted_width = adjustment.adjusted_width
                          line_cls = line_fitness_class(adjusted_width, max_width)

                          case line_break_cost_from_space_stats(
                                 width,
                                 adjusted_width,
                                 max_width,
                                 align,
                                 last_line?,
                                 justify_space_tuning,
                                 penalties.cost_model,
                                 space_count,
                                 space_total_width
                               ) do
                            :infeasible ->
                              acc

                            line_cost ->
                              remaining_cost =
                                Map.get(cost_acc3, {next_idx, line_cls, line_hyphen}, :infinity)

                              if remaining_cost == :infinity do
                                acc
                              else
                                token_count =
                                  range_non_space_count(line_index, start_idx, trimmed_end_idx)

                                base_penalty =
                                  line_cost +
                                    if(next_idx >= n and start_idx > 0 and token_count == 1,
                                      do: penalties.widow,
                                      else: 0.0
                                    ) +
                                    if(start_idx == 0 and next_idx < n and token_count == 1,
                                      do: penalties.orphan,
                                      else: 0.0
                                    ) +
                                    if next_idx < n and line_hyphen,
                                      do: penalties.hyphen,
                                      else: 0.0

                                [
                                  %{
                                    next_idx: next_idx,
                                    line_cls: line_cls,
                                    line_hyphen: line_hyphen,
                                    base_penalty: base_penalty,
                                    remaining_cost: remaining_cost
                                  }
                                  | acc
                                ]
                              end
                          end
                        end
                    end
                  end)

                {best_cost, best_next_idx, best_line_cls, best_line_hyphen} =
                  Enum.reduce(candidates, {:infinity, nil, nil, nil}, fn candidate,
                                                                         {acc_cost, acc_next,
                                                                          acc_cls, acc_hyphen} ->
                    transition_penalty =
                      if prev_cls != :none and abs(prev_cls - candidate.line_cls) > 1,
                        do: penalties.fitness_class,
                        else: 0.0

                    consecutive_hyphen_penalty =
                      if prev_hyphen and candidate.line_hyphen,
                        do: penalties.consecutive_hyphen,
                        else: 0.0

                    total_cost =
                      candidate.base_penalty +
                        candidate.remaining_cost +
                        transition_penalty +
                        consecutive_hyphen_penalty

                    cond do
                      acc_cost == :infinity or total_cost < acc_cost ->
                        {total_cost, candidate.next_idx, candidate.line_cls,
                         candidate.line_hyphen}

                      total_cost == acc_cost and is_integer(acc_next) and
                          candidate.next_idx > acc_next ->
                        {total_cost, candidate.next_idx, candidate.line_cls,
                         candidate.line_hyphen}

                      true ->
                        {acc_cost, acc_next, acc_cls, acc_hyphen}
                    end
                  end)

                {
                  Map.put(cost_acc3, {idx, prev_cls, prev_hyphen}, best_cost),
                  Map.put(
                    next_acc3,
                    {idx, prev_cls, prev_hyphen},
                    {best_next_idx, best_line_cls, best_line_hyphen}
                  )
                }
            end
          end)
        end)
      end)

    _ = costs
    build_spans(tokens, next_break, 0, :none, false, [])
  end

  defp build_line_index(tokens) do
    n = length(tokens)

    {prefix_width_rev, prefix_space_count_rev, prefix_space_width_rev, prefix_non_space_count_rev,
     hyphen_flags_rev, _width, _space_count, _space_width,
     _non_space_count} =
      Enum.reduce(
        tokens,
        {[0.0], [0], [0.0], [0], [], 0.0, 0, 0.0, 0},
        fn token,
           {prefix_width_acc, prefix_space_count_acc, prefix_space_width_acc,
            prefix_non_space_count_acc, hyphen_flags_acc, width_acc, space_count_acc,
            space_width_acc, non_space_count_acc} ->
          token_width = token.width
          is_space = match?(%Space{}, token)

          next_width = width_acc + token_width
          next_space_count = if is_space, do: space_count_acc + 1, else: space_count_acc
          next_space_width = if is_space, do: space_width_acc + token_width, else: space_width_acc

          next_non_space_count =
            if is_space, do: non_space_count_acc, else: non_space_count_acc + 1

          hyphen? =
            case token do
              %Space{} -> false
              _ -> token |> Map.get(:text, "") |> String.ends_with?("-")
            end

          {[next_width | prefix_width_acc], [next_space_count | prefix_space_count_acc],
           [next_space_width | prefix_space_width_acc],
           [next_non_space_count | prefix_non_space_count_acc], [hyphen? | hyphen_flags_acc],
           next_width, next_space_count, next_space_width, next_non_space_count}
        end
      )

    prefix_width = prefix_width_rev |> Enum.reverse() |> List.to_tuple()
    prefix_space_count = prefix_space_count_rev |> Enum.reverse() |> List.to_tuple()
    prefix_space_width = prefix_space_width_rev |> Enum.reverse() |> List.to_tuple()
    prefix_non_space_count = prefix_non_space_count_rev |> Enum.reverse() |> List.to_tuple()
    hyphen_flags = hyphen_flags_rev |> Enum.reverse() |> List.to_tuple()

    prev_non_space_before =
      tokens
      |> Enum.with_index()
      |> Enum.reduce({[-1], -1}, fn {token, idx}, {acc, last_non_space} ->
        next_last_non_space = if match?(%Space{}, token), do: last_non_space, else: idx
        {[next_last_non_space | acc], next_last_non_space}
      end)
      |> elem(0)
      |> Enum.reverse()
      |> List.to_tuple()

    next_non_space =
      tokens
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce({[n], n}, fn {token, idx}, {acc, next_non_space_idx} ->
        next_idx = if match?(%Space{}, token), do: next_non_space_idx, else: idx
        {[next_idx | acc], next_idx}
      end)
      |> elem(0)
      |> List.to_tuple()

    %{
      n: n,
      prefix_width: prefix_width,
      prefix_space_count: prefix_space_count,
      prefix_space_width: prefix_space_width,
      prefix_non_space_count: prefix_non_space_count,
      prev_non_space_before: prev_non_space_before,
      next_non_space: next_non_space,
      hyphen_flags: hyphen_flags
    }
  end

  defp skip_leading_spaces_index(%{next_non_space: next_non_space, n: n}, idx)
       when is_integer(idx) and idx >= 0 and idx <= n do
    elem(next_non_space, idx)
  end

  defp trim_trailing_spaces_index(
         %{prev_non_space_before: prev_non_space_before},
         start_idx,
         end_idx
       ) do
    last_non_space = elem(prev_non_space_before, end_idx)
    if last_non_space < start_idx, do: start_idx, else: last_non_space + 1
  end

  defp line_ends_with_hyphen_index?(%{hyphen_flags: hyphen_flags}, trimmed_end_idx)
       when is_integer(trimmed_end_idx) and trimmed_end_idx > 0 do
    elem(hyphen_flags, trimmed_end_idx - 1)
  end

  defp range_width(%{prefix_width: prefix_width}, start_idx, end_idx) do
    elem(prefix_width, end_idx) - elem(prefix_width, start_idx)
  end

  defp range_space_count(%{prefix_space_count: prefix_space_count}, start_idx, end_idx) do
    elem(prefix_space_count, end_idx) - elem(prefix_space_count, start_idx)
  end

  defp range_space_width(%{prefix_space_width: prefix_space_width}, start_idx, end_idx) do
    elem(prefix_space_width, end_idx) - elem(prefix_space_width, start_idx)
  end

  defp range_non_space_count(
         %{prefix_non_space_count: prefix_non_space_count},
         start_idx,
         end_idx
       ) do
    elem(prefix_non_space_count, end_idx) - elem(prefix_non_space_count, start_idx)
  end

  defp build_spans(tokens, next_break, idx, prev_cls, prev_hyphen, spans_acc) do
    n = length(tokens)
    start_idx = skip_leading_spaces(tokens, idx)

    cond do
      start_idx >= n ->
        Enum.reverse(spans_acc)

      true ->
        case Map.get(next_break, {start_idx, prev_cls, prev_hyphen}) do
          nil ->
            nil

          {end_idx, line_cls, line_hyphen} when is_integer(end_idx) and end_idx > start_idx ->
            build_spans(tokens, next_break, end_idx, line_cls, line_hyphen, [
              {start_idx, end_idx} | spans_acc
            ])

          _ ->
            nil
        end
    end
  end

  defp skip_leading_spaces(tokens, idx) do
    n = length(tokens)

    Enum.reduce_while(idx..n, idx, fn current_idx, _acc ->
      cond do
        current_idx >= n ->
          {:halt, n}

        match?(%Space{}, Enum.at(tokens, current_idx)) ->
          {:cont, current_idx + 1}

        true ->
          {:halt, current_idx}
      end
    end)
  end

  defp has_oversized_non_space_token?(tokens, max_width) do
    Enum.any?(tokens, fn token ->
      not match?(%Space{}, token) and token.width > max_width
    end)
  end

  defp line_fitness_class(width, max_width) when max_width > 0 do
    ratio = (max_width - width) / max_width

    cond do
      ratio < 0.08 -> 0
      ratio < 0.18 -> 1
      ratio < 0.32 -> 2
      true -> 3
    end
  end

  @spec layout_paragraph_with_spill(RichText.t(), number(), pos_integer(), [option()]) ::
          LayoutResult.t()
  def layout_paragraph_with_spill(%RichText{} = rich, max_width, max_lines, opts \\ [])
      when is_number(max_width) and max_width > 0 and is_integer(max_lines) and max_lines > 0 and
             is_list(opts) do
    lines = layout_paragraph(rich, max_width, opts)
    {visible, spill} = Enum.split(lines, max_lines)

    %LayoutResult{
      lines: visible,
      spill_lines: spill,
      spill_text: Enum.map_join(spill, "\n", & &1.text),
      overflow?: spill != []
    }
  end

  defp reduce_token(
         %Break{},
         max_width,
         align,
         _justify_space_tuning,
         acc_lines,
         acc_tokens,
         _acc_width
       ) do
    case emit_line(acc_tokens, max_width, align) do
      nil -> {acc_lines, [], 0.0}
      line -> {acc_lines ++ [line], [], 0.0}
    end
  end

  defp reduce_token(
         %Space{} = token,
         _max_width,
         _align,
         _justify_space_tuning,
         acc_lines,
         [],
         _acc_width
       ) do
    # Skip leading spaces on a new line.
    _ = token
    {acc_lines, [], 0.0}
  end

  defp reduce_token(
         token,
         max_width,
         align,
         justify_space_tuning,
         acc_lines,
         acc_tokens,
         acc_width
       ) do
    token_width = token.width
    candidate_tokens = acc_tokens ++ [token]

    cond do
      acc_tokens == [] and token_width > max_width ->
        # Keep oversized tokens on their own line to preserve content.
        line = build_line([token], max_width, align)
        {acc_lines ++ [line], [], 0.0}

      line_can_fit?(candidate_tokens, max_width, align, justify_space_tuning) ->
        {acc_lines, candidate_tokens, acc_width + token_width}

      true ->
        line = emit_line(acc_tokens, max_width, align)

        case token do
          %Space{} ->
            {acc_lines ++ List.wrap(line), [], 0.0}

          _ ->
            {acc_lines ++ List.wrap(line), [token], token_width}
        end
    end
  end

  defp emit_line(tokens, max_width, align) do
    trimmed = trim_trailing_spaces(tokens)

    case trimmed do
      [] ->
        nil

      _ ->
        build_line(trimmed, max_width, align)
    end
  end

  defp trim_trailing_spaces(tokens) do
    tokens
    |> Enum.reverse()
    |> Enum.drop_while(&match?(%Space{}, &1))
    |> Enum.reverse()
  end

  defp trim_line_edges(tokens) do
    tokens
    |> Enum.drop_while(&match?(%Space{}, &1))
    |> trim_trailing_spaces()
  end

  defp build_line(tokens, max_width, align) do
    width = line_width(tokens)

    text =
      tokens
      |> Enum.map(& &1.text)
      |> Enum.join("")

    %Line{
      text: text,
      tokens: tokens,
      width: width,
      x: line_x(width, max_width, align)
    }
  end

  defp line_width(tokens) do
    Enum.reduce(tokens, 0.0, fn token, acc -> acc + token.width end)
  end

  defp line_x(_width, _max_width, :left), do: 0.0
  defp line_x(_width, _max_width, :justified), do: 0.0
  defp line_x(width, max_width, :center), do: max((max_width - width) / 2, 0.0)
  defp line_x(width, max_width, :right), do: max(max_width - width, 0.0)
  defp line_x(_width, _max_width, _), do: 0.0

  defp justify_lines([] = lines, _max_width, _justify_space_tuning), do: lines

  defp justify_lines(lines, max_width, justify_space_tuning) do
    last_index = length(lines) - 1

    Enum.with_index(lines)
    |> Enum.map(fn {%Line{} = line, idx} ->
      is_last_line = idx == last_index
      space_count = Enum.count(line.tokens, &match?(%Space{}, &1))

      if space_count > 0 do
        adjustment =
          line_adjustment(
            line.tokens,
            line.width,
            max_width,
            :justified,
            justify_space_tuning,
            is_last_line
          )

        applied_delta = adjustment.adjusted_width - line.width
        delta_per_space = applied_delta / space_count

        adjusted_tokens =
          Enum.map(line.tokens, fn
            %Space{} = space ->
              %{space | width: space.width + delta_per_space}

            token ->
              token
          end)

        %{line | tokens: adjusted_tokens, width: line.width + applied_delta, x: 0.0}
      else
        line
      end
    end)
  end

  defp line_can_fit?(tokens, max_width, align, justify_space_tuning) do
    width = line_width(tokens)

    case line_adjustment(tokens, width, max_width, align, justify_space_tuning, false) do
      %{fits?: true} -> true
      _ -> false
    end
  end

  defp line_adjustment(tokens, width, max_width, align, justify_space_tuning, last_line?) do
    {space_count, space_total_width} = line_space_stats(tokens)

    line_adjustment_from_space_stats(
      width,
      max_width,
      align,
      justify_space_tuning,
      last_line?,
      space_count,
      space_total_width
    )
  end

  defp line_adjustment_from_space_stats(
         width,
         max_width,
         align,
         justify_space_tuning,
         last_line?,
         space_count,
         space_total_width
       ) do
    if align != :justified do
      %{fits?: width <= max_width, adjusted_width: width}
    else
      if space_count == 0 do
        %{fits?: width <= max_width, adjusted_width: width}
      else
        max_stretch =
          if last_line? do
            0.0
          else
            case justify_space_tuning.max_multiplier do
              :infinity -> :infinity
              multiplier -> space_total_width * (multiplier - 1.0)
            end
          end

        max_shrink = space_total_width * (1.0 - justify_space_tuning.min_multiplier)
        min_width = width - max_shrink
        fits? = width <= max_width or min_width <= max_width

        adjusted_width =
          if fits? do
            requested_delta = max_width - width
            width + applied_space_delta(requested_delta, max_stretch, max_shrink)
          else
            width
          end

        %{fits?: fits?, adjusted_width: adjusted_width}
      end
    end
  end

  defp applied_space_delta(requested_delta, max_stretch, _max_shrink) when requested_delta >= 0 do
    case max_stretch do
      :infinity -> requested_delta
      stretch when is_number(stretch) -> min(requested_delta, max(stretch, 0.0))
    end
  end

  defp applied_space_delta(requested_delta, _max_stretch, max_shrink) when requested_delta < 0 do
    -min(-requested_delta, max(max_shrink, 0.0))
  end

  defp line_break_cost_from_space_stats(
         _natural_width,
         _adjusted_width,
         _max_width,
         _align,
         true,
         _justify_space_tuning,
         _cost_model,
         _space_count,
         _space_total_width
       ),
       do: 0.0

  defp line_break_cost_from_space_stats(
         _natural_width,
         adjusted_width,
         max_width,
         _align,
         false,
         _justify_space_tuning,
         :quadratic,
         _space_count,
         _space_total_width
       ) do
    slack = max_width - adjusted_width
    slack * slack
  end

  defp line_break_cost_from_space_stats(
         natural_width,
         adjusted_width,
         max_width,
         :justified,
         false,
         justify_space_tuning,
         :box_glue,
         space_count,
         space_total_width
       ) do
    case justified_ratio_from_space_stats(
           natural_width,
           adjusted_width,
           max_width,
           justify_space_tuning,
           space_count,
           space_total_width
         ) do
      :infeasible ->
        :infeasible

      ratio ->
        badness = min(10_000.0, 100.0 * :math.pow(abs(ratio), 3))
        badness * badness
    end
  end

  defp line_break_cost_from_space_stats(
         _natural_width,
         adjusted_width,
         max_width,
         _align,
         false,
         _justify_space_tuning,
         :box_glue,
         _space_count,
         _space_total_width
       ) do
    slack = max_width - adjusted_width
    slack * slack
  end

  defp justified_ratio_from_space_stats(
         natural_width,
         adjusted_width,
         max_width,
         justify_space_tuning,
         space_count,
         space_total_width
       ) do
    epsilon = 1.0e-6

    cond do
      space_count == 0 ->
        if abs(adjusted_width - max_width) <= epsilon, do: 0.0, else: :infeasible

      true ->
        requested_delta = max_width - natural_width

        cond do
          requested_delta > 0 ->
            case justify_space_tuning.max_multiplier do
              :infinity ->
                0.0

              multiplier ->
                max_stretch = space_total_width * (multiplier - 1.0)

                if max_stretch <= epsilon do
                  :infeasible
                else
                  ratio = requested_delta / max_stretch
                  if ratio <= 1.0 + epsilon, do: ratio, else: :infeasible
                end
            end

          requested_delta < 0 ->
            max_shrink = space_total_width * (1.0 - justify_space_tuning.min_multiplier)

            if max_shrink <= epsilon do
              :infeasible
            else
              ratio = requested_delta / max_shrink
              if abs(ratio) <= 1.0 + epsilon, do: ratio, else: :infeasible
            end

          true ->
            0.0
        end
    end
  end

  defp line_space_stats(tokens) do
    Enum.reduce(tokens, {0, 0.0}, fn
      %Space{} = space, {count, acc} -> {count + 1, acc + space.width}
      _token, acc -> acc
    end)
  end

  defp place_lines(lines, opts) do
    line_height = Keyword.get(opts, :line_height)

    case line_height do
      value when is_number(value) and value > 0 ->
        Enum.with_index(lines)
        |> Enum.map(fn {%Line{} = line, idx} ->
          %{line | y: -(idx * value * 1.0)}
        end)

      _ ->
        {positioned, _cursor} =
          Enum.reduce(lines, {[], 0.0}, fn %Line{} = line, {acc, y_cursor} ->
            height = default_line_height(line)
            {acc ++ [%{line | y: y_cursor}], y_cursor - height}
          end)

        positioned
    end
  end

  defp default_line_height(%Line{} = line) do
    max_size =
      line.tokens
      |> Enum.reduce(0, fn token, acc ->
        case token do
          %Break{} -> acc
          %{} -> max(acc, Map.get(token, :size, 0))
        end
      end)

    fallback_size = if max_size > 0, do: max_size, else: 12
    fallback_size * 1.2
  end
end
