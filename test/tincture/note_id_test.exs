defmodule Tincture.NoteIdTest do
  @moduledoc """
  ISO 14289-1 clause 7.9: a Note element shall carry an `/ID`, and each shall be
  unique. The `/ID` is a key into `/IDTree`, the name tree on
  `/StructTreeRoot` — ISO 32000-1 makes that the mechanism for dereferencing it,
  so an `/ID` with no tree is unusable rather than merely unverified.

  veraPDF has no rule about the tree at all: clause 7.9's two tests look only at
  the element. So the tree is asserted here, by resolving through it.
  """

  use ExUnit.Case, async: true

  defp objects(binary) do
    ~r/^(\d+) 0 obj\r?\n(.*?)\r?\nendobj/ms
    |> Regex.scan(binary)
    |> Map.new(fn [_, id, body] -> {String.to_integer(id), body} end)
  end

  defp notes(objects) do
    for {id, body} <- objects, body =~ "/S /Note ", into: %{}, do: {id, body}
  end

  # [{id_string, object_id}, ...] in the order /Names lists them.
  defp id_tree(binary) do
    objects = objects(binary)

    [_, root_id] = Regex.run(~r/\/StructTreeRoot (\d+) 0 R/, binary)
    root = Map.fetch!(objects, String.to_integer(root_id))

    case Regex.run(~r/\/IDTree (\d+) 0 R/, root) do
      nil ->
        nil

      [_, tree_id] ->
        tree = Map.fetch!(objects, String.to_integer(tree_id))
        [_, names] = Regex.run(~r/\/Names \[(.*)\]/s, tree)

        ~r/\(([^)]*)\) (\d+) 0 R/
        |> Regex.scan(names)
        |> Enum.map(fn [_, id, object_id] -> {id, String.to_integer(object_id)} end)
    end
  end

  defp document_with_notes(count, opts \\ %{}) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fn doc ->
      Enum.reduce(1..count, doc, fn n, acc ->
        Tincture.tag(acc, :note, Map.get(opts, n, []), fn page ->
          page
          |> Tincture.set_font("Helvetica", 9)
          |> Tincture.text_at(50, 800 - n * 12, "Note #{n}.")
        end)
      end)
    end)
    |> Tincture.export()
  end

  describe "a Note element" do
    test "carries an /ID" do
      binary = document_with_notes(3)

      for {_id, body} <- notes(objects(binary)) do
        assert body =~ ~r/\/ID \(note\d+\)/
      end
    end

    test "resolves through /IDTree to its own object" do
      binary = document_with_notes(3)
      objects = objects(binary)
      entries = id_tree(binary)

      assert length(entries) == 3

      for {id, object_id} <- entries do
        body = Map.fetch!(objects, object_id)
        assert body =~ "/S /Note "
        assert body =~ "/ID (#{id})"
      end
    end

    test "has an id unique within the document" do
      binary = document_with_notes(12)
      ids = id_tree(binary) |> Enum.map(&elem(&1, 0))

      assert length(ids) == 12
      assert ids == Enum.uniq(ids)
    end
  end

  describe "the name tree" do
    # /Names is ordered by byte comparison, so unpadded "note10" would sort
    # between "note1" and "note2". A conforming consumer is entitled to binary
    # search it; most viewers scan linearly and would never reveal the fault.
    test "is sorted by byte comparison across the single-digit boundary" do
      binary = document_with_notes(12)
      ids = id_tree(binary) |> Enum.map(&elem(&1, 0))

      assert ids == Enum.sort(ids)

      nine = Enum.find_index(ids, &String.ends_with?(&1, "0009"))
      ten = Enum.find_index(ids, &String.ends_with?(&1, "0010"))

      assert nine + 1 == ten,
             "note 9 must be immediately followed by note 10, got #{inspect(ids)}"
    end

    test "is generated deterministically, so the same document is byte-identical" do
      assert document_with_notes(5) == document_with_notes(5)
    end

    test "is absent when nothing registers an id, leaving other documents unmoved" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.tag(:document, fn doc ->
          Tincture.tag(doc, :p, fn page ->
            page
            |> Tincture.set_font("Helvetica", 12)
            |> Tincture.text_at(50, 700, "No notes here.")
          end)
        end)
        |> Tincture.export()

      assert binary =~ "/StructTreeRoot"
      refute binary =~ "/IDTree"
      refute binary =~ "/ID (note"
    end

    test "registers only Note elements, not every structure element" do
      binary = document_with_notes(2)
      objects = objects(binary)

      non_notes =
        for {_id, body} <- objects,
            body =~ "/Type /StructElem",
            not (body =~ "/S /Note "),
            do: body

      assert non_notes != []

      for body <- non_notes do
        refute body =~ "/ID ("
      end
    end
  end

  describe "an explicit :id" do
    test "is used in place of the generated one" do
      binary = document_with_notes(2, %{1 => [id: "footnote-tariffs"]})
      ids = id_tree(binary) |> Enum.map(&elem(&1, 0))

      assert "footnote-tariffs" in ids
    end

    test "is refused when blank" do
      assert_raise ArgumentError, ~r/must not be blank/, fn ->
        document_with_notes(1, %{1 => [id: "  "]})
      end
    end

    test "is refused when it collides with another" do
      assert_raise ArgumentError, ~r/must be unique/, fn ->
        document_with_notes(2, %{1 => [id: "same"], 2 => [id: "same"]})
      end
    end
  end
end
