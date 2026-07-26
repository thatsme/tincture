defmodule Tincture.Benchmark.Document do
  @moduledoc false

  alias Tincture.PDF
  alias Tincture.Layout.Table
  alias Tincture.Layout.Template
  alias Tincture.Typography.RichText

  @default_guardrails %{
    paragraph_flow: %{
      max_us_per_iter: 80_000.0,
      max_memory_bytes_delta: 20_000_000,
      max_gpos_guardrail_skips: 0
    },
    table_heavy: %{
      max_us_per_iter: 120_000.0,
      max_memory_bytes_delta: 30_000_000,
      max_gpos_guardrail_skips: 0
    },
    template_paginated: %{
      max_us_per_iter: 140_000.0,
      max_memory_bytes_delta: 40_000_000,
      max_gpos_guardrail_skips: 0
    }
  }

  @type metrics :: %{
          iterations: pos_integer(),
          total_us: integer(),
          us_per_iter: float(),
          ips: float(),
          memory_bytes_delta: non_neg_integer(),
          gpos_guardrail_skips: non_neg_integer()
        }

  @type report :: %{
          meta: %{iterations: pos_integer(), warmup: non_neg_integer()},
          scenarios: %{atom() => metrics()}
        }

  @spec run(keyword()) :: report()
  def run(opts \\ []) when is_list(opts) do
    iterations = normalize_iterations(Keyword.get(opts, :iterations, 30))
    warmup = normalize_warmup(Keyword.get(opts, :warmup, 5))
    print? = Keyword.get(opts, :print, true) == true

    scenarios =
      opts
      |> Keyword.get(:scenarios, default_scenarios())
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
    IO.puts("Document benchmark")
    IO.puts("iterations=#{meta.iterations} warmup=#{meta.warmup}")
    IO.puts("")

    scenarios
    |> Enum.sort_by(fn {_name, metrics} -> metrics.us_per_iter end)
    |> Enum.each(fn {name, metrics} ->
      IO.puts(
        "#{name}: #{fmt(metrics.us_per_iter)} us/iter | #{fmt(metrics.ips)} iter/s | " <>
          "mem +#{metrics.memory_bytes_delta} B | gpos-skip #{metrics.gpos_guardrail_skips}"
      )
    end)

    :ok
  end

  @spec guardrail_warnings(report(), keyword()) :: [String.t()]
  def guardrail_warnings(%{scenarios: scenarios}, opts \\ []) do
    guardrails = Keyword.get(opts, :guardrails, @default_guardrails)
    speed_factor = normalize_factor(Keyword.get(opts, :speed_factor, 1.0), :speed_factor)
    memory_factor = normalize_factor(Keyword.get(opts, :memory_factor, 1.0), :memory_factor)

    scenarios
    |> Enum.flat_map(fn {name, metrics} ->
      case Map.get(guardrails, name) do
        %{max_us_per_iter: max_us_per_iter, max_memory_bytes_delta: max_mem} = scenario_guardrails
        when is_number(max_us_per_iter) and is_number(max_mem) ->
          timing_threshold = max_us_per_iter * speed_factor
          memory_threshold = trunc(max_mem * memory_factor)
          gpos_guardrail_skip_threshold = Map.get(scenario_guardrails, :max_gpos_guardrail_skips)
          gpos_guardrail_skips = Map.get(metrics, :gpos_guardrail_skips, 0)

          []
          |> maybe_warn(
            metrics.us_per_iter > timing_threshold,
            "#{name}: us/iter #{fmt(metrics.us_per_iter)} exceeds guardrail #{fmt(timing_threshold)}"
          )
          |> maybe_warn(
            metrics.memory_bytes_delta > memory_threshold,
            "#{name}: memory delta #{metrics.memory_bytes_delta} exceeds guardrail #{memory_threshold}"
          )
          |> maybe_warn(
            is_integer(gpos_guardrail_skip_threshold) and gpos_guardrail_skip_threshold >= 0 and
              gpos_guardrail_skips > gpos_guardrail_skip_threshold,
            "#{name}: gpos guardrail skips #{gpos_guardrail_skips} exceeds guardrail #{gpos_guardrail_skip_threshold}"
          )

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
    :erlang.garbage_collect()
    before_mem = :erlang.memory(:total)

    {total_us, gpos_guardrail_skips} =
      :timer.tc(fn -> iteration_run(scenario_fun, iterations) end)

    :erlang.garbage_collect()
    after_mem = :erlang.memory(:total)

    us_per_iter = total_us / (iterations * 1.0)
    ips = if us_per_iter > 0.0, do: 1_000_000.0 / us_per_iter, else: 0.0

    memory_bytes_delta =
      case after_mem - before_mem do
        diff when diff < 0 -> 0
        diff -> diff
      end

    {name,
     %{
       iterations: iterations,
       total_us: total_us,
       us_per_iter: us_per_iter,
       ips: ips,
       memory_bytes_delta: memory_bytes_delta,
       gpos_guardrail_skips: gpos_guardrail_skips
     }}
  end

  defp default_scenarios do
    [
      {:paragraph_flow, fn -> run_paragraph_flow() end},
      {:table_heavy, fn -> run_table_heavy() end},
      {:template_paginated, fn -> run_template_paginated() end}
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

  defp normalize_scenarios(_scenarios),
    do: raise(ArgumentError, "scenarios must be a list")

  defp run_paragraph_flow do
    rich =
      RichText.from_plain(
        Enum.map_join(1..90, " ", fn idx -> "paragraph_token_#{idx}" end),
        font: "Courier",
        size: 10
      )

    Enum.reduce(1..3, Tincture.new(), fn idx, pdf ->
      page_pdf = if idx == 1, do: pdf, else: Tincture.add_page(pdf)

      Tincture.text_paragraph(page_pdf, 50, 740, rich, 500,
        align: :justified,
        line_break: :greedy,
        justify_max_space_multiplier: 2.0,
        justify_min_space_multiplier: 0.8,
        line_height: 13
      )
    end)
    |> Tincture.export()
  end

  defp run_table_heavy do
    rows =
      [
        ["Item", "Qty", "Unit", "Total"]
      ] ++
        Enum.map(1..80, fn idx ->
          ["Line #{idx}", Integer.to_string(rem(idx, 9) + 1), "$#{idx}.00", "$#{idx * 3}.00"]
        end)

    Enum.reduce(1..5, Tincture.new(), fn idx, pdf ->
      page_pdf = if idx == 1, do: pdf, else: Tincture.add_page(pdf)

      {next_pdf, _result} =
        Table.render(page_pdf, 40, 740, :auto, rows,
          header_rows: 1,
          font: "Helvetica",
          header_font: "Helvetica-Bold",
          font_size: 9,
          padding: 3,
          table_width: 520
        )

      next_pdf
    end)
    |> Tincture.export()
  end

  defp run_template_paginated do
    text = Enum.map_join(1..180, " ", fn idx -> "flow#{idx}" end)
    rich = RichText.from_plain(text, font: "Courier", size: 10)

    template =
      Template.new(page_size: :letter, margins: {50, 50, 50, 50}, columns: 2, gutter: 20)
      |> Template.with_header("Bench {page}/{total}", font: "Helvetica-Bold", size: 12)
      |> Template.with_footer("p.{page}", font: "Helvetica", size: 10)

    {pdf, _result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Template.render_document(template, rich,
        page_number_start: 1,
        page_total: 4,
        max_pages: 4,
        align: :justified,
        line_break: :greedy,
        line_height: 13
      )

    Tincture.export(pdf)
  end

  defp warmup_run(_fun, 0), do: :ok

  defp warmup_run(fun, warmup) do
    Enum.each(1..warmup, fn _ -> fun.() end)
    :ok
  end

  defp iteration_run(fun, iterations) do
    Enum.reduce(1..iterations, 0, fn _, acc ->
      acc + scenario_gpos_guardrail_skips(fun.())
    end)
  end

  defp scenario_gpos_guardrail_skips(%PDF{} = pdf), do: gpos_guardrail_skips_from_pdf(pdf)

  defp scenario_gpos_guardrail_skips({%PDF{} = pdf, _artifact}),
    do: gpos_guardrail_skips_from_pdf(pdf)

  defp scenario_gpos_guardrail_skips(_scenario_result), do: 0

  defp gpos_guardrail_skips_from_pdf(%PDF{embedded_fonts: embedded_fonts})
       when is_map(embedded_fonts) do
    Enum.reduce(embedded_fonts, 0, fn
      {_font_name, %{ttf_metrics: %{gpos_guardrail_skips: skips}}}, acc
      when is_integer(skips) and skips >= 0 ->
        acc + skips

      _entry, acc ->
        acc
    end)
  end

  defp gpos_guardrail_skips_from_pdf(%PDF{}), do: 0

  defp normalize_iterations(value) when is_integer(value) and value > 0, do: value

  defp normalize_iterations(_value),
    do: raise(ArgumentError, "iterations must be a positive integer")

  defp normalize_warmup(value) when is_integer(value) and value >= 0, do: value
  defp normalize_warmup(_value), do: raise(ArgumentError, "warmup must be a non-negative integer")

  defp normalize_factor(value, _field) when is_number(value) and value > 0, do: value * 1.0
  defp normalize_factor(_value, field), do: raise(ArgumentError, "#{field} must be > 0")

  defp maybe_warn(warnings, true, message), do: warnings ++ [message]
  defp maybe_warn(warnings, false, _message), do: warnings

  defp fmt(value) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp format_warnings(warnings) do
    Enum.map_join(warnings, "\n", &("  - " <> &1))
  end
end
