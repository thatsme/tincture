defmodule Tincture.FormXObjectTest do
  @moduledoc """
  Form XObjects: content drawn once with `form_xobject/5` and placed any
  number of times with `place_form_xobject/4,5`.

  The callback draws into a stream of its own, starting from a fixed state,
  and the caller's state is restored when it returns. Three properties follow,
  and each is pinned here: the XObject's bytes do not depend on the page, the
  page's bytes do not depend on the XObject, and no operator is ever omitted
  because the state it sets was set elsewhere.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF
  alias Tincture.Test.ContentStreamState
  alias Tincture.Test.MeasurableFont

  @refusal " A form XObject is a content stream with no page, structure or annotations " <>
             "of its own, so only drawing, text, images and fonts are allowed inside it."

  defp stamp(pdf, name \\ :stamp) do
    Tincture.form_xobject(pdf, name, 200, 40, fn pdf ->
      pdf
      |> Tincture.set_font("Helvetica", 10)
      |> Tincture.text_at(4, 14, "APPROVED")
      |> Tincture.rectangle(0.5, 0.5, 199, 39, :stroke)
    end)
  end

  # The form XObject's object body, from its dictionary to `endstream`.
  defp xobject_bodies(binary) do
    ~r{<< /Type /XObject /Subtype /Form .*?endstream}s
    |> Regex.scan(binary)
    |> Enum.map(&hd/1)
  end

  defp xobject_body(binary) do
    [body] = xobject_bodies(binary)
    body
  end

  # Every page content stream's data, in page order. Page content streams are
  # the only streams whose dictionary is just a /Length.
  defp page_contents(binary) do
    ~r{<< /Length \d+ >>\nstream\n(.*?)\nendstream}s
    |> Regex.scan(binary)
    |> Enum.map(fn [_whole, data] -> data end)
  end

  defp page_content(binary), do: binary |> page_contents() |> hd()

  defp refusal(caller, name \\ "stamp") do
    function = caller |> String.split(".") |> List.last()

    "#{caller} was called inside the form_xobject/5 callback defining #{inspect(name)}." <>
      @refusal <> " Call #{function} outside the callback."
  end

  defp assert_clean(binary) do
    %{streams: streams, violations: violations} = ContentStreamState.check_pdf(binary)
    assert streams > 0

    assert violations == [],
           Enum.map_join(violations, "\n", &ContentStreamState.format_violation/1)
  end

  describe "drawing state (T1-T6)" do
    test "T1: the XObject's bytes do not depend on what the page set before the call" do
      draw = fn pdf ->
        pdf
        |> Tincture.text_at(4, 14, "APPROVED")
        |> Tincture.rectangle(0.5, 0.5, 199, 39, :stroke)
      end

      fresh = Tincture.new() |> Tincture.form_xobject(:stamp, 200, 40, draw)

      busy =
        Tincture.new()
        |> Tincture.set_font("Courier", 20)
        |> Tincture.set_fill_color({1, 0, 0})
        |> Tincture.set_line_width(5)
        |> Tincture.set_dash([3, 2], 0)
        |> Tincture.set_alpha(0.5)
        |> Tincture.text_at(10, 10, "page text")
        |> Tincture.form_xobject(:stamp, 200, 40, draw)

      fresh_body = fresh |> Tincture.export() |> xobject_body()
      busy_body = busy |> Tincture.export() |> xobject_body()

      assert busy_body == fresh_body
      assert fresh_body =~ "/BaseFont /Helvetica"
      refute busy_body =~ "Courier"
    end

    test "T2: a definition changes nothing on the page, before or after it" do
      before = fn pdf ->
        pdf
        |> Tincture.set_fill_color({0, 0, 1})
        |> Tincture.text_at(72, 700, "before")
        |> Tincture.set_font("Courier", 20)
      end

      after_ = fn pdf ->
        pdf
        |> Tincture.text_at(72, 600, "after")
        |> Tincture.rectangle(72, 500, 100, 50, :fill)
      end

      plain = Tincture.new() |> before.()

      defined =
        plain
        |> Tincture.form_xobject(:stamp, 200, 40, fn pdf ->
          pdf
          |> Tincture.set_font("Times-Roman", 30)
          |> Tincture.set_fill_color({1, 0, 0})
          |> Tincture.set_line_width(4)
          |> Tincture.text_at(0, 0, "inside")
        end)

      assert defined.current_font == plain.current_font
      assert defined.operations == plain.operations
      assert defined.pages == plain.pages
      assert defined.current_stream == nil

      plain_bytes = plain |> after_.() |> Tincture.export() |> page_content()
      defined_bytes = defined |> after_.() |> Tincture.export() |> page_content()

      assert defined_bytes == plain_bytes
    end

    test "T3: an operator in the XObject is written even when the page set the same state" do
      binary =
        Tincture.new()
        |> Tincture.set_fill_color({1, 0, 0})
        |> Tincture.form_xobject(:stamp, 100, 100, fn pdf ->
          pdf
          |> Tincture.set_fill_color({1, 0, 0})
          |> Tincture.rectangle(0, 0, 10, 10, :fill)
        end)
        |> Tincture.export()

      assert xobject_body(binary) =~ "1 0 0 rg\n0 0 10 10 re\nf\n"
    end

    test "T4: an operator on the page is written even when the XObject set the same state" do
      binary =
        Tincture.new()
        |> Tincture.form_xobject(:stamp, 100, 100, fn pdf ->
          pdf
          |> Tincture.set_fill_color({1, 0, 0})
          |> Tincture.rectangle(0, 0, 10, 10, :fill)
        end)
        |> Tincture.place_form_xobject(:stamp, 0, 0)
        |> Tincture.set_fill_color({1, 0, 0})
        |> Tincture.rectangle(50, 50, 10, 10, :fill)
        |> Tincture.export()

      assert page_content(binary) =~ "/Fm1 Do\nQ\n1 0 0 rg\n50 50 10 10 re\nf\n"
    end

    test "T5: the callback starts from Helvetica 12, and the page's font is restored" do
      test_pid = self()

      pdf =
        Tincture.new()
        |> Tincture.set_font("Courier", 20)
        |> Tincture.form_xobject(:stamp, 100, 100, fn pdf ->
          send(test_pid, {:font_inside, pdf.current_font})
          pdf |> Tincture.set_font("Times-Roman", 30) |> Tincture.text_at(0, 0, "x")
        end)
        |> Tincture.text_at(72, 700, "page")

      assert_received {:font_inside, {"Helvetica", 12}}
      assert pdf.current_font == {"Courier", 20}
      assert List.last(pdf.operations) == {:text_at, 72, 700, "page", {"Courier", 20}}
    end

    test "T6: the operations mirror holds the XObject's operations inside, the page's after" do
      test_pid = self()

      pdf =
        Tincture.new()
        |> Tincture.text_at(72, 700, "page")
        |> Tincture.form_xobject(:stamp, 100, 100, fn pdf ->
          send(test_pid, {:at_entry, pdf.operations})
          drawn = Tincture.rectangle(pdf, 0, 0, 10, 10, :fill)
          send(test_pid, {:after_draw, drawn.operations, PDF.current_stream(drawn)})
          drawn
        end)

      assert_received {:at_entry, []}
      assert_received {:after_draw, [{:rectangle, 0, 0, 10, 10, :fill}], {:xobject, "stamp"}}
      assert pdf.operations == PDF.stream_operations(pdf, {:page, 1})
      assert pdf.operations == [{:text_at, 72, 700, "page", {"Helvetica", 12}}]
      assert PDF.current_stream(pdf) == {:page, 1}
    end
  end

  describe "bytes (T7-T9)" do
    test "T7: the XObject object and the placement bytes" do
      binary =
        Tincture.new()
        |> stamp()
        |> Tincture.place_form_xobject(:stamp, 72, 600)
        |> Tincture.place_form_xobject(:stamp, 72, 300, scale: 0.5)
        |> Tincture.place_form_xobject(:stamp, 72, 200, width: 100)
        |> Tincture.place_form_xobject(:stamp, 72, 100, width: 200)
        |> Tincture.export()

      assert xobject_body(binary) ==
               "<< /Type /XObject /Subtype /Form /BBox [0 0 200 40] /Resources << /Font << " <>
                 "/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> /Length 58 >>\n" <>
                 "stream\nBT\n/F1 10 Tf\n4 14 Td\n(APPROVED) Tj\nET\n0.5 0.5 199 39 re\nS\n\nendstream"

      assert page_content(binary) ==
               "q\n1 0 0 1 72 600 cm\n/Fm1 Do\nQ\n" <>
                 "q\n0.5 0 0 0.5 72 300 cm\n/Fm1 Do\nQ\n" <>
                 "q\n0.5 0 0 0.5 72 200 cm\n/Fm1 Do\nQ\n" <>
                 "q\n1 0 0 1 72 100 cm\n/Fm1 Do\nQ\n"

      assert_clean(binary)
    end

    test "T8: one object for every placement, on every page" do
      binary =
        Tincture.new()
        |> stamp()
        |> Tincture.place_form_xobject(:stamp, 72, 600)
        |> Tincture.place_form_xobject(:stamp, 72, 300)
        |> Tincture.add_page()
        |> Tincture.place_form_xobject(:stamp, 72, 600)
        |> Tincture.export()

      assert length(xobject_bodies(binary)) == 1
      [_whole, object_id] = Regex.run(~r{(\d+) 0 obj\n<< /Type /XObject /Subtype /Form}, binary)
      assert length(Regex.scan(~r{/XObject << /Fm1 #{object_id} 0 R >>}, binary)) == 2
      assert_clean(binary)
    end

    test "T9: resource names are local to each stream" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Courier", 10)
        |> Tincture.text_at(72, 700, "page")
        |> stamp()
        |> Tincture.place_form_xobject(:stamp, 72, 600)
        |> Tincture.export()

      assert xobject_body(binary) =~ "/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      assert binary =~ ~r{/Type /Page .*/F1 << /Type /Font /Subtype /Type1 /BaseFont /Courier >>}
    end
  end

  describe "refusals inside the callback (T10, T11)" do
    defp refused(caller, fun) do
      assert_raise ArgumentError, refusal(caller), fn ->
        Tincture.new()
        |> Tincture.form_xobject(:stamp, 100, 100, fun)
      end
    end

    test "T10: pages" do
      refused("Tincture.add_page/1", &Tincture.add_page/1)
      refused("Tincture.set_page/2", &Tincture.set_page(&1, 1))
    end

    test "T10: links" do
      refused("Tincture.link/6", &Tincture.link(&1, 0, 0, 10, 10, "https://example.com"))
      refused("Tincture.link/7", &Tincture.link(&1, 0, 0, 10, 10, "https://example.com", []))
      refused("Tincture.text_link/5", &Tincture.text_link(&1, 0, 0, "x", "https://example.com"))

      refused(
        "Tincture.text_link/6",
        &Tincture.text_link(&1, 0, 0, "x", "https://example.com", [])
      )

      refused("Tincture.PDF.add_link/4", &PDF.add_link(&1, {0, 0, 10, 10}, "https://example.com"))
    end

    test "T10: form fields and signing" do
      refused("Tincture.text_field/7", &Tincture.text_field(&1, 0, 0, 100, 20, "name"))
      refused("Tincture.checkbox/6", &Tincture.checkbox(&1, 0, 0, 12, "agree"))

      refused(
        "Tincture.choice_field/7",
        &Tincture.choice_field(&1, 0, 0, 100, 20, "days", options: ["14", "30"])
      )

      refused("Tincture.push_button/7", &Tincture.push_button(&1, 0, 0, 80, 20, "go"))
      refused("Tincture.signature_field/7", &Tincture.signature_field(&1, 0, 0, 200, 40, "sig"))

      refused(
        "Tincture.radio_group/4",
        &Tincture.radio_group(&1, "delivery", [[value: "standard", x: 0, y: 0, size: 12]])
      )

      refused("Tincture.sign/3", &Tincture.sign(&1, "sig", []))
      refused("Tincture.PDF.set_signature/3", &PDF.set_signature(&1, "sig", []))
    end

    test "T10: bookmarks and document settings" do
      refused("Tincture.add_bookmark/3", &Tincture.add_bookmark(&1, "Title", 1))
      refused("Tincture.set_metadata/2", &Tincture.set_metadata(&1, title: "x"))
      refused("Tincture.set_language/2", &Tincture.set_language(&1, "en-GB"))
      refused("Tincture.set_pdf_a/2", &Tincture.set_pdf_a(&1, :a2b))
      refused("Tincture.encrypt/1", &Tincture.encrypt/1)
      refused("Tincture.encrypt/2", &Tincture.encrypt(&1, user_password: "p"))
      refused("Tincture.page_size/2", &Tincture.page_size(&1, :letter))
    end

    test "T10: output, and save/3 writes no file" do
      refused("Tincture.export/1", &Tincture.export/1)
      refused("Tincture.export/2", &Tincture.export(&1, []))

      path =
        Path.join(System.tmp_dir!(), "tincture_xobject_#{System.unique_integer([:positive])}.pdf")

      refused("Tincture.save/3", &Tincture.save(&1, path))
      refute File.exists?(path)
    end

    test "T10: a nested definition, and a placement inside a definition" do
      refused("Tincture.form_xobject/5", &stamp(&1, :inner))

      assert_raise ArgumentError, refusal("Tincture.place_form_xobject/4", "outer"), fn ->
        Tincture.new()
        |> stamp(:inner)
        |> Tincture.form_xobject(:outer, 100, 100, &Tincture.place_form_xobject(&1, :inner, 0, 0))
      end

      assert_raise ArgumentError, refusal("Tincture.place_form_xobject/5", "outer"), fn ->
        Tincture.new()
        |> stamp(:inner)
        |> Tincture.form_xobject(
          :outer,
          100,
          100,
          &Tincture.place_form_xobject(&1, :inner, 0, 0, scale: 2)
        )
      end
    end

    test "T10: the layout modules reach the guards" do
      rich =
        Tincture.Typography.RichText.from_plain(
          "Body text that runs onto a second page. "
          |> String.duplicate(400)
        )

      refused("Tincture.add_page/1", fn pdf ->
        pdf
        |> Tincture.Layout.Template.render_document(Tincture.Layout.Template.new(), rich)
        |> elem(0)
      end)

      assert_raise ArgumentError, refusal("Tincture.tag/4"), fn ->
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, fn pdf ->
          Tincture.form_xobject(pdf, :stamp, 300, 300, fn pdf ->
            pdf |> Tincture.Layout.Box.flow_text(0, 280, 280, 260, rich) |> elem(0)
          end)
        end)
      end
    end

    test "T10: the structure functions of Tincture.PDF" do
      refused("Tincture.PDF.end_structure/1", &PDF.end_structure/1)
      refused("Tincture.PDF.end_artifact/1", &PDF.end_artifact/1)
    end

    # The reuse rule in docs/design/0.4.0-forms.md, section B, "Reuse across
    # structure elements", rests on this: an XObject cannot carry marked
    # content, so it may be placed inside any number of structure elements.
    # If this test ever has to change, that rule has to be revisited with it.
    test "T11: the reuse guarantee - tag/4 and artifact/2 inside the callback raise" do
      refused("Tincture.tag/4", &Tincture.tag(&1, :p, fn pdf -> pdf end))
      refused("Tincture.tag/4", &Tincture.tag(&1, :figure, [alt: "x"], fn pdf -> pdf end))
      refused("Tincture.artifact/2", &Tincture.artifact(&1, fn pdf -> pdf end))
    end
  end

  describe "names (T12)" do
    test "T12: an unknown name, including one defined only later" do
      assert_raise ArgumentError,
                   "Tincture.place_form_xobject/4 was given \"stamp\", which is not a defined " <>
                     "form XObject. Define it with form_xobject/5 before placing it.",
                   fn -> Tincture.new() |> Tincture.place_form_xobject(:stamp, 0, 0) end

      assert_raise ArgumentError,
                   "Tincture.place_form_xobject/5 was given \"later\", which is not a defined " <>
                     "form XObject. Define it with form_xobject/5 before placing it. Defined " <>
                     "form XObjects: \"stamp\".",
                   fn ->
                     Tincture.new()
                     |> stamp()
                     |> Tincture.place_form_xobject(:later, 0, 0, [])
                     |> stamp(:later)
                   end
    end

    test "T12: a duplicate name, :stamp and \"stamp\" being one name" do
      message =
        "Tincture.form_xobject/5 was given \"stamp\", which is already defined. " <>
          "Each form XObject needs its own name."

      assert_raise ArgumentError, message, fn -> Tincture.new() |> stamp() |> stamp() end
      assert_raise ArgumentError, message, fn -> Tincture.new() |> stamp() |> stamp("stamp") end

      pdf = Tincture.new() |> stamp("stamp") |> Tincture.place_form_xobject(:stamp, 0, 0)
      assert List.last(pdf.operations) == {:form_xobject, "stamp", 0, 0, 1, 1}
    end

    test "T12: a name that is neither an atom nor a non-empty string" do
      for name <- ["", nil, true, 7] do
        assert_raise ArgumentError,
                     "Tincture.form_xobject/5 was given #{inspect(name)} as a form XObject " <>
                       "name. A name is an atom or a non-empty string.",
                     fn -> Tincture.new() |> stamp(name) end
      end
    end
  end

  describe "placement options (T13)" do
    defp placed(opts) do
      Tincture.new()
      |> stamp()
      |> Tincture.place_form_xobject(:stamp, 10, 20, opts)
      |> Map.fetch!(:operations)
      |> List.last()
    end

    test "T13: scale, one dimension, both dimensions" do
      assert placed([]) == {:form_xobject, "stamp", 10, 20, 1, 1}
      assert placed(scale: 2) == {:form_xobject, "stamp", 10, 20, 2, 2}
      assert placed(scale: 0.5) == {:form_xobject, "stamp", 10, 20, 0.5, 0.5}
      assert placed(width: 100) == {:form_xobject, "stamp", 10, 20, 0.5, 0.5}
      assert placed(height: 80) == {:form_xobject, "stamp", 10, 20, 2, 2}
      assert placed(width: 100, height: 80) == {:form_xobject, "stamp", 10, 20, 0.5, 2}
    end

    test "T13: a scale equal to an integer is written as that integer" do
      assert placed(width: 200) == {:form_xobject, "stamp", 10, 20, 1, 1}
      assert placed(scale: 3.0) == {:form_xobject, "stamp", 10, 20, 3, 3}
    end

    test "T13: refused options" do
      message = fn text -> "Tincture.place_form_xobject/5 was given " <> text end

      assert_raise ArgumentError,
                   message.(
                     "both :scale and :width. Give :scale, or :width and/or :height, not both."
                   ),
                   fn -> placed(scale: 1, width: 100) end

      assert_raise ArgumentError,
                   message.(
                     "both :scale and :height. Give :scale, or :width and/or :height, not both."
                   ),
                   fn -> placed(scale: 1, height: 100) end

      for {key, value} <- [scale: -1, scale: 0, width: 0, height: "2"] do
        assert_raise ArgumentError,
                     message.(
                       "#{key}: #{inspect(value)}. :scale, :width and :height must be positive numbers."
                     ),
                     fn -> placed([{key, value}]) end
      end

      assert_raise ArgumentError,
                   message.("an unknown option :rotate. Known options: :scale, :width, :height."),
                   fn -> placed(rotate: 90) end
    end
  end

  describe "the end of the callback (T14)" do
    test "T14: a save_state/1 left unrestored" do
      assert_raise ArgumentError,
                   "the Tincture.form_xobject/5 callback defining \"stamp\" left 1 save_state/1 " <>
                     "without a restore_state/1. A form XObject is a content stream of its own, " <>
                     "and its saves and restores must balance within it.",
                   fn ->
                     Tincture.new()
                     |> Tincture.form_xobject(:stamp, 10, 10, &Tincture.save_state/1)
                   end
    end

    test "T14: a restore_state/1 with nothing saved" do
      assert_raise ArgumentError,
                   "the Tincture.form_xobject/5 callback defining \"stamp\" called restore_state/1 " <>
                     "with no save_state/1 open. A form XObject is a content stream of its own, " <>
                     "and its saves and restores must balance within it.",
                   fn ->
                     Tincture.new()
                     |> Tincture.form_xobject(:stamp, 10, 10, &Tincture.restore_state/1)
                   end
    end

    test "T14: a path left open" do
      assert_raise ArgumentError,
                   "the Tincture.form_xobject/5 callback defining \"stamp\" left a path open. " <>
                     "A path that is never painted draws nothing: paint it, or pass a shape its " <>
                     "own paint argument, before the callback returns.",
                   fn ->
                     Tincture.new()
                     |> Tincture.form_xobject(:stamp, 10, 10, &Tincture.move_to(&1, 0, 0))
                   end
    end

    test "T14: the callback must return the document" do
      assert_raise ArgumentError,
                   "the function passed to form_xobject/5 must return a %Tincture.PDF{}, got: :ok",
                   fn ->
                     Tincture.new() |> Tincture.form_xobject(:stamp, 10, 10, fn _ -> :ok end)
                   end
    end
  end

  describe "structure and figures (T15, T16)" do
    defp tagged, do: Tincture.new() |> Tincture.set_language("en-GB") |> stamp()

    test "T15: one XObject inside two structure elements, each Do in its own marked content" do
      binary =
        tagged()
        |> Tincture.tag(:p, &Tincture.place_form_xobject(&1, :stamp, 72, 600))
        |> Tincture.tag(:figure, [alt: "Approval stamp"], fn pdf ->
          Tincture.place_form_xobject(pdf, :stamp, 72, 300, scale: 0.5)
        end)
        |> Tincture.export()

      assert page_content(binary) ==
               "/P <</MCID 0>> BDC\nq\n1 0 0 1 72 600 cm\n/Fm1 Do\nQ\nEMC\n" <>
                 "/Figure <</MCID 1>> BDC\nq\n0.5 0 0 0.5 72 300 cm\n/Fm1 Do\nQ\nEMC\n"

      assert binary =~ "/S /P"
      assert binary =~ "/S /Figure"
      assert length(xobject_bodies(binary)) == 1
      refute xobject_body(binary) =~ "BDC"
      assert_clean(binary)
    end

    test "T16: a figure holding only a placement is bounded by the placed /BBox" do
      binary =
        tagged()
        |> Tincture.tag(:figure, [alt: "Approval stamp"], fn pdf ->
          Tincture.place_form_xobject(pdf, :stamp, 72, 300, scale: 0.5)
        end)
        |> Tincture.export()

      # 200 x 0.5 is the float 100.0, written as computed, as for an image.
      assert binary =~ "/BBox [72 300 172.0 320.0]"
      assert_clean(binary)
    end

    test "T16: with a stroked rectangle beside it, the union" do
      binary =
        tagged()
        |> Tincture.tag(:figure, [alt: "Approval stamp"], fn pdf ->
          pdf
          |> Tincture.place_form_xobject(:stamp, 72, 300, scale: 0.5)
          |> Tincture.rectangle(200, 250, 50, 20, :stroke)
        end)
        |> Tincture.export()

      assert binary =~ "/BBox [72 249.5 250.5 320.0]"
    end
  end

  describe "fonts and PDF/A (T17-T19)" do
    setup do
      path = MeasurableFont.write!()
      on_exit(fn -> File.rm(path) end)
      %{font: path}
    end

    test "T17: a glyph drawn only inside an XObject is in the embedded font", %{font: path} do
      base =
        Tincture.new()
        |> Tincture.register_ttf_font("Measurable", path)
        |> Tincture.set_font("Measurable", 10)
        |> Tincture.text_at(72, 700, "A")

      page_only = Tincture.export(base)

      with_xobject =
        base
        |> Tincture.form_xobject(:mark, 50, 20, fn pdf ->
          pdf |> Tincture.set_font("Measurable", 10) |> Tincture.text_at(0, 5, "B")
        end)
        |> Tincture.export()

      assert page_only =~ "/LastChar 65"
      refute page_only =~ "/LastChar 66"
      assert with_xobject =~ "/LastChar 66"
      assert with_xobject =~ ~r{/Widths \[700 900\]}
      assert length(Regex.scan(~r{/FontFile2}, with_xobject)) == 1
    end

    test "T18: a standard-14 font inside an XObject is refused under PDF/A", %{font: path} do
      pdf =
        Tincture.new()
        |> Tincture.register_ttf_font("Measurable", path)
        |> Tincture.set_pdf_a(:a2b)
        |> Tincture.set_font("Measurable", 10)
        |> Tincture.text_at(72, 700, "A")
        |> stamp()

      exception = assert_raise ArgumentError, fn -> Tincture.export(pdf) end
      assert exception.message =~ "Helvetica"
    end

    test "T19: an unplaced XObject is written, its font embedded", %{font: path} do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("Measurable", path)
        |> Tincture.form_xobject(:unplaced, 50, 20, fn pdf ->
          pdf |> Tincture.set_font("Measurable", 10) |> Tincture.text_at(0, 5, "AB")
        end)
        |> Tincture.export()

      assert length(xobject_bodies(binary)) == 1
      assert binary =~ "/FontFile2"
      refute binary =~ "Do\n"
    end
  end

  describe "no XObject, no change (T20)" do
    test "T20: stream keys are the pages, and the new fields stay empty" do
      pdf =
        Tincture.new()
        |> Tincture.text_at(72, 700, "one")
        |> Tincture.add_page()
        |> Tincture.text_at(72, 700, "two")
        |> Tincture.set_page(1)

      assert PDF.stream_keys(pdf) == [{:page, 1}, {:page, 2}]
      assert pdf.form_xobjects == %{}
      assert pdf.current_stream == nil
      assert PDF.current_stream(pdf) == {:page, 1}
    end

    test "T20: XObjects are listed after the pages, in definition order" do
      pdf = Tincture.new() |> stamp(:b) |> Tincture.add_page() |> stamp(:a)
      assert PDF.stream_keys(pdf) == [{:page, 1}, {:page, 2}, {:xobject, "b"}, {:xobject, "a"}]
    end

    test "T20: XObjects are allocated after images, before everything else" do
      binary =
        Tincture.new()
        |> stamp()
        |> Tincture.place_form_xobject(:stamp, 0, 0)
        |> Tincture.add_bookmark("Start", 1)
        |> Tincture.export()

      # Catalog 1, pages 2, page 3, its content 4: the XObject is 5, and the
      # outline after it.
      assert binary =~ "5 0 obj\n<< /Type /XObject /Subtype /Form"
      assert binary =~ "/Outlines 6 0 R"
    end
  end

  describe "the open-path refusal (T24)" do
    test "T24: a placement while a path is open raises, naming the arity called" do
      for {arity, place} <- [
            {4, &Tincture.place_form_xobject(&1, :stamp, 0, 0)},
            {5, &Tincture.place_form_xobject(&1, :stamp, 0, 0, scale: 2)}
          ] do
        assert_raise ArgumentError,
                     "Tincture.place_form_xobject/#{arity} was called with a path open. A " <>
                       "placement draws with its own q … Q, which cannot appear while a path " <>
                       "is being built. Paint or close the path first.",
                     fn ->
                       Tincture.new()
                       |> stamp()
                       |> Tincture.move_to(0, 0)
                       |> Tincture.line_to(10, 10)
                       |> place.()
                     end
      end
    end

    test "T24: after the path is painted, the placement is allowed" do
      pdf =
        Tincture.new()
        |> stamp()
        |> Tincture.move_to(0, 0)
        |> Tincture.line_to(10, 10)
        |> Tincture.stroke()
        |> Tincture.place_form_xobject(:stamp, 0, 0)

      assert List.last(pdf.operations) == {:form_xobject, "stamp", 0, 0, 1, 1}
    end
  end
end
