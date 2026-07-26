defmodule Tincture.PaintTest do
  @moduledoc """
  How shapes are painted.

  A PDF path-painting operator also *ends* the path, so a shape can be painted
  exactly once. `rectangle/6`, `circle/5` and `line/6` previously emitted `S`
  unconditionally, which meant a following `fill/1` had no path left to act on
  and silently did nothing — a filled rectangle, the most basic design
  primitive there is, was impossible to draw.
  """
  use ExUnit.Case, async: true

  defp content(pdf) do
    [_, stream] = Regex.run(~r/stream\n(.*?)\nendstream/s, Tincture.export(pdf))
    stream
  end

  describe "paint modes" do
    test "stroke is the default, preserving the original behaviour" do
      assert content(Tincture.rectangle(Tincture.new(), 0, 0, 10, 10)) =~ "re\nS"
    end

    test "fill emits f rather than S" do
      stream = content(Tincture.rectangle(Tincture.new(), 0, 0, 10, 10, :fill))

      assert stream =~ "re\nf"
      refute stream =~ "re\nS"
    end

    test "fill_and_stroke emits B" do
      assert content(Tincture.rectangle(Tincture.new(), 0, 0, 10, 10, :fill_and_stroke)) =~
               "re\nB"
    end

    test "fill_even_odd emits f*" do
      assert content(Tincture.rectangle(Tincture.new(), 0, 0, 10, 10, :fill_even_odd)) =~ "re\nf*"
    end

    test "none ends the path without painting, leaving it to the caller" do
      stream =
        Tincture.new()
        |> Tincture.rectangle(0, 0, 10, 10, :none)
        |> content()

      assert stream =~ "re\nn"
    end

    test "the regression: a filled rectangle actually fills" do
      # Before the fix this emitted `re S f` — the S consumed the path and the
      # f did nothing, so the band was invisible.
      stream =
        Tincture.new()
        |> Tincture.set_fill_color({0.06, 0.35, 0.55})
        |> Tincture.rectangle(0, 700, 595, 96, :fill)
        |> content()

      assert stream =~ "0.06 0.35 0.55 rg"
      assert stream =~ "0 700 595 96 re\nf"
      refute stream =~ "re\nS\nf"
    end
  end

  describe "circle and line take the same modes" do
    test "a filled circle ends with f" do
      assert String.ends_with?(
               content(Tincture.circle(Tincture.new(), 50, 50, 20, :fill)),
               "c\nf"
             )
    end

    test "a circle defaults to stroke" do
      assert String.ends_with?(content(Tincture.circle(Tincture.new(), 50, 50, 20)), "c\nS")
    end

    test "a line defaults to stroke" do
      assert content(Tincture.line(Tincture.new(), 0, 0, 10, 10)) =~ "l\nS"
    end
  end

  describe "validation" do
    test "an unknown paint mode is rejected" do
      assert_raise ArgumentError, ~r/paint must be/, fn ->
        Tincture.rectangle(Tincture.new(), 0, 0, 10, 10, :splatter)
      end
    end
  end
end
