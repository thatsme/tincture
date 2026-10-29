defmodule Tincture.Benchmark.TypographyTest do
  use ExUnit.Case

  alias Tincture.Benchmark.Typography

  # Tests tagged :benchmark depend on measured wall-clock values. They are
  # excluded from the default suite (test/test_helper.exs) and run in CI's
  # Benchmark job with `mix test --only benchmark`. Everything else here is
  # structural: the report's shape, option validation, and the guardrail
  # logic on hand-built reports.

  # A real warm-up and enough iterations for a steady state: with
  # iterations: 2, warmup: 0, the greedy baseline is measured cold, and the
  # ratio below divides by a few cold microseconds.
  @measured [iterations: 50, warmup: 50, print: false]

  @scenarios [:greedy, :optimal_quadratic, :optimal_box_glue, :optimal_box_glue_penalties]

  test "run/1 returns the report shape for all benchmark scenarios" do
    report = Typography.run(iterations: 2, warmup: 0, print: false)

    assert report.meta.iterations == 2
    assert report.meta.warmup == 0

    for scenario <- @scenarios do
      metrics = Map.fetch!(report.scenarios, scenario)

      assert metrics.iterations == 2
      assert is_integer(metrics.total_us)
      assert is_float(metrics.us_per_iter)
      assert is_float(metrics.ips)
    end
  end

  @tag :benchmark
  test "run/1 measures a positive time for every scenario" do
    report = Typography.run(@measured)

    for scenario <- @scenarios do
      metrics = Map.fetch!(report.scenarios, scenario)

      assert metrics.total_us > 0
      assert metrics.us_per_iter > 0
      assert metrics.ips > 0
    end
  end

  # Each us_per_iter is a mean over 50 iterations after a warm-up of 50. The
  # ratio measured about 100: 73 to 119 with nothing else running, up to 197
  # beside a parallel test run, and 106 in CI. The limit of 300 therefore fails
  # when an optimal breaker becomes about three times slower relative to
  # greedy: a real regression, not noise on a shared runner.
  @tag :benchmark
  test "optimal scenarios stay within bounded slowdown vs greedy baseline" do
    report = Typography.run(@measured)

    greedy_us = report.scenarios.greedy.us_per_iter

    # Printed so that the Benchmark job's log records the margin, not only
    # whether the threshold held.
    IO.puts("greedy: #{Float.round(greedy_us, 1)} us/iter")

    for scenario <- [:optimal_quadratic, :optimal_box_glue, :optimal_box_glue_penalties] do
      optimal_us = report.scenarios[scenario].us_per_iter
      IO.puts("#{scenario} / greedy: #{Float.round(optimal_us / greedy_us, 1)}")
      assert optimal_us / greedy_us < 300.0
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
    assert is_integer(report.scenarios.custom.total_us)
    assert is_float(report.scenarios.custom.us_per_iter)
    assert is_float(report.scenarios.custom.ips)
  end

  @tag :benchmark
  test "a custom scenario's measured times are non-negative" do
    report =
      Typography.run(
        iterations: 1,
        warmup: 0,
        print: false,
        scenarios: [custom: fn -> :ok end]
      )

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
