defmodule Tincture.BenchmarkScript do
  def run do
    iterations = parse_env_int("EX_GUTEN_BENCH_ITERS", 300)
    warmup = parse_env_int("EX_GUTEN_BENCH_WARMUP", 50)
    speed_factor = parse_env_float("EX_GUTEN_BENCH_SPEED_FACTOR", 1.0)
    enforce? = parse_env_bool("EX_GUTEN_BENCH_ENFORCE", false)

    report =
      Tincture.Benchmark.Typography.run(
        iterations: iterations,
        warmup: warmup,
        print: true
      )

    guardrail_opts = [speed_factor: speed_factor]

    if enforce? do
      Tincture.Benchmark.Typography.assert_guardrails!(report, guardrail_opts)
      IO.puts("")
      IO.puts("Benchmark guardrails: PASS")
      :ok
    else
      report
      |> Tincture.Benchmark.Typography.guardrail_warnings(guardrail_opts)
      |> print_warnings()
    end
  end

  defp parse_env_int(var, default) do
    case System.get_env(var) do
      nil ->
        default

      raw ->
        case Integer.parse(raw) do
          {parsed, ""} when parsed >= 0 -> parsed
          _ -> default
        end
    end
  end

  defp parse_env_float(var, default) do
    case System.get_env(var) do
      nil ->
        default

      raw ->
        case Float.parse(raw) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> default
        end
    end
  end

  defp parse_env_bool(var, default) do
    case System.get_env(var) do
      nil -> default
      "1" -> true
      "true" -> true
      "TRUE" -> true
      "yes" -> true
      "YES" -> true
      "on" -> true
      "ON" -> true
      "0" -> false
      "false" -> false
      "FALSE" -> false
      "no" -> false
      "NO" -> false
      "off" -> false
      "OFF" -> false
      _ -> default
    end
  end

  defp print_warnings([]), do: :ok

  defp print_warnings(warnings) do
    IO.puts("")
    IO.puts("Guardrail warnings:")
    Enum.each(warnings, &IO.puts("  - " <> &1))
    :ok
  end
end

Tincture.BenchmarkScript.run()
