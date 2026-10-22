defmodule Tincture.PathStateTest do
  @moduledoc """
  What is written between a path's construction and its paint.

  ISO 32000-1 Figure 9 allows only path construction inside a path object,
  then optionally W or W*, then the paint. So:

    * a shape drawn with `paint: :none` writes only its construction, and the
      next paint or clip paints it;
    * a colour, line-style or alpha setter called while a path is open is
      written before the path, which §8.2 permits;
    * text, an image, a gradient, a saved or restored graphics state, or
      marked content, while a path is open, warns (W5): 0.4.0 raises;
    * a path nothing painted is ended with `n`, and leaving the page or
      exporting with one warns (W6): 0.4.0 raises;
    * a content tag or artifact closing over a path started inside it warns
      (W7), with the bytes unchanged: 0.4.0 raises.
  """
  # Not async: these tests capture stderr, which is shared by the whole VM, and
  # a test running alongside that writes to it would land in the capture.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO, only: [with_io: 2]

  alias Tincture.PDF.PathState
  alias Tincture.Test.ContentStreamState

  defp open_path, do: Tincture.new() |> Tincture.move_to(10, 10) |> Tincture.line_to(50, 50)

  defp content(pdf) do
    [_, stream] =
      Regex.run(~r/stream\n(.*?)\nendstream/s, Tincture.export(pdf, enforce: false))

    stream
  end

  defp quiet(fun) do
    {result, stderr} = with_io(:stderr, fun)
    {result, stderr}
  end

  defp w5(caller, what) do
    "#{caller} was called while a path is open, so #{what} would be written inside the " <>
      "path, where PDF does not allow it. A path holds only path construction until " <>
      "stroke/1, fill/1 or clip/1 paints it, or a shape's own paint argument does: paint " <>
      "the path first, or draw this before starting it. This will raise in 0.4.0."
  end

  defp w6(caller, page) do
    "#{caller} was called while a path is open on page #{page} that nothing has painted. " <>
      "A path draws nothing until stroke/1, fill/1 or clip/1 paints it, so it is ended " <>
      "unpainted. Paint it, or remove it. This will raise in 0.4.0."
  end

  defp w7(closed, block) do
    "#{closed} with a path still open, so its end would be written inside the path, where " <>
      "PDF does not allow it. Paint the path with stroke/1, fill/1 or clip/1 before the " <>
      "#{block} closes. This will raise in 0.4.0."
  end

  defp w7_count(stderr), do: length(String.split(stderr, "with a path still open")) - 1

  defp line_inside(pdf), do: pdf |> Tincture.move_to(10, 10) |> Tincture.line_to(50, 50)

  defp png do
    chunk = fn type, data ->
      <<byte_size(data)::32-big, type::binary-size(4), data::binary,
        :erlang.crc32([type, data])::32-big>>
    end

    path = Path.join(System.tmp_dir!(), "tincture_ps_#{System.unique_integer([:positive])}.png")

    File.write!(
      path,
      <<137, 80, 78, 71, 13, 10, 26, 10>> <>
        chunk.("IHDR", <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>) <>
        chunk.("IDAT", :zlib.compress(<<0, 255, 0, 0, 128>>)) <> chunk.("IEND", "")
    )

    on_exit(fn -> File.rm(path) end)
    path
  end

  @stops [{0.0, {1, 0, 0}}, {1.0, {0, 0, 1}}]

  describe "PS1, PS2: class 3, setters, are written before the path" do
    @setters [
      {:set_fill_color, [{1, 0, 0}], "1 0 0 rg\n"},
      {:set_stroke_color, [{1, 0, 0}], "1 0 0 RG\n"},
      {:set_line_width, [2], "2 w\n"},
      {:set_line_cap, [1], "1 J\n"},
      {:set_line_join, [1], "1 j\n"},
      {:set_dash, [[3, 2], 0], "[3 2] 0 d\n"},
      {:set_miter_limit, [4], "4 M\n"},
      {:set_alpha, [0.5], "/GS0 gs\n"}
    ]

    for {setter, args, bytes} <- @setters do
      @setter setter
      @args args
      @bytes bytes
      test "#{setter} between the path and its paint" do
        {pdf, stderr} =
          quiet(fn ->
            Tincture
            |> apply(@setter, [open_path() | @args])
            |> Tincture.stroke()
          end)

        assert stderr == ""
        assert content(pdf) == @bytes <> "10 10 m\n50 50 l\nS\n"
        assert ContentStreamState.check_stream(content(pdf)) == []
      end
    end

    test "several setters keep their call order, before the path" do
      {pdf, ""} =
        quiet(fn ->
          open_path()
          |> Tincture.set_stroke_color({1, 0, 0})
          |> Tincture.line_to(90, 10)
          |> Tincture.set_line_width(3)
          |> Tincture.stroke()
        end)

      assert content(pdf) == "1 0 0 RG\n3 w\n10 10 m\n50 50 l\n90 10 l\nS\n"
    end

    test "the recorded operations keep call order" do
      pdf = open_path() |> Tincture.set_stroke_color({1, 0, 0}) |> Tincture.stroke()

      assert Tincture.PDF.page_operations(pdf, 1) == [
               {:move_to, 10, 10},
               {:line_to, 50, 50},
               {:set_stroke_color, {1, 0, 0}},
               :stroke
             ]
    end
  end

  describe "PS3: moving setters gives every graphics object the same values" do
    # The value of each setter in force at each paint, replayed over an
    # operation list. A setter moved before the path is still before the paint
    # and after the previous paint, so both orders must agree.
    defp state_at_paints(ops) do
      {_state, at_paints} =
        Enum.reduce(ops, {%{}, []}, fn
          op, {state, acc} when op in [:stroke, :fill, :fill_even_odd, :clip, :clip_even_odd] ->
            {state, [state | acc]}

          op, {state, acc} when is_tuple(op) and elem(op, 0) in [:rectangle, :line, :circle] ->
            if elem(op, tuple_size(op) - 1) == :none,
              do: {state, acc},
              else: {state, [state | acc]}

          op, {state, acc} when is_tuple(op) ->
            name = elem(op, 0)

            if name in [
                 :set_fill_color,
                 :set_stroke_color,
                 :set_line_width,
                 :set_line_cap,
                 :set_line_join,
                 :set_dash,
                 :set_miter_limit,
                 :set_alpha
               ],
               do: {Map.put(state, name, op), acc},
               else: {state, acc}

          _op, acc ->
            acc
        end)

      Enum.reverse(at_paints)
    end

    test "a mixed sequence" do
      ops = [
        {:set_line_width, 1},
        {:move_to, 0, 0},
        {:line_to, 10, 10},
        {:set_stroke_color, {1, 0, 0}},
        {:set_line_width, 4},
        :stroke,
        {:rectangle, 0, 0, 5, 5, :none},
        {:set_fill_color, {0, 1, 0}},
        :fill,
        {:set_dash, [2], 0},
        {:rectangle, 0, 0, 5, 5, :stroke},
        {:move_to, 1, 1},
        {:set_alpha, 0.5, 0.5},
        {:line_to, 2, 2},
        :stroke
      ]

      written = PathState.written_order(ops)

      assert state_at_paints(written) == state_at_paints(ops)
      assert Enum.sort(written) == Enum.sort(ops)
    end
  end

  describe "PS4, PS6, PS7: paint: :none" do
    test "then fill/1, stroke/1, clip/1" do
      fill = Tincture.new() |> Tincture.rectangle(10, 10, 30, 30, :none) |> Tincture.fill()
      stroke = Tincture.new() |> Tincture.line(0, 0, 10, 10, :none) |> Tincture.stroke()

      clip =
        Tincture.new()
        |> Tincture.rectangle(10, 10, 30, 30, :none)
        |> Tincture.clip()
        |> Tincture.rectangle(0, 0, 100, 100, :fill)

      assert content(fill) == "10 10 30 30 re\nf\n"
      assert content(stroke) == "0 0 m\n10 10 l\nS\n"
      assert content(clip) == "10 10 30 30 re\nW\nn\n0 0 100 100 re\nf\n"

      for pdf <- [fill, stroke, clip],
          do: assert(ContentStreamState.check_stream(content(pdf)) == [])
    end

    test "then nothing: ended with n, and export warns (W6)" do
      {binary, stderr} =
        quiet(fn ->
          Tincture.new() |> Tincture.rectangle(0, 0, 5, 5, :none) |> Tincture.export()
        end)

      assert binary =~ "0 0 5 5 re\nn\n"
      assert stderr =~ w6("Tincture.export/2", 1)
    end

    test "then a setter and text: n right after the shape, as :none always wrote, and W5" do
      {pdf, stderr} =
        quiet(fn ->
          Tincture.new()
          |> Tincture.rectangle(0, 0, 5, 5, :none)
          |> Tincture.set_fill_color({1, 0, 0})
          |> Tincture.text_at(0, 0, "x")
        end)

      assert content(pdf) == "0 0 5 5 re\nn\n1 0 0 rg\nBT\n/F1 12 Tf\n0 0 Td\n(x) Tj\nET\n"
      assert stderr =~ w5("Tincture.text_at/4", "the text")
      assert ContentStreamState.check_stream(content(pdf)) == []
    end
  end

  describe "PS8: W5 at every class-4 function" do
    test "each one warns once, naming itself" do
      png = png()

      calls = [
        {"Tincture.text_at/4", "the text", &Tincture.text_at(&1, 0, 0, "x")},
        {"Tincture.text_at_rotated/5", "the text", &Tincture.text_at_rotated(&1, 0, 0, 90, "x")},
        {"Tincture.text_at_with_fallback/5", "the text",
         &Tincture.text_at_with_fallback(&1, 0, 0, "x")},
        {"Tincture.text_at_with_fallback/6", "the text",
         &Tincture.text_at_with_fallback(&1, 0, 0, "x", [], [])},
        {"Tincture.text_at_rotated_with_fallback/6", "the text",
         &Tincture.text_at_rotated_with_fallback(&1, 0, 0, 90, "x")},
        {"Tincture.text_at_rotated_with_fallback/7", "the text",
         &Tincture.text_at_rotated_with_fallback(&1, 0, 0, 90, "x", [], [])},
        {"Tincture.text_paragraph/6", "the text",
         &Tincture.text_paragraph(
           &1,
           0,
           0,
           Tincture.Typography.RichText.from_plain("x"),
           100
         )},
        {"Tincture.text_link/5", "the text",
         &Tincture.text_link(&1, 0, 0, "x", "https://example.com")},
        {"Tincture.text_link/6", "the text",
         &Tincture.text_link(&1, 0, 0, "x", "https://example.com", color: {0, 0, 1})},
        {"Tincture.image_png/6", "the image", &Tincture.image_png(&1, 0, 0, 10, 10, png)},
        {"Tincture.linear_gradient/7", "the gradient",
         &Tincture.linear_gradient(&1, 0, 0, 10, 10, @stops)},
        {"Tincture.radial_gradient/7", "the gradient",
         &Tincture.radial_gradient(&1, 0, 0, 10, 10, @stops)},
        {"Tincture.save_state/1", "the saved graphics state", &Tincture.save_state/1},
        {"Tincture.restore_state/1", "the restored graphics state", &Tincture.restore_state/1},
        {"Tincture.tag/4", "the marked content", &Tincture.tag(&1, :p, fn pdf -> pdf end)},
        {"Tincture.artifact/2", "the marked content", &Tincture.artifact(&1, fn pdf -> pdf end)}
      ]

      for {caller, what, call} <- calls do
        {_pdf, stderr} = quiet(fn -> open_path() |> call.() end)
        message = w5(caller, what)

        assert stderr =~ message, "#{caller}: #{stderr}"

        assert length(String.split(stderr, "was called while a path is open")) == 2,
               "#{caller} warned more than once: #{stderr}"
      end
    end

    test "image_jpeg/6 warns before it reads the file" do
      {result, stderr} =
        quiet(fn ->
          try do
            open_path() |> Tincture.image_jpeg(0, 0, 10, 10, "tmp/no_such_file.jpg")
          rescue
            _error -> :raised
          end
        end)

      assert result == :raised
      assert stderr =~ w5("Tincture.image_jpeg/6", "the image")
    end

    test "inside a form XObject, the path that counts is the XObject's own" do
      {_pdf, inside} =
        quiet(fn ->
          Tincture.new()
          |> Tincture.form_xobject(:stamp, 100, 100, fn pdf ->
            pdf
            |> Tincture.move_to(10, 10)
            |> Tincture.line_to(50, 50)
            |> Tincture.text_at(0, 0, "x")
            |> Tincture.stroke()
          end)
        end)

      assert inside =~ w5("Tincture.text_at/4", "the text")

      {_pdf, outside} =
        quiet(fn ->
          open_path()
          |> Tincture.form_xobject(:stamp, 100, 100, &Tincture.text_at(&1, 0, 0, "x"))
          |> Tincture.stroke()
        end)

      refute outside =~ "was called while a path is open"
    end

    test "a grouping tag writes no marked content, and does not warn" do
      {_pdf, stderr} = quiet(fn -> open_path() |> Tincture.tag(:section, fn pdf -> pdf end) end)
      refute stderr =~ "was called while a path is open"
    end

    test "nothing warns with no path open, or after it is painted" do
      {_pdf, stderr} =
        quiet(fn ->
          Tincture.new()
          |> Tincture.text_at(0, 0, "x")
          |> Tincture.move_to(0, 0)
          |> Tincture.line_to(5, 5)
          |> Tincture.stroke()
          |> Tincture.save_state()
          |> Tincture.text_at(0, 0, "y")
          |> Tincture.restore_state()
        end)

      assert stderr == ""
    end
  end

  describe "PS9: W6" do
    test "add_page/1 with a path open warns, and the page's path is ended with n" do
      {pdf, stderr} = quiet(fn -> open_path() |> Tincture.add_page() end)

      assert stderr =~ w6("Tincture.add_page/1", 1)
      [_, page1 | _rest] = Regex.split(~r/stream\n/, Tincture.export(pdf))
      assert page1 =~ ~r/\A10 10 m\n50 50 l\nn\n/
    end

    test "set_page/2 to another page warns; to the same page it does not" do
      base =
        Tincture.new() |> Tincture.add_page() |> Tincture.move_to(0, 0) |> Tincture.line_to(5, 5)

      {_pdf, same} = quiet(fn -> Tincture.set_page(base, 2) end)
      {_pdf, other} = quiet(fn -> Tincture.set_page(base, 1) end)

      assert same == ""
      assert other =~ w6("Tincture.set_page/2", 2)
    end

    test "export warns, whatever enforce: says" do
      {_binary, stderr} = quiet(fn -> Tincture.export(open_path(), enforce: false) end)
      assert stderr =~ w6("Tincture.export/2", 1)
    end
  end

  describe "W7: a tag or artifact closing over a path started inside it" do
    test "a path opened inside tag(:p) and painted after it warns once, bytes unchanged" do
      {pdf, stderr} =
        quiet(fn -> Tincture.new() |> Tincture.tag(:p, &line_inside/1) |> Tincture.stroke() end)

      assert stderr =~ w7("Tincture.tag/4 closed tag(:p, ...)", "tag")
      assert w7_count(stderr) == 1
      assert content(pdf) == "/P <</MCID 0>> BDC\n10 10 m\n50 50 l\nEMC\nS\n"
    end

    test "the same inside artifact/2" do
      {pdf, stderr} =
        quiet(fn -> Tincture.new() |> Tincture.artifact(&line_inside/1) |> Tincture.stroke() end)

      assert stderr =~ w7("Tincture.artifact/2 closed", "artifact")
      assert w7_count(stderr) == 1
      assert content(pdf) == "/Artifact BMC\n10 10 m\n50 50 l\nEMC\nS\n"
    end

    test "nested tags warn once, at the inner close" do
      {_pdf, stderr} =
        quiet(fn ->
          Tincture.new()
          |> Tincture.tag(:p, &Tincture.tag(&1, :span, fn pdf -> line_inside(pdf) end))
          |> Tincture.stroke()
        end)

      assert stderr =~ w7("Tincture.tag/4 closed tag(:span, ...)", "tag")
      assert w7_count(stderr) == 1
    end

    test "a path open before the tag opened is W5's, at the open, and not W7's" do
      {_pdf, stderr} =
        quiet(fn -> open_path() |> Tincture.tag(:p, fn pdf -> pdf end) |> Tincture.stroke() end)

      assert stderr =~ w5("Tincture.tag/4", "the marked content")
      assert length(String.split(stderr, "was called while a path is open")) == 2
      assert w7_count(stderr) == 0
    end

    test "a path opened and painted inside the tag does not warn" do
      {_pdf, stderr} =
        quiet(fn ->
          Tincture.new()
          |> Tincture.tag(:p, &(&1 |> line_inside() |> Tincture.stroke()))
          |> Tincture.artifact(&(&1 |> line_inside() |> Tincture.fill()))
        end)

      assert stderr == ""
    end

    test "a grouping element closing over a path does not warn, and writes no EMC" do
      {pdf, stderr} =
        quiet(fn ->
          Tincture.new() |> Tincture.tag(:section, &line_inside/1) |> Tincture.stroke()
        end)

      assert stderr == ""
      assert content(pdf) == "10 10 m\n50 50 l\nS\n"
    end
  end

  describe "PS1: the matrix, class 4 written as before" do
    test "text inside an open path keeps today's bytes" do
      {pdf, _stderr} =
        quiet(fn -> open_path() |> Tincture.text_at(0, 0, "x") |> Tincture.stroke() end)

      assert content(pdf) == "10 10 m\n50 50 l\nBT\n/F1 12 Tf\n0 0 Td\n(x) Tj\nET\nS\n"
    end

    test "a shape with a paint joins the open path, valid as before" do
      pdf = open_path() |> Tincture.rectangle(0, 0, 5, 5, :fill)

      assert content(pdf) == "10 10 m\n50 50 l\n0 0 5 5 re\nf\n"
      assert ContentStreamState.check_stream(content(pdf)) == []
    end
  end
end
