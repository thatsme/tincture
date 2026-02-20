defmodule ExGuten.Benchmark.TypographyTest do
  use ExUnit.Case

  alias ExGuten.Benchmark.Typography

  test "run/1 returns metrics for all benchmark scenarios" do
    report = Typography.run(iterations: 2, warmup: 0, print: false)

    assert report.meta.iterations == 2
    assert report.meta.warmup == 0

    for scenario <- [:greedy, :optimal_quadratic, :optimal_box_glue, :optimal_box_glue_penalties] do
      metrics = Map.fetch!(report.scenarios, scenario)

      assert metrics.iterations == 2
      assert metrics.total_us > 0
      assert metrics.us_per_iter > 0
      assert metrics.ips > 0
    end
  end

  test "optimal scenarios stay within bounded slowdown vs greedy baseline" do
    report = Typography.run(iterations: 2, warmup: 0, print: false)

    greedy_us = report.scenarios.greedy.us_per_iter

    for scenario <- [:optimal_quadratic, :optimal_box_glue, :optimal_box_glue_penalties] do
      optimal_us = report.scenarios[scenario].us_per_iter
      assert optimal_us / greedy_us < 150.0
    end
  end

  test "run/1 validates iteration and warmup values" do
    assert_raise ArgumentError, "iterations must be a positive integer", fn ->
      Typography.run(iterations: 0, print: false)
    end

    assert_raise ArgumentError, "warmup must be a non-negative integer", fn ->
      Typography.run(iterations: 1, warmup: -1, print: false)
    end
  end

  test "run/1 supports custom scenarios" do
    report =
      Typography.run(
        iterations: 1,
        warmup: 0,
        print: false,
        scenarios: [custom: fn -> :ok end]
      )

    assert report.meta.iterations == 1
    assert report.meta.warmup == 0
    assert report.scenarios.custom.iterations == 1
    assert report.scenarios.custom.total_us >= 0
    assert report.scenarios.custom.us_per_iter >= 0
    assert report.scenarios.custom.ips >= 0
  end

  test "run/1 validates scenarios option values" do
    assert_raise ArgumentError,
                 "scenarios must be a list of {name_atom, zero_arity_function} tuples",
                 fn ->
                   Typography.run(iterations: 1, warmup: 0, print: false, scenarios: [:invalid])
                 end
  end

  test "guardrail_warnings/2 returns warnings when scenario metrics exceed thresholds" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        greedy: %{iterations: 1, total_us: 0, us_per_iter: 999_999.0, ips: 1.0}
      }
    }

    warnings =
      Typography.guardrail_warnings(report,
        guardrails: %{greedy: %{max_us_per_iter: 1_000.0}}
      )

    assert length(warnings) == 1
    assert Enum.any?(warnings, &String.contains?(&1, "greedy"))
  end

  test "guardrail_warnings/2 returns empty list when scenario metrics are within thresholds" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        greedy: %{iterations: 1, total_us: 0, us_per_iter: 100.0, ips: 10_000.0}
      }
    }

    assert Typography.guardrail_warnings(report,
             guardrails: %{greedy: %{max_us_per_iter: 1_000.0}}
           ) == []
  end

  test "assert_guardrails!/2 raises when warnings exist" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        greedy: %{iterations: 1, total_us: 0, us_per_iter: 999_999.0, ips: 1.0}
      }
    }

    assert_raise RuntimeError, ~r/Benchmark guardrail failures/, fn ->
      Typography.assert_guardrails!(report, guardrails: %{greedy: %{max_us_per_iter: 1_000.0}})
    end
  end

  test "assert_guardrails!/2 returns :ok when metrics are within thresholds" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        greedy: %{iterations: 1, total_us: 0, us_per_iter: 100.0, ips: 10_000.0}
      }
    }

    assert :ok ==
             Typography.assert_guardrails!(report,
               guardrails: %{greedy: %{max_us_per_iter: 1_000.0}}
             )
  end
end
