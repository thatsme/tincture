defmodule Tincture.ZlibCanaryTest do
  @moduledoc """
  Whether this machine's zlib is the reference zlib.

  Tincture compresses streams with `:zlib.compress/1`, and the hash locks and
  the committed examples hold the bytes it writes. Those bytes are the same
  wherever OTP links classic zlib: 1.2.11 to 1.3.1 were measured identical,
  on Windows with OTP's own build and on Ubuntu 22.04 and 26.04 with the
  system library, which is what CI runs. zlib-ng, which Fedora 40 and later
  ship as the system zlib, writes different bytes at every level.

  So this compresses one fixed input, the vendored LiberationSans program,
  and asserts the bytes. On a machine with another zlib it is the one test
  that says why every hash lock fails.

  A machine not yet measured, such as macOS with OTP linked against the
  system libz, is checked with two commands from the repository root:

      mix test test/tincture/zlib_canary_test.exs
      mix run -e 'IO.puts(:crypto.hash(:sha256, :zlib.compress(File.read!("examples/fonts/LiberationSans-Regular.ttf"))) |> Base.encode16(case: :lower))'

  The first passes or fails; the second prints the hash to compare with
  `@reference` below.
  """
  use ExUnit.Case, async: true

  @input "examples/fonts/LiberationSans-Regular.ttf"
  @reference "1cd9943f18e6247f367e961f02b4e2356d3d569bb1490418ce9487fdad5032ef"
  @reference_size 211_488

  test "this zlib compresses the reference input to the reference bytes" do
    compressed = @input |> File.read!() |> :zlib.compress()
    digest = :crypto.hash(:sha256, compressed) |> Base.encode16(case: :lower)

    assert {byte_size(compressed), digest} == {@reference_size, @reference}, """
    This zlib is not the reference zlib.

    :zlib.compress/1 wrote #{byte_size(compressed)} bytes, SHA-256 #{digest},
    where classic zlib (1.2.11 to 1.3.1) writes #{@reference_size} bytes,
    SHA-256 #{@reference}.

    Every stream Tincture compresses will differ from the committed bytes, so
    the hash locks fail and `mix examples` rewrites every example; the
    documents themselves are still valid. zlib-ng, the system zlib on Fedora 40
    and later, is the known case. Run the suite, and regenerate examples, with
    an OTP linked against classic zlib, such as CI's Ubuntu runners.
    """
  end
end
