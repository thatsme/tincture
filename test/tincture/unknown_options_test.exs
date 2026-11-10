defmodule Tincture.UnknownOptionsTest do
  @moduledoc """
  W11: the public functions that take keyword options name an option they do
  not know. Before 0.5.0 such a key was ignored without a word; it warns now,
  once per call, naming the function, every unknown key and the known ones,
  and will raise in 0.6.0.

  Each row is one function, with the keys its code reads, written out here
  rather than read from the library, so that a key added to or dropped from a
  function's list fails a test. Every function is called with an unknown key
  and must warn with its full message, and with every one of its known keys
  and must not. A known key is given as `nil`: the warning is issued before
  any option is read, so a value the function then refuses still shows
  whether the key warned.
  """
  # Not async: these tests capture stderr, which the whole VM shares.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Tincture.Font.Context
  alias Tincture.Layout.Box
  alias Tincture.Layout.Table
  alias Tincture.Layout.Template
  alias Tincture.PDF.Encrypt
  alias Tincture.Typography
  alias Tincture.Typography.Hyphen
  alias Tincture.Typography.LineBreak
  alias Tincture.Typography.RichText

  @layout [
    :align,
    :line_break,
    :justify_max_space_multiplier,
    :justify_min_space_multiplier,
    :line_height,
    :widow_penalty,
    :orphan_penalty,
    :hyphen_penalty,
    :fitness_class_penalty,
    :consecutive_hyphen_penalty,
    :optimal_cost_model
  ]
  @flow [:rotate, :tag, :tag_as | @layout]
  @link [:border, :contents, :new_window, :page]
  @field [
    :page,
    :value,
    :font,
    :size,
    :border,
    :max_length,
    :tooltip,
    :options,
    :action,
    :label,
    :full_font,
    :align,
    :invisible,
    :read_only,
    :required,
    :no_export
  ]
  @encrypt [:user_password, :owner_password, :permissions, :encrypt_metadata]

  defp pdf, do: Tincture.new()
  defp rich, do: RichText.from_plain("Hello world")

  defp radio(opts),
    do: Tincture.radio_group(pdf(), "r", [[value: "a", x: 1, y: 1, size: 9]], opts)

  # {function, its known keys, a call with the given options}
  defp rows do
    [
      {"Tincture.link/7", @link, &Tincture.link(pdf(), 0, 0, 9, 9, {:url, "https://x.test"}, &1)},
      {"Tincture.text_link/6", [:color | @link],
       &Tincture.text_link(pdf(), 0, 0, "x", {:url, "https://x.test"}, &1)},
      {"Tincture.text_field/7", @field ++ [:multiline, :password],
       &Tincture.text_field(pdf(), 0, 0, 9, 9, "t", &1)},
      {"Tincture.checkbox/6", @field, &Tincture.checkbox(pdf(), 0, 0, 9, "c", &1)},
      {"Tincture.radio_group/4",
       [
         :selected,
         :read_only,
         :required,
         :no_export,
         :allow_deselect,
         :font,
         :size,
         :border,
         :tooltip,
         :page
       ], &radio/1},
      {"Tincture.push_button/7", @field, &Tincture.push_button(pdf(), 0, 0, 9, 9, "b", &1)},
      {"Tincture.signature_field/7", @field,
       &Tincture.signature_field(pdf(), 0, 0, 9, 9, "s", &1)},
      {"Tincture.choice_field/7", @field ++ [:dropdown, :editable, :sort],
       &Tincture.choice_field(pdf(), 0, 0, 9, 9, "ch", &1)},
      {"Tincture.encrypt/2", @encrypt, &Tincture.encrypt(pdf(), &1)},
      {"Tincture.register_ttf_font/4", [:subset, :enforce_embedding_permissions],
       &Tincture.register_ttf_font(pdf(), "F", "examples/fonts/LiberationSans-Regular.ttf", &1)},
      {"Tincture.register_otf_font/4", [:subset, :enforce_embedding_permissions],
       &Tincture.register_otf_font(pdf(), "F", "examples/fonts/LiberationSans-Regular.ttf", &1)},
      {"Tincture.text_at_with_fallback/6", [:shaping, :kerning],
       &Tincture.text_at_with_fallback(pdf(), 0, 0, "x", [], &1)},
      {"Tincture.set_alpha/2", [:fill, :stroke], &Tincture.set_alpha(pdf(), &1)},
      {"Tincture.linear_gradient/7", [:direction, :extend],
       &Tincture.linear_gradient(pdf(), 0, 0, 9, 9, [{0.0, {0, 0, 0}}, {1.0, {1, 1, 1}}], &1)},
      {"Tincture.radial_gradient/7", [:center, :radius, :inner_radius, :extend],
       &Tincture.radial_gradient(pdf(), 0, 0, 9, 9, [{0.0, {0, 0, 0}}, {1.0, {1, 1, 1}}], &1)},
      {"Tincture.tag/4", [:alt, :actual_text, :lang, :title, :scope, :id, :bbox],
       &Tincture.tag(pdf(), :p, &1, fn pdf -> pdf end)},
      {"Tincture.sign/3",
       [
         :private_key,
         :certificate,
         :chain,
         :digest,
         :signing_time,
         :reserved_bytes,
         :name,
         :reason,
         :location,
         :contact
       ], &Tincture.sign(pdf(), "s", &1)},
      {"Tincture.text_paragraph/6",
       [:rotate, :fallback_fonts, :bidi, :shaping, :kerning] ++ @layout,
       &Tincture.text_paragraph(pdf(), 0, 700, rich(), 200, &1)},
      {"Tincture.Layout.Box.flow_text/7", @flow,
       &Box.flow_text(pdf(), 0, 700, 200, 100, rich(), &1)},
      {"Tincture.Layout.Box.flow_across_boxes/4", @flow,
       &Box.flow_across_boxes(pdf(), rich(), [{0, 700, 200, 100}], &1)},
      {"Tincture.Layout.Table.render/6",
       [
         :padding,
         :font_size,
         :row_height,
         :border,
         :valign,
         :font,
         :header_font,
         :header_rows,
         :tag,
         :min_col_width,
         :table_width
       ], &Table.render(pdf(), 0, 700, :auto, [["a"]], &1)},
      {"Tincture.Layout.Template.new/1",
       [:page_size, :margins, :columns, :gutter, :header_height, :footer_height],
       &Template.new/1},
      {"Tincture.Layout.Template.with_header/3", [:font, :size, :height],
       &Template.with_header(Template.new(), "h", &1)},
      {"Tincture.Layout.Template.with_footer/3", [:font, :size, :height],
       &Template.with_footer(Template.new(), "f", &1)},
      {"Tincture.Layout.Template.render/4", [:page_number, :page_total | @flow],
       &Template.render(pdf(), Template.new(), rich(), &1)},
      {"Tincture.Layout.Template.render_document/4",
       [:page_number_start, :max_pages, :page_total | @flow],
       &Template.render_document(pdf(), Template.new(), rich(), &1)},
      {"Tincture.Layout.Template.render_xml_document/3",
       [:page_number_start, :max_pages, :page_total | @flow],
       &Template.render_xml_document(pdf(), "<document><body>x</body></document>", &1)},
      {"Tincture.Typography.layout_paragraph/3", @layout,
       &Typography.layout_paragraph(rich(), 200, &1)},
      {"Tincture.Typography.layout_paragraph_with_spill/4", @layout,
       &Typography.layout_paragraph_with_spill(rich(), 200, 3, &1)},
      {"Tincture.Typography.LineBreak.break_text/5",
       [:context, :hyphenate, :locale_resolver, :locale, :hyphen_left_min, :hyphen_right_min],
       &LineBreak.break_text("hello world", "Helvetica", 12, 200, &1)},
      {"Tincture.Typography.Hyphen.hyphenate/3", [:left_min, :right_min],
       &Hyphen.hyphenate("hyphenation", :en_gb, &1)},
      {"Tincture.Typography.RichText.from_plain/2", [:font, :size, :style, :context],
       &RichText.from_plain("x", &1)},
      {"Tincture.Typography.RichText.from_runs/2", [:context],
       &RichText.from_runs([%{text: "x", font: "Helvetica", size: 12}], &1)},
      {"Tincture.Font.Context.text_width/5", [:on_unknown],
       &Context.text_width(Context.new(), "Helvetica", 12, "x", &1)},
      {"Tincture.PDF.Encrypt.new/1", @encrypt, &Encrypt.new/1}
    ]
  end

  # stderr while `fun` runs, whatever it then returns or raises.
  defp stderr(fun) do
    capture_io(:stderr, fn ->
      try do
        fun.()
      rescue
        _error -> :refused
      end
    end)
  end

  defp warning(function, known) do
    "#{function} got the unknown option :zz_unknown. Known options: " <>
      "#{Enum.map_join(known, ", ", &inspect/1)}. " <>
      button_options(function) <>
      "Unknown options are ignored now; this will raise in 0.6.0."
  end

  defp button_options("Tincture.radio_group/4"),
    do: "Known button options: :value, :x, :y, :size, :page. "

  defp button_options(_function), do: ""

  test "the table covers the 35 functions that warn" do
    assert length(rows()) == 35
    assert rows() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 35
  end

  for index <- 0..34 do
    test "row #{index}: an unknown key warns once, with the full message" do
      {function, known, call} = Enum.at(rows(), unquote(index))
      output = stderr(fn -> call.(zz_unknown: 1) end)

      assert output =~ warning(function, known), "#{function}: #{output}"

      assert length(String.split(output, "this will raise in 0.6.0")) == 2, function
    end

    test "row #{index}: its known keys warn nothing" do
      {function, known, call} = Enum.at(rows(), unquote(index))
      output = stderr(fn -> call.(Enum.map(known, &{&1, nil})) end)

      refute output =~ "unknown option", "#{function}: #{output}"
    end
  end

  describe "radio_group/4" do
    @group "Known options: :selected, :read_only, :required, :no_export, :allow_deselect, " <>
             ":font, :size, :border, :tooltip, :page."
    @buttons "Known button options: :value, :x, :y, :size, :page."

    test "an unknown group key is named, with the group's and the buttons' known keys" do
      assert stderr(fn -> radio(zz_unknown: 1) end) =~
               "Tincture.radio_group/4 got the unknown option :zz_unknown. #{@group} #{@buttons}"
    end

    test "an unknown button key is named, with the same, in one warning" do
      output =
        stderr(fn ->
          Tincture.radio_group(pdf(), "r", [
            [value: "a", x: 1, y: 1, size: 9, checked: true],
            [value: "b", x: 20, y: 1, size: 9, checked: false]
          ])
        end)

      assert output =~
               "Tincture.radio_group/4 got the unknown button option :checked. " <>
                 "#{@group} #{@buttons}"

      assert length(String.split(output, "this will raise in 0.6.0")) == 2
    end

    test "unknown group and button keys, in one warning" do
      output =
        stderr(fn ->
          Tincture.radio_group(pdf(), "r", [[value: "a", x: 1, y: 1, size: 9, on: 1]], zz: 1)
        end)

      assert output =~
               "Tincture.radio_group/4 got the unknown option :zz and the unknown button " <>
                 "option :on. #{@group} #{@buttons}"
    end

    test "every known button key warns nothing" do
      button = [value: "a", x: 1, y: 1, size: 9, page: 1]
      refute stderr(fn -> Tincture.radio_group(pdf(), "r", [button]) end) =~ "unknown"
    end
  end

  describe "the 36th: place_form_xobject/5" do
    test "already raised on an unknown key, and still does, rather than warning" do
      pdf =
        Tincture.new()
        |> Tincture.form_xobject("f", 10, 10, fn pdf -> pdf end)

      output =
        capture_io(:stderr, fn ->
          assert_raise ArgumentError, ~r/unknown option :zz_unknown/, fn ->
            Tincture.place_form_xobject(pdf, "f", 0, 0, zz_unknown: 1)
          end
        end)

      refute output =~ "will raise in 0.6.0"
    end
  end

  describe "a function passing its options on warns once, under its own name" do
    test "text_link/6 does not warn again as link/7" do
      output =
        stderr(fn -> Tincture.text_link(pdf(), 0, 0, "x", {:url, "https://x.test"}, zz: 1) end)

      assert output =~ "Tincture.text_link/6 got the unknown option :zz."
      refute output =~ "Tincture.link/7 got"
    end

    test "render_document/4 does not warn as render/4 or flow_text/7 for its own keys" do
      output =
        stderr(fn ->
          Template.render_document(pdf(), Template.new(), rich(), max_pages: 2, zz: 1)
        end)

      assert length(String.split(output, "got the unknown option")) == 2
      assert output =~ "Tincture.Layout.Template.render_document/4 got the unknown option :zz."
    end

    test "text_paragraph/6 does not warn again as layout_paragraph/3" do
      output = stderr(fn -> Tincture.text_paragraph(pdf(), 0, 700, rich(), 200, zz: 1) end)

      assert length(String.split(output, "got the unknown option")) == 2
    end

    test "encrypt/2 does not warn again as Encrypt.new/1" do
      output = stderr(fn -> Tincture.encrypt(pdf(), zz: 1) end)

      assert output =~ "Tincture.encrypt/2 got the unknown option :zz."
      refute output =~ "Tincture.PDF.Encrypt.new/1 got"
    end

    test "flow_across_boxes/4 warns once, however many boxes it fills" do
      output =
        stderr(fn ->
          Box.flow_across_boxes(pdf(), rich(), [{0, 700, 20, 15}, {0, 600, 20, 15}], zz: 1)
        end)

      assert length(String.split(output, "got the unknown option")) == 2
    end
  end
end
