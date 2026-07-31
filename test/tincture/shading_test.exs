defmodule Tincture.ShadingTest do
  use ExUnit.Case, async: true

  # Both /ExtGState and /Shading are written inline into the page's resource
  # dictionary rather than as indirect objects, so these assertions read the
  # resource entry and the content stream operator together - the pair is what
  # makes a gradient render, and either alone is silently inert.

  describe "set_alpha/2" do
    test "emits an ExtGState resource and selects it" do
      binary =
        Tincture.new()
        |> Tincture.set_alpha(0.4)
        |> Tincture.rectangle(20, 600, 120, 40, :fill)
        |> Tincture.export()

      assert binary =~ "/ExtGState << /GS0 << /Type /ExtGState /ca 0.4 /CA 0.4 >> >>"
      assert binary =~ "/GS0 gs"
    end

    test "sets fill and stroke alpha separately" do
      binary =
        Tincture.new()
        |> Tincture.set_alpha(fill: 0.25, stroke: 1.0)
        |> Tincture.rectangle(20, 600, 120, 40, :fill_and_stroke)
        |> Tincture.export()

      assert binary =~ "/ca 0.25 /CA 1"
    end

    test "an unspecified channel stays opaque" do
      binary =
        Tincture.new()
        |> Tincture.set_alpha(fill: 0.5)
        |> Tincture.rectangle(20, 600, 120, 40, :fill)
        |> Tincture.export()

      assert binary =~ "/ca 0.5 /CA 1"
    end

    test "identical states share one resource, distinct ones do not" do
      binary =
        Tincture.new()
        |> Tincture.set_alpha(0.5)
        |> Tincture.rectangle(20, 600, 40, 40, :fill)
        |> Tincture.set_alpha(0.5)
        |> Tincture.rectangle(80, 600, 40, 40, :fill)
        |> Tincture.set_alpha(0.9)
        |> Tincture.rectangle(140, 600, 40, 40, :fill)
        |> Tincture.export()

      assert binary =~ "/GS0 << /Type /ExtGState /ca 0.5 /CA 0.5 >>"
      assert binary =~ "/GS1 << /Type /ExtGState /ca 0.9 /CA 0.9 >>"
      refute binary =~ "/GS2"
    end

    test "rejects an alpha outside 0..1" do
      assert_raise FunctionClauseError, fn ->
        Tincture.new() |> Tincture.set_alpha(1.5)
      end
    end
  end

  describe "linear_gradient/7" do
    test "two stops interpolate directly" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(0, 500, 595, 342, [
          {0.0, {0.05, 0.32, 0.55}},
          {1.0, {0.02, 0.06, 0.12}}
        ])
        |> Tincture.export()

      assert binary =~ "/ShadingType 2"
      assert binary =~ "/ColorSpace /DeviceRGB"
      assert binary =~ "/FunctionType 2"
      assert binary =~ "/C0 [0.05 0.32 0.55]"
      assert binary =~ "/C1 [0.02 0.06 0.12]"
      assert binary =~ "/Extend [true true]"
      assert binary =~ "/Sh0 sh"
    end

    test "vertical runs the first stop from the top of the rectangle" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(0, 500, 595, 342, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}])
        |> Tincture.export()

      # y + height down to y: PDF's y axis points up, so the top is the larger
      # coordinate.
      assert binary =~ "/Coords [0 842 0 500]"
    end

    test "horizontal runs left to right" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(40, 700, 515, 8, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}],
          direction: :horizontal
        )
        |> Tincture.export()

      assert binary =~ "/Coords [40 700 555 700]"
    end

    test "an explicit axis is used as given" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 100, 100, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}],
          direction: {10, 20, 30, 40}
        )
        |> Tincture.export()

      assert binary =~ "/Coords [10 20 30 40]"
    end

    test "more than two stops are stitched" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(40, 700, 515, 8, [
          {0.0, {0.85, 0.2, 0.3}},
          {0.5, {0.95, 0.7, 0.2}},
          {1.0, {0.2, 0.55, 0.45}}
        ])
        |> Tincture.export()

      assert binary =~ "/FunctionType 3"
      # One interpolation per adjacent pair, handing over at the interior stop.
      assert binary =~ "/Bounds [0.5]"
      assert binary =~ "/Encode [0 1 0 1]"
      assert binary =~ "/C0 [0.85 0.2 0.3]"
      assert binary =~ "/C1 [0.2 0.55 0.45]"
    end

    test "extend can be turned off" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 100, 100, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}],
          extend: {false, false}
        )
        |> Tincture.export()

      assert binary =~ "/Extend [false false]"
    end

    test "the gradient clips to its rectangle and restores the state" do
      binary =
        Tincture.new()
        |> Tincture.linear_gradient(10, 20, 30, 40, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}])
        |> Tincture.export()

      assert binary =~ "q\n10 20 30 40 re\nW\nn\n/Sh0 sh\nQ\n"
    end
  end

  describe "radial_gradient/7" do
    test "emits a type 3 shading centred in the rectangle" do
      binary =
        Tincture.new()
        |> Tincture.radial_gradient(180, 480, 240, 240, [
          {0.0, {1.0, 0.95, 0.8}},
          {1.0, {0.85, 0.35, 0.1}}
        ])
        |> Tincture.export()

      assert binary =~ "/ShadingType 3"
      # Centre of the rectangle, from radius 0 out to half the longer side.
      assert binary =~ "/Coords [300 600 0 300 600 120]"
    end

    test "centre, radius and inner radius can be given" do
      binary =
        Tincture.new()
        |> Tincture.radial_gradient(0, 0, 100, 100, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}],
          center: {25, 75},
          radius: 60,
          inner_radius: 10
        )
        |> Tincture.export()

      assert binary =~ "/Coords [25 75 10 25 75 60]"
    end
  end

  describe "validation" do
    test "a gradient needs at least two stops" do
      assert_raise ArgumentError, ~r/at least two stops/, fn ->
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 10, 10, [{0.0, {1, 1, 1}}])
      end
    end

    test "offsets must ascend" do
      assert_raise ArgumentError, ~r/must ascend/, fn ->
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 10, 10, [{1.0, {1, 1, 1}}, {0.0, {0, 0, 0}}])
      end
    end

    test "a colour component outside 0..1 is refused" do
      assert_raise ArgumentError, ~r/between 0 and 1/, fn ->
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 10, 10, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 255}}])
      end
    end

    test "a malformed stop is refused" do
      assert_raise ArgumentError, ~r/each gradient stop/, fn ->
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 10, 10, [{0.0, {1, 1, 1}}, {1.0, :black}])
      end
    end

    test "an unknown direction is refused" do
      assert_raise ArgumentError, ~r/unknown gradient direction/, fn ->
        Tincture.new()
        |> Tincture.linear_gradient(0, 0, 10, 10, [{0.0, {1, 1, 1}}, {1.0, {0, 0, 0}}],
          direction: :diagonal
        )
      end
    end
  end

  describe "documents that use neither" do
    test "carry no ExtGState or Shading resource" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_at(50, 700, "Plain")
        |> Tincture.export()

      refute binary =~ "/ExtGState"
      refute binary =~ "/Shading"
    end
  end
end
