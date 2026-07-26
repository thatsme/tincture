defmodule Tincture.Benchmark.DocumentTest do
  use ExUnit.Case

  alias Tincture.Benchmark.Document

  test "run/1 returns timing and memory metrics for all document scenarios" do
    report = Document.run(iterations: 1, warmup: 0, print: false)

    assert report.meta.iterations == 1
    assert report.meta.warmup == 0

    for scenario <- [:paragraph_flow, :table_heavy, :template_paginated] do
      metrics = Map.fetch!(report.scenarios, scenario)

      assert metrics.iterations == 1
      assert metrics.total_us > 0
      assert metrics.us_per_iter > 0
      assert metrics.ips > 0
      assert is_integer(metrics.memory_bytes_delta)
      assert metrics.memory_bytes_delta >= 0
      assert is_integer(metrics.gpos_guardrail_skips)
      assert metrics.gpos_guardrail_skips >= 0
    end
  end

  test "run/1 validates iteration and warmup values" do
    assert_raise ArgumentError, "iterations must be a positive integer", fn ->
      Document.run(iterations: 0, print: false)
    end

    assert_raise ArgumentError, "warmup must be a non-negative integer", fn ->
      Document.run(iterations: 1, warmup: -1, print: false)
    end
  end

  test "run/1 records gpos guardrail skips from scenario PDF results" do
    scenario_pdf =
      Tincture.new()
      |> Map.put(:embedded_fonts, %{
        "GuardrailedA" => %{ttf_metrics: %{gpos_guardrail_skips: 2}},
        "GuardrailedB" => %{ttf_metrics: %{gpos_guardrail_skips: 1}}
      })

    report =
      Document.run(
        iterations: 1,
        warmup: 0,
        print: false,
        scenarios: [custom: fn -> {scenario_pdf, <<>>} end]
      )

    assert report.scenarios.custom.gpos_guardrail_skips == 3
  end

  test "run/1 validates scenarios option values" do
    assert_raise ArgumentError,
                 "scenarios must be a list of {name_atom, zero_arity_function} tuples",
                 fn ->
                   Document.run(iterations: 1, warmup: 0, print: false, scenarios: [:invalid])
                 end
  end

  test "guardrail_warnings/2 returns warnings when timing or memory exceeds thresholds" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        paragraph_flow: %{
          iterations: 1,
          total_us: 0,
          us_per_iter: 999_999.0,
          ips: 1.0,
          memory_bytes_delta: 100_000_000,
          gpos_guardrail_skips: 2
        }
      }
    }

    warnings =
      Document.guardrail_warnings(report,
        guardrails: %{
          paragraph_flow: %{
            max_us_per_iter: 1_000.0,
            max_memory_bytes_delta: 2_000,
            max_gpos_guardrail_skips: 0
          }
        }
      )

    assert length(warnings) == 3
    assert Enum.any?(warnings, &String.contains?(&1, "paragraph_flow"))
    assert Enum.any?(warnings, &String.contains?(&1, "gpos guardrail skips"))
  end

  test "guardrail_warnings/2 returns empty list when metrics are within thresholds" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        paragraph_flow: %{
          iterations: 1,
          total_us: 0,
          us_per_iter: 100.0,
          ips: 10_000.0,
          memory_bytes_delta: 1_000,
          gpos_guardrail_skips: 0
        }
      }
    }

    assert Document.guardrail_warnings(report,
             guardrails: %{
               paragraph_flow: %{
                 max_us_per_iter: 1_000.0,
                 max_memory_bytes_delta: 2_000,
                 max_gpos_guardrail_skips: 0
               }
             }
           ) == []
  end

  test "assert_guardrails!/2 raises when timing or memory warnings exist" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        paragraph_flow: %{
          iterations: 1,
          total_us: 0,
          us_per_iter: 999_999.0,
          ips: 1.0,
          memory_bytes_delta: 100_000_000,
          gpos_guardrail_skips: 1
        }
      }
    }

    assert_raise RuntimeError, ~r/Benchmark guardrail failures/, fn ->
      Document.assert_guardrails!(report,
        guardrails: %{
          paragraph_flow: %{
            max_us_per_iter: 1_000.0,
            max_memory_bytes_delta: 2_000,
            max_gpos_guardrail_skips: 0
          }
        }
      )
    end
  end

  test "assert_guardrails!/2 returns :ok when metrics are within thresholds" do
    report = %{
      meta: %{iterations: 1, warmup: 0},
      scenarios: %{
        paragraph_flow: %{
          iterations: 1,
          total_us: 0,
          us_per_iter: 100.0,
          ips: 10_000.0,
          memory_bytes_delta: 1_000,
          gpos_guardrail_skips: 0
        }
      }
    }

    assert :ok ==
             Document.assert_guardrails!(report,
               guardrails: %{
                 paragraph_flow: %{
                   max_us_per_iter: 1_000.0,
                   max_memory_bytes_delta: 2_000,
                   max_gpos_guardrail_skips: 0
                 }
               }
             )
  end
end
