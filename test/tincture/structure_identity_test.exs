defmodule Tincture.StructureIdentityTest do
  @moduledoc """
  Two structure elements can be equal as terms: two empty `:section` scopes on
  one page carry the same tag, page and kids. Each is still its own element,
  and has to be written as its own object, reachable exactly once from its
  parent. Numbering elements by value gave both one object, listed twice in
  the parent's `/K`, and left the other unreachable - and no veraPDF rule
  looks for it.

  These tests follow the references in the written file: every structure
  element is a kid of exactly one element (or of the root), its `/P` names
  that element, and no `/K` lists the same element twice.
  """

  use ExUnit.Case, async: true

  defp objects(binary) do
    ~r/^(\d+) 0 obj\r?\n(.*?)\r?\nendobj/ms
    |> Regex.scan(binary)
    |> Map.new(fn [_, id, body] -> {String.to_integer(id), body} end)
  end

  defp kid_refs(body) do
    case Regex.run(~r/\/K \[([^\]]*)\]/, body) do
      [_, kids] ->
        ~r/(\d+) 0 R/ |> Regex.scan(kids) |> Enum.map(fn [_, id] -> String.to_integer(id) end)

      nil ->
        []
    end
  end

  defp parent_ref(body) do
    [_, id] = Regex.run(~r/\/P (\d+) 0 R/, body)
    String.to_integer(id)
  end

  # Every structure element, every reference to one from a /K array, and the
  # element each reference comes from.
  defp structure(binary) do
    objects = objects(binary)
    elements = for {id, body} <- objects, body =~ "/Type /StructElem", into: %{}, do: {id, body}
    [{root_id, root}] = for {id, body} <- objects, body =~ "/Type /StructTreeRoot", do: {id, body}

    references =
      for {from, body} <- [{root_id, root} | Map.to_list(elements)],
          kid <- kid_refs(body),
          Map.has_key?(elements, kid),
          do: {from, kid}

    {elements, root_id, references}
  end

  defp assert_each_element_reachable_once(binary) do
    {elements, root_id, references} = structure(binary)

    for {id, body} <- elements do
      from = for {from, ^id} <- references, do: from

      assert length(from) == 1,
             "element #{id} is referenced #{length(from)} times, from #{inspect(from)}"

      [parent] = from
      expected = if parent == root_id, do: root_id, else: parent
      assert parent_ref(body) == expected, "element #{id}'s /P is not the element listing it"
    end

    elements
  end

  test "two :section scopes, each holding only a field, are two objects" do
    binary =
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.tag(:document, fn pdf ->
        pdf
        |> Tincture.tag(:section, fn pdf ->
          Tincture.text_field(pdf, 72, 700, 200, 20, "first", tooltip: "First")
        end)
        |> Tincture.tag(:section, fn pdf ->
          Tincture.text_field(pdf, 72, 650, 200, 20, "second", tooltip: "Second")
        end)
      end)
      |> Tincture.export(enforce: false)

    elements = assert_each_element_reachable_once(binary)
    assert Enum.count(elements, fn {_id, body} -> body =~ "/S /Sect " end) == 2
  end

  test "two identical empty containers are two objects, beside a content element" do
    binary =
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.tag(:document, fn pdf ->
        pdf
        |> Tincture.tag(:section, fn pdf -> pdf end)
        |> Tincture.tag(:p, fn pdf ->
          pdf |> Tincture.set_font("Helvetica", 10) |> Tincture.text_at(72, 760, "Between")
        end)
        |> Tincture.tag(:section, fn pdf -> pdf end)
      end)
      |> Tincture.export(enforce: false)

    elements = assert_each_element_reachable_once(binary)
    assert Enum.count(elements, fn {_id, body} -> body =~ "/S /Sect" end) == 2

    {_elements, _root_id, references} = structure(binary)

    [{_root, document}] =
      for {from, kid} <- references, from not in Map.keys(elements), do: {from, kid}

    document_kids = for {^document, kid} <- references, do: kid
    assert document_kids == Enum.uniq(document_kids)
    assert length(document_kids) == 3
  end

  test "identical nested containers each keep their own kids" do
    binary =
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.tag(:document, fn pdf ->
        pdf
        |> Tincture.tag(:section, fn pdf -> Tincture.tag(pdf, :div, fn pdf -> pdf end) end)
        |> Tincture.tag(:section, fn pdf -> Tincture.tag(pdf, :div, fn pdf -> pdf end) end)
      end)
      |> Tincture.export(enforce: false)

    elements = assert_each_element_reachable_once(binary)
    assert Enum.count(elements, fn {_id, body} -> body =~ "/S /Div" end) == 2
  end
end
