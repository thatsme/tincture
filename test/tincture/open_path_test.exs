defmodule Tincture.OpenPathTest do
  # Not async: these tests capture stderr, which is shared by the whole VM, and
  # a test running alongside that writes to it would land in the capture.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # A painting or clipping operator with no path open is invalid where it is
  # written and ignored by viewers. stroke/1, fill/1, fill_even_odd/1, clip/1
  # and clip_even_odd/1 called with nothing open raise ArgumentError, and
  # write nothing to stderr.

  defp content(pdf) do
    [stream] =
      Regex.run(~r/<< \/Length \d+ >>\nstream\n(.*?)\nendstream/s, Tincture.export(pdf),
        capture: :all_but_first
      )

    stream
  end

  # Runs fun, which must raise ArgumentError, with stderr captured. Returns the
  # exception, and asserts nothing was written to stderr: the condition raises
  # and does not also warn.
  defp raises_silently(fun) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        send(parent, {:raised, assert_raise(ArgumentError, fun)})
      end)

    assert stderr == ""
    assert_received {:raised, exception}
    exception
  end

  for {function, operator, verb, paint} <- [
        {:stroke, "S", "paint", ":stroke"},
        {:fill, "f", "paint", ":fill"},
        {:fill_even_odd, "f*", "paint", ":fill_even_odd"},
        {:clip, "W", "clip to", ":none"},
        {:clip_even_odd, "W*", "clip to", ":none"}
      ] do
    describe "#{function}/1" do
      test "with no open path raises, naming the fix" do
        exception =
          raises_silently(fn ->
            Tincture.new()
            |> Tincture.rectangle(100, 100, 50, 50)
            |> then(&apply(Tincture, unquote(function), [&1]))
          end)

        assert exception.message ==
                 "Tincture.#{unquote(function)}/1 was called with no open path, so there is " <>
                   "nothing to #{unquote(verb)}. A shape paints itself: pass its own paint " <>
                   "argument (for example rectangle(pdf, x, y, w, h, #{unquote(paint)})) " <>
                   "instead, or start a path with move_to/3."
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

  test "rectangle |> fill raises, naming the shape's own paint argument" do
    exception =
      raises_silently(fn ->
        Tincture.new() |> Tincture.rectangle(10, 20, 30, 40) |> Tincture.fill()
      end)

    assert exception.message ==
             "Tincture.fill/1 was called with no open path, so there is nothing to paint. " <>
               "A shape paints itself: pass its own paint argument (for example " <>
               "rectangle(pdf, x, y, w, h, :fill)) instead, or start a path with move_to/3."
  end

  test "a shape drawn with paint: :none leaves the path open for fill/1" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        Tincture.new() |> Tincture.rectangle(10, 20, 30, 40, :none) |> Tincture.fill()
      end)

    assert warning == ""
    assert content(pdf) == "10 20 30 40 re\nf\n"
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
    assert content(pdf) =~ ~r/10 10 l\nS\n/
    assert content(pdf) =~ ~r/ c\nf\n\z/
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

  test "one painting operator closes the path, so a second one raises" do
    pdf =
      Tincture.new()
      |> Tincture.move_to(0, 0)
      |> Tincture.line_to(10, 10)
      |> Tincture.stroke()

    assert content(pdf) == "0 0 m\n10 10 l\nS\n"

    exception = raises_silently(fn -> Tincture.stroke(pdf) end)
    assert exception.message =~ "Tincture.stroke/1 was called with no open path"
  end

  # Leaving page 1 with its path unpainted also warns (W6); that warning is the
  # only thing written to stderr.
  test "the path is tracked per page" do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        exception =
          assert_raise(ArgumentError, fn ->
            Tincture.new()
            |> Tincture.move_to(0, 0)
            |> Tincture.line_to(10, 10)
            |> Tincture.add_page()
            |> Tincture.stroke()
          end)

        send(parent, {:raised, exception})
      end)

    assert_received {:raised, exception}
    assert exception.message =~ "no open path"
    assert stderr =~ "Tincture.add_page/1 was called while a path is open on page 1"
    assert length(Regex.scan(~r/warning: /, stderr)) == 1
  end
end
