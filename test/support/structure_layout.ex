defmodule Tincture.Test.StructureLayout do
  @moduledoc """
  Checks the layout attributes of a tagged PDF's structure elements, read from
  the file's bytes rather than from the library's own model.

    * Every `/Figure` carries an attribute dictionary owned by `/Layout` with a
      four-number `/BBox` inside its page's MediaBox (ISO 32000-1 Table 344).
    * An inline-level element or illustration (§14.8.4.4, §14.8.4.5) whose
      parent is a grouping element (§14.8.4.2) carries `/Placement /Block`,
      and no other element carries `/Placement` at all.

  The lists below are the standard's, not Tincture's vocabulary, so a type
  Tincture learns later is held to the same rule without touching this.
  """

  alias Tincture.Test.PDFObjects

  @inline_level ~w(Span Quote Note Reference BibEntry Code Link Annot Ruby Warichu Figure Formula Form)
  @grouping ~w(Document Part Art Sect Div)
  @headings ~w(H H1 H2 H3 H4 H5 H6)

  @type result :: %{
          elements: non_neg_integer(),
          problems: [String.t()],
          headings?: boolean(),
          outlines?: boolean()
        }

  @doc """
  The structure elements found, the layout problems among them, and whether the
  document has headings and an outline.
  """
  @spec check(binary()) :: result()
  def check(pdf) when is_binary(pdf) do
    %{objects: objects, trailer: trailer} = PDFObjects.read(pdf)
    catalog = PDFObjects.resolve(Map.fetch!(trailer, "Root"), objects)

    elements =
      for {number, %{value: %{"Type" => {:name, "StructElem"}} = element}} <- objects,
          do: {number, element}

    problems =
      elements
      |> Enum.sort()
      |> Enum.flat_map(fn {number, element} -> problems(number, element, objects) end)

    %{
      elements: length(elements),
      problems: problems,
      headings?: Enum.any?(elements, fn {_number, element} -> type(element) in @headings end),
      outlines?: Map.has_key?(catalog, "Outlines")
    }
  end

  defp problems(number, element, objects) do
    type = type(element)
    layout = layout_attributes(element, objects)
    parent_type = element |> Map.get("P") |> PDFObjects.resolve(objects) |> type()

    bbox_problems(number, type, layout, element, objects) ++
      placement_problems(number, type, parent_type, layout)
  end

  defp bbox_problems(number, "Figure", layout, element, objects) do
    {_x0, _y0, width, height} = media_box(element, objects)

    case Map.get(layout, "BBox") do
      [left, bottom, right, top] = box
      when is_number(left) and is_number(bottom) and is_number(right) and is_number(top) ->
        if left >= 0 and bottom >= 0 and right <= width and top <= height and left < right and
             bottom < top,
           do: [],
           else: [
             "object #{number}: Figure /BBox #{inspect(box)} is not inside MediaBox [0 0 #{width} #{height}]"
           ]

      nil ->
        ["object #{number}: Figure has no /Layout /BBox"]

      other ->
        ["object #{number}: Figure /BBox is not four numbers: #{inspect(other)}"]
    end
  end

  defp bbox_problems(_number, _type, _layout, _element, _objects), do: []

  defp placement_problems(number, type, parent_type, layout) do
    expected = if type in @inline_level and parent_type in @grouping, do: {:name, "Block"}

    case {expected, Map.get(layout, "Placement")} do
      {same, same} ->
        []

      {nil, found} ->
        [
          "object #{number}: #{type} in #{parent_type} carries /Placement #{inspect(found)}, expected none"
        ]

      {_block, found} ->
        [
          "object #{number}: #{type} in #{parent_type} needs /Placement /Block, found #{inspect(found)}"
        ]
    end
  end

  # /A is one attribute dictionary or an array of them, each possibly a
  # reference. Only the one owned by /Layout matters here.
  defp layout_attributes(element, objects) do
    element
    |> Map.get("A")
    |> PDFObjects.resolve(objects)
    |> List.wrap()
    |> Enum.map(&PDFObjects.resolve(&1, objects))
    |> Enum.find(%{}, &(Map.get(&1, "O") == {:name, "Layout"}))
  end

  defp media_box(element, objects) do
    page = element |> Map.fetch!("Pg") |> PDFObjects.resolve(objects)
    [x0, y0, x1, y1] = page |> inherited("MediaBox", objects) |> PDFObjects.resolve(objects)
    {x0, y0, x1, y1}
  end

  defp inherited(node, key, objects) do
    case Map.fetch(node, key) do
      {:ok, value} ->
        value

      :error ->
        node |> Map.fetch!("Parent") |> PDFObjects.resolve(objects) |> inherited(key, objects)
    end
  end

  defp type(%{"S" => {:name, type}}), do: type
  defp type(_not_an_element), do: nil
end
