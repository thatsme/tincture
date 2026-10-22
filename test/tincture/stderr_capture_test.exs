defmodule Tincture.StderrCaptureTest do
  @moduledoc """
  A test module that captures stderr runs synchronously.

  `ExUnit.CaptureIO` on `:stderr` captures the device, which the whole VM
  shares, not the test. In an `async: true` module, a warning printed by a
  test running alongside lands in the capture, and an assertion that nothing
  was printed fails by chance. So every module that captures stderr is
  `async: false`, and this test fails when one is not.
  """
  # Not async: its own examples below match the pattern it checks for.
  use ExUnit.Case, async: false

  @captures_stderr ~r/\b(?:capture_io|with_io)\(\s*:(?:stderr|standard_error)\b/
  @async_true ~r/^\s*use ExUnit\.Case,[^\n]*\basync:\s*true\b/m

  test "every module that captures stderr is async: false" do
    offenders =
      "test/**/*_test.exs"
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        source = File.read!(path)
        Regex.match?(@captures_stderr, source) and Regex.match?(@async_true, source)
      end)

    assert offenders == [],
           "these modules capture stderr but are async: true, so a warning from a " <>
             "test running alongside can land in their capture: #{inspect(offenders)}"
  end

  test "the patterns recognise what they look for" do
    assert Regex.match?(@captures_stderr, "with_io(:stderr, fun)")
    assert Regex.match?(@captures_stderr, "capture_io(:stderr, fn -> :ok end)")
    assert Regex.match?(@captures_stderr, "ExUnit.CaptureIO.capture_io(:standard_error, f)")
    refute Regex.match?(@captures_stderr, "capture_io(fn -> :ok end)")
    assert Regex.match?(@async_true, "  use ExUnit.Case, async: true\n")
    refute Regex.match?(@async_true, "  use ExUnit.Case, async: false\n")
    refute Regex.match?(@async_true, "  use ExUnit.Case\n")
  end
end
