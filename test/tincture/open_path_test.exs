defmodule Tincture.OpenPathTest do
  # Not async: these tests capture stderr, which is shared by the whole VM, and
  # a test running alongside that writes to it would land in the capture.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # A painting or clipping operator with no path open is invalid where it is
  # written and ignored by viewers. stroke/1, fill/1, fill_even_odd/1, clip/1
  # and clip_even_odd/1 called with nothing open write nothing, and warn.

  defp content(pdf) do
    [stream] =
      Regex.run(~r/<< \/Length \d+ >>\nstream\n(.*?)\nendstream/s, Tincture.export(pdf),
        capture: :all_but_first
      )

    stream
  end

  for {function, operator} <- [
        stroke: "S",
        fill: "f",
        fill_even_odd: "f*",
        clip: "W",
        clip_even_odd: "W*"
      ] do
    describe "#{function}/1" do
      test "with no open path warns once and writes no operator" do
        {pdf, warning} =
          with_io(:stderr, fn ->
            Tincture.new()
            |> Tincture.rectangle(100, 100, 50, 50)
            |> then(&apply(Tincture, unquote(function), [&1]))
          end)

        assert warning =~ "Tincture.#{unquote(function)}/1 was called with no open path"
        assert warning =~ "pass its own paint argument"
        assert warning =~ "0.4.0"
        assert length(Regex.scan(~r/warning: /, warning)) == 1
        assert content(pdf) == "100 100 50 50 re\nS\n"
      end

      test "on a path opened with move_to/3 writes the operator, silently" do
        {pdf, warning} =
          with_io(:stderr, fn ->
            Tincture.new()
            |> Tincture.move_to(100, 100)
            |> Tincture.line_to(200, 100)
            |> Tincture.line_to(150, 200)
            |> then(&apply(Tincture, unquote(function), [&1]))
          end)

        assert warning == ""
        assert content(pdf) =~ ~r/150 200 l\n#{Regex.escape(unquote(operator))}\n/
      end
    end
  end

  test "rectangle |> fill writes exactly `re S`, and warns" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new() |> Tincture.rectangle(10, 20, 30, 40) |> Tincture.fill()
      end)

    assert content(pdf) == "10 20 30 40 re\nS\n"
    assert warning =~ "Tincture.fill/1 was called with no open path"
    assert warning =~ "rectangle(pdf, x, y, w, h, :fill)"
  end

  test "a shape drawn with paint: :none leaves the path open for fill/1" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new() |> Tincture.rectangle(10, 20, 30, 40, :none) |> Tincture.fill()
      end)

    assert warning == ""
    assert content(pdf) == "10 20 30 40 re\nn\nf\n"
  end

  test "a line or circle drawn with paint: :none leaves the path open too" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new()
        |> Tincture.line(0, 0, 10, 10, :none)
        |> Tincture.stroke()
        |> Tincture.circle(50, 50, 5, :none)
        |> Tincture.fill()
      end)

    assert warning == ""
    assert content(pdf) =~ ~r/10 10 l\nn\nS\n/
    assert content(pdf) =~ ~r/ c\nn\nf\n\z/
  end

  test "text and colour between path and paint do not close it" do
    {_pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new()
        |> Tincture.move_to(0, 0)
        |> Tincture.line_to(10, 10)
        |> Tincture.set_stroke_color({1, 0, 0})
        |> Tincture.stroke()
      end)

    assert warning == ""
  end

  test "one painting operator closes the path for the next call" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new()
        |> Tincture.move_to(0, 0)
        |> Tincture.line_to(10, 10)
        |> Tincture.stroke()
        |> Tincture.stroke()
      end)

    assert content(pdf) == "0 0 m\n10 10 l\nS\n"
    assert length(Regex.scan(~r/warning: /, warning)) == 1
  end

  test "the path is tracked per page" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new()
        |> Tincture.move_to(0, 0)
        |> Tincture.line_to(10, 10)
        |> Tincture.add_page()
        |> Tincture.stroke()
      end)

    assert warning =~ "no open path"
    assert Tincture.PDF.page_operations(pdf, 2) == []
  end
end
