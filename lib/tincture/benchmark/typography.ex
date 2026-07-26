defmodule Tincture.Benchmark.Typography do
  @moduledoc false

  alias Tincture.Typography
  alias Tincture.Typography.RichText

  @default_guardrails %{
    greedy: %{max_us_per_iter: 2_000.0},
    optimal_quadratic: %{max_us_per_iter: 24_000.0},
    optimal_box_glue: %{max_us_per_iter: 24_000.0},
    optimal_box_glue_penalties: %{max_us_per_iter: 24_000.0}
  }

  @type metrics :: %{
          iterations: pos_integer(),
          total_us: integer(),
          us_per_iter: float(),
          ips: float()
        }

  @type report :: %{
          meta: %{iterations: pos_integer(), warmup: non_neg_integer()},
          scenarios: %{atom() => metrics()}
        }

  @spec run(keyword()) :: report()
  def run(opts \\ []) when is_list(opts) do
    iterations = normalize_iterations(Keyword.get(opts, :iterations, 300))
    warmup = normalize_warmup(Keyword.get(opts, :warmup, 50))
    print? = Keyword.get(opts, :print, true) == true

    rich = benchmark_paragraph()
    width = 280

    scenarios =
      opts
      |> Keyword.get(:scenarios, default_scenarios(rich, width))
      |> normalize_scenarios()

    scenario_metrics =
      scenarios
      |> Enum.map(fn {name, scenario_fun} ->
        run_scenario(name, scenario_fun, warmup, iterations)
      end)
      |> Enum.into(%{})

    report = %{
      meta: %{iterations: iterations, warmup: warmup},
      scenarios: scenario_metrics
    }

    if print? do
      print_report(report)
    end

    report
  end

  @spec print_report(report()) :: :ok
  def print_report(%{meta: meta, scenarios: scenarios}) do
    IO.puts("Typography benchmark")
    IO.puts("iterations=#{meta.iterations} warmup=#{meta.warmup}")
    IO.puts("")

    scenarios
    |> Enum.sort_by(fn {_name, metrics} -> metrics.us_per_iter end)
    |> Enum.each(fn {name, metrics} ->
      IO.puts(
        "#{name}: #{format_float(metrics.us_per_iter)} us/iter | #{format_float(metrics.ips)} iter/s"
      )
    end)

    :ok
  end

  @spec guardrail_warnings(report(), keyword()) :: [String.t()]
  def guardrail_warnings(%{scenarios: scenarios}, opts \\ []) do
    guardrails = Keyword.get(opts, :guardrails, @default_guardrails)
    speed_factor = normalize_factor(Keyword.get(opts, :speed_factor, 1.0), :speed_factor)

    scenarios
    |> Enum.flat_map(fn {name, metrics} ->
      case Map.get(guardrails, name) do
        %{max_us_per_iter: max_us_per_iter} when is_number(max_us_per_iter) ->
          threshold = max_us_per_iter * speed_factor

          if metrics.us_per_iter > threshold do
            [
              "#{name}: us/iter #{format_float(metrics.us_per_iter)} exceeds " <>
                "guardrail #{format_float(threshold)}"
            ]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  @spec assert_guardrails!(report(), keyword()) :: :ok
  def assert_guardrails!(report, opts \\ []) do
    case guardrail_warnings(report, opts) do
      [] ->
        :ok

      warnings ->
        raise RuntimeError, "Benchmark guardrail failures:\n" <> format_warnings(warnings)
    end
  end

  defp run_scenario(name, scenario_fun, warmup, iterations) do
    warmup_run(scenario_fun, warmup)
    {total_us, _} = :timer.tc(fn -> iteration_run(scenario_fun, iterations) end)

    us_per_iter = total_us / (iterations * 1.0)
    ips = if us_per_iter > 0.0, do: 1_000_000.0 / us_per_iter, else: 0.0

    {name,
     %{
       iterations: iterations,
       total_us: total_us,
       us_per_iter: us_per_iter,
       ips: ips
     }}
  end

  defp default_scenarios(rich, width) do
    [
      {:greedy,
       fn -> Typography.layout_paragraph(rich, width, line_break: :greedy, align: :justified) end},
      {:optimal_quadratic,
       fn ->
         Typography.layout_paragraph(rich, width,
           line_break: :optimal,
           align: :justified,
           optimal_cost_model: :quadratic
         )
       end},
      {:optimal_box_glue,
       fn ->
         Typography.layout_paragraph(rich, width,
           line_break: :optimal,
           align: :justified,
           optimal_cost_model: :box_glue
         )
       end},
      {:optimal_box_glue_penalties,
       fn ->
         Typography.layout_paragraph(rich, width,
           line_break: :optimal,
           align: :justified,
           optimal_cost_model: :box_glue,
           justify_max_space_multiplier: 2.0,
           justify_min_space_multiplier: 0.75,
           widow_penalty: 1_500,
           orphan_penalty: 1_500,
           hyphen_penalty: 250,
           consecutive_hyphen_penalty: 350,
           fitness_class_penalty: 500
         )
       end}
    ]
  end

  defp normalize_scenarios(scenarios) when is_list(scenarios) do
    Enum.map(scenarios, fn
      {name, scenario_fun} when is_atom(name) and is_function(scenario_fun, 0) ->
        {name, scenario_fun}

      _other ->
        raise ArgumentError,
              "scenarios must be a list of {name_atom, zero_arity_function} tuples"
    end)
  end

  defp normalize_scenarios(_scenarios), do: raise(ArgumentError, "scenarios must be a list")

  defp warmup_run(_fun, 0), do: :ok

  defp warmup_run(fun, warmup) do
    Enum.each(1..warmup, fn _ -> fun.() end)
    :ok
  end

  defp iteration_run(fun, iterations) do
    Enum.each(1..iterations, fn _ -> fun.() end)
    :ok
  end

  defp benchmark_paragraph do
    RichText.from_plain(
      "hyphenation strategy changes can affect global breakpoints and typographic color. " <>
        "This benchmark sentence mixes narrow words, longwordswithoutbreaks, and soft-hyphen-like " <>
        "fragments such as micro-architecture, re-entry, and post-processing to stress layout. " <>
        "We also include repeated tokens aa bb cc dd eeeeee and aa- aa- aaa- aa aa- to exercise " <>
        "widow, orphan, fitness, and consecutive-hyphen penalties over many line candidates.",
      font: "Courier",
      size: 10
    )
  end

  defp normalize_iterations(value) when is_integer(value) and value > 0, do: value

  defp normalize_iterations(_value),
    do: raise(ArgumentError, "iterations must be a positive integer")

  defp normalize_warmup(value) when is_integer(value) and value >= 0, do: value
  defp normalize_warmup(_value), do: raise(ArgumentError, "warmup must be a non-negative integer")

  defp normalize_factor(value, _field) when is_number(value) and value > 0, do: value * 1.0
  defp normalize_factor(_value, field), do: raise(ArgumentError, "#{field} must be > 0")

  defp format_float(value) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp format_warnings(warnings) do
    Enum.map_join(warnings, "\n", &("  - " <> &1))
  end
end
