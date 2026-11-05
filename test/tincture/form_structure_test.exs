defmodule Tincture.FormStructureTest do
  @moduledoc """
  PDF/UA-1 requires every widget annotation of a tagged document to be nested
  in a Form structure element (ISO 14289-1 clause 7.18.4), and a Form without a
  Role attribute may have only that widget as its child. The connection runs
  both ways and each direction fails on its own, so each is asserted on its
  own, for every field type:

    1. one Form element, and only one, owns the widget;
    2. its /K is a single /OBJR whose /Obj is the widget;
    3. the widget carries /StructParent;
    4. and 5. /ParentTree maps that key to the same Form element;
    6. the Form's /P is the element that was open at the field call.

  An invisible signature field matters most: its rectangle is outside the crop
  box, so veraPDF's rules for widgets pass it whether or not a Form owns it.
  Only a test like this one can tell.

  The assertions parse the written file and follow its references, as
  `Tincture.LinkStructureTest` does for links.
  """

  use ExUnit.Case, async: true

  # -- reading the file ---------------------------------------------------------

  defp objects(binary) do
    ~r/^(\d+) 0 obj\r?\n(.*?)\r?\nendobj/ms
    |> Regex.scan(binary)
    |> Map.new(fn [_, id, body] -> {String.to_integer(id), body} end)
  end

  defp widgets(objects),
    do: for({id, body} <- objects, body =~ "/Subtype /Widget", into: %{}, do: {id, body})

  defp elements(objects, type) do
    for {id, body} <- objects,
        body =~ "/Type /StructElem",
        body =~ ~r|/S /#{type}[ >/]|,
        into: %{},
        do: {id, body}
  end

  defp integer_entry(body, key) do
    case Regex.run(~r/\/#{key} (\d+)(?![\d ]+0 R)/, body) do
      [_, value] -> String.to_integer(value)
      nil -> nil
    end
  end

  defp ref_entry(body, key) do
    case Regex.run(~r/\/#{key} (\d+) 0 R/, body) do
      [_, id] -> String.to_integer(id)
      nil -> nil
    end
  end

  defp kids(body) do
    case Regex.run(~r/\/K \[(.*?)\](?= \/| >>)/, body) do
      [_, kids] -> kids
      nil -> nil
    end
  end

  # The annotation entries of /Nums: key => element, for keys that map to a
  # single reference rather than a page's array.
  defp parent_tree(objects) do
    {_id, root} = Enum.find(objects, fn {_id, body} -> body =~ "/Type /StructTreeRoot" end)
    nums = Map.fetch!(objects, ref_entry(root, "ParentTree"))
    [_, entries] = Regex.run(~r/\/Nums \[(.*)\]/s, nums)

    ~r/(\d+) (\[[^\]]*\]|\d+ 0 R)/
    |> Regex.scan(entries)
    |> Map.new(fn [_, key, value] -> {String.to_integer(key), value} end)
  end

  defp parent_tree_next_key(objects) do
    {_id, root} = Enum.find(objects, fn {_id, body} -> body =~ "/Type /StructTreeRoot" end)
    integer_entry(root, "ParentTreeNextKey")
  end

  # The six steps, for every widget in the file. Returns, per widget, its Form
  # element's id and its parent's structure type.
  defp assert_owned(binary) do
    objects = objects(binary)
    forms = elements(objects, "Form")
    tree = parent_tree(objects)

    for {widget, body} <- widgets(objects), into: %{} do
      owners = for {id, form} <- forms, form =~ "/OBJR /Obj #{widget} 0 R", do: id
      assert [form] = owners, "widget #{widget} is owned by #{length(owners)} Form elements"

      assert kids(Map.fetch!(forms, form)) == "<< /Type /OBJR /Obj #{widget} 0 R >>",
             "Form #{form}'s /K is not a single /OBJR naming widget #{widget}"

      key = integer_entry(body, "StructParent")
      assert is_integer(key), "widget #{widget} has no /StructParent"
      assert Map.fetch!(tree, key) == "#{form} 0 R", "/ParentTree #{key} is not Form #{form}"

      parent = ref_entry(Map.fetch!(forms, form), "P")
      [_, type] = Regex.run(~r|/S /(\w+)|, Map.fetch!(objects, parent))
      {widget, %{form: form, parent: parent, parent_type: type}}
    end
  end

  # -- documents ----------------------------------------------------------------

  defp tagged(fun) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fun)
    |> Tincture.export()
  end

  @fields [
    {"text", &__MODULE__.text/1, 1},
    {"multiline text", &__MODULE__.multiline/1, 1},
    {"combo box", &__MODULE__.combo/1, 1},
    {"list box", &__MODULE__.list/1, 1},
    {"checkbox", &__MODULE__.checkbox/1, 1},
    {"three-button radio group", &__MODULE__.radio/1, 3},
    {"push button", &__MODULE__.push_button/1, 1},
    {"visible signature", &__MODULE__.signature/1, 1},
    {"invisible signature", &__MODULE__.invisible_signature/1, 1}
  ]

  def text(pdf), do: Tincture.text_field(pdf, 72, 700, 200, 20, "f", tooltip: "Text")

  def multiline(pdf),
    do: Tincture.text_field(pdf, 72, 640, 200, 60, "f", multiline: true, tooltip: "Notes")

  def combo(pdf),
    do: Tincture.choice_field(pdf, 72, 700, 200, 20, "f", options: ["a", "b"], tooltip: "Combo")

  def list(pdf) do
    Tincture.choice_field(pdf, 72, 640, 200, 60, "f",
      options: ["a", "b"],
      dropdown: false,
      tooltip: "List"
    )
  end

  def checkbox(pdf), do: Tincture.checkbox(pdf, 72, 700, 12, "f", tooltip: "Agree")

  def radio(pdf) do
    Tincture.radio_group(
      pdf,
      "f",
      [
        [value: "a", x: 72, y: 700, size: 12],
        [value: "b", x: 72, y: 680, size: 12],
        [value: "c", x: 72, y: 660, size: 12]
      ],
      tooltip: "Choose"
    )
  end

  def push_button(pdf) do
    Tincture.push_button(pdf, 72, 700, 120, 24, "f",
      action: {:url, "https://example.org"},
      label: "Open",
      tooltip: "Open the site"
    )
  end

  def signature(pdf),
    do: Tincture.signature_field(pdf, 72, 640, 200, 50, "f", label: "Sign", tooltip: "Sign")

  def invisible_signature(pdf),
    do: Tincture.signature_field(pdf, 0, 0, 0, 0, "f", invisible: true, tooltip: "Sign")

  # -- ownership ----------------------------------------------------------------

  describe "every widget is owned by its own Form element" do
    for {label, fun, count} <- @fields do
      test "a #{label}, created inside a :section" do
        binary = tagged(&Tincture.tag(&1, :section, unquote(fun)))
        owned = assert_owned(binary)

        assert map_size(owned) == unquote(count)
        assert owned |> Map.values() |> Enum.map(& &1.parent_type) |> Enum.uniq() == ["Sect"]
        assert length(Regex.scan(~r|/S /Form |, binary)) == unquote(count)
      end

      test "a #{label}, created inside a :p" do
        owned = assert_owned(tagged(&Tincture.tag(&1, :p, unquote(fun))))
        assert owned |> Map.values() |> Enum.map(& &1.parent_type) |> Enum.uniq() == ["P"]
      end
    end
  end

  describe "a radio group" do
    test "gets one Form element per button, in button order, under the element open at the call" do
      objects = objects(tagged(&Tincture.tag(&1, :section, fn pdf -> radio(pdf) end)))

      owned =
        assert_owned(Enum.map_join(objects, "\n", fn {id, b} -> "#{id} 0 obj\n#{b}\nendobj" end))

      by_button =
        objects
        |> widgets()
        |> Enum.map(fn {widget, body} ->
          [_, state] = Regex.run(~r|/AP << /N << /(\w+) |, body)
          {state, Map.fetch!(owned, widget).form}
        end)
        |> Enum.sort_by(&elem(&1, 1))

      assert Enum.map(by_button, &elem(&1, 0)) == ["a", "b", "c"]
      assert owned |> Map.values() |> Enum.map(& &1.parent) |> Enum.uniq() |> length() == 1
    end

    test "with buttons on two pages, each Form element names its own button's page" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.add_page()
        |> Tincture.set_page(1)
        |> Tincture.tag(:document, fn pdf ->
          Tincture.tag(pdf, :section, fn pdf ->
            Tincture.radio_group(
              pdf,
              "where",
              [
                [value: "here", x: 72, y: 700, size: 12],
                [value: "there", x: 72, y: 700, size: 12, page: 2]
              ],
              tooltip: "Where"
            )
          end)
        end)
        |> Tincture.export()

      objects = objects(binary)
      owned = assert_owned(binary)

      for {widget, %{form: form}} <- owned do
        assert ref_entry(Map.fetch!(objects, form), "Pg") ==
                 ref_entry(Map.fetch!(objects, widget), "P")
      end

      assert owned
             |> Map.values()
             |> Enum.map(&ref_entry(Map.fetch!(objects, &1.form), "Pg"))
             |> Enum.uniq()
             |> length() == 2
    end
  end

  describe "placement" do
    test "a Form element directly under a grouping element is laid out as a block" do
      objects = objects(tagged(&Tincture.tag(&1, :section, fn pdf -> text(pdf) end)))
      [{_id, form}] = Map.to_list(elements(objects, "Form"))
      assert form =~ "/A << /O /Layout /Placement /Block >>"
    end

    test "a Form element inside a content element carries no placement" do
      objects = objects(tagged(&Tincture.tag(&1, :p, fn pdf -> text(pdf) end)))
      [{_id, form}] = Map.to_list(elements(objects, "Form"))
      refute form =~ "/Placement"
      refute form =~ "/A "
    end
  end

  describe "order" do
    test "Form elements join the open element's kids in call order, among its other kids" do
      objects =
        objects(
          tagged(fn pdf ->
            Tincture.tag(pdf, :section, fn pdf ->
              pdf
              |> Tincture.text_field(72, 700, 200, 20, "first", tooltip: "First")
              |> Tincture.tag(:p, &Tincture.text_at(&1, 72, 680, "Between"))
              |> Tincture.text_field(72, 650, 200, 20, "second", tooltip: "Second")
            end)
          end)
        )

      [{_id, sect}] = Map.to_list(elements(objects, "Sect"))

      kid_types =
        for [_, id] <- Regex.scan(~r/(\d+) 0 R/, kids(sect)) do
          [_, type] = Regex.run(~r|/S /(\w+)|, Map.fetch!(objects, String.to_integer(id)))
          type
        end

      assert kid_types == ["Form", "P", "Form"]

      [first, second] =
        for name <- ["first", "second"] do
          {widget, _body} = Enum.find(widgets(objects), fn {_id, b} -> b =~ "/T (#{name})" end)
          widget
        end

      [form_first, _p, form_second] =
        for [_, id] <- Regex.scan(~r/(\d+) 0 R/, kids(sect)), do: String.to_integer(id)

      assert Map.fetch!(objects, form_first) =~ "/Obj #{first} 0 R"
      assert Map.fetch!(objects, form_second) =~ "/Obj #{second} 0 R"
    end
  end

  describe "/StructParent keys" do
    test "pages take the first keys, links the next, and widgets follow, with no key used twice" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.add_page()
        |> Tincture.set_page(1)
        |> Tincture.tag(:document, fn pdf ->
          pdf
          |> Tincture.tag(:p, fn pdf ->
            pdf
            |> Tincture.text_at(72, 760, "Name")
            |> Tincture.text_field(72, 730, 200, 20, "name", tooltip: "Name")
          end)
          |> Tincture.tag(:link, fn pdf ->
            pdf
            |> Tincture.text_at(300, 735, "terms")
            |> Tincture.link(300, 730, 340, 745, {:url, "https://example.org"}, contents: "Terms")
          end)
          |> Tincture.set_page(2)
          |> Tincture.tag(:p, fn pdf ->
            pdf
            |> Tincture.text_at(72, 760, "Agree")
            |> Tincture.checkbox(72, 730, 12, "agree", tooltip: "Agree")
          end)
        end)
        |> Tincture.export()

      objects = objects(binary)
      assert_owned(binary)

      page_keys =
        for {_id, body} <- objects,
            body =~ "/Type /Page /Parent",
            do: integer_entry(body, "StructParents")

      [link_key] =
        for {_id, body} <- objects,
            body =~ "/Subtype /Link",
            do: integer_entry(body, "StructParent")

      widget_keys = for {_id, body} <- widgets(objects), do: integer_entry(body, "StructParent")

      assert Enum.sort(page_keys) == [0, 1]
      assert link_key == 2
      assert Enum.sort(widget_keys) == [3, 4]
      assert parent_tree_next_key(objects) == 5
      assert Map.keys(parent_tree(objects)) |> Enum.sort() == [0, 1, 2, 3, 4]
    end

    test "a tagged document without fields keeps the keys and bytes it had: no Form element" do
      binary =
        tagged(fn pdf ->
          Tincture.tag(pdf, :link, fn pdf ->
            pdf
            |> Tincture.text_at(72, 735, "terms")
            |> Tincture.link(72, 730, 112, 745, {:url, "https://example.org"}, contents: "Terms")
          end)
        end)

      refute binary =~ "/S /Form"
      objects = objects(binary)
      [link] = for {_id, body} <- objects, body =~ "/Subtype /Link", do: body
      assert integer_entry(link, "StructParent") == 1
      assert parent_tree_next_key(objects) == 2
    end
  end

  describe "an untagged document" do
    for {label, fun, _count} <- @fields do
      test "a #{label} gets no Form element and no /StructParent" do
        binary = Tincture.new() |> unquote(fun).() |> Tincture.export()
        refute binary =~ "/S /Form"
        refute binary =~ "/StructParent"
        refute binary =~ "/StructTreeRoot"
      end
    end
  end

  describe "tag/4" do
    test "refuses :form, which every form field call creates for itself" do
      message =
        "tag/4 cannot open :form: each form field call creates a :form element for each " <>
          "of its widgets, inside the element open at the call. Create the field inside the " <>
          "element that describes it, such as the :p holding its label"

      assert_raise ArgumentError, message, fn ->
        Tincture.tag(Tincture.new(), :form, fn pdf -> pdf end)
      end
    end
  end
end
