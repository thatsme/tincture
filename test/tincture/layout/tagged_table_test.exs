defmodule Tincture.Layout.TaggedTableTest do
  @moduledoc """
  Tests for `Tincture.Layout.Table.render/6` emitting its own structure.

  A table is the element that most needs tagging — without it a screen reader
  reads a grid of numbers with nothing saying which column or row each belongs
  to — and it is also the one a caller cannot tag by hand, because the helper
  draws the whole grid in a single call.
  """
  use ExUnit.Case, async: true

  alias Tincture.Layout.Table

  @rows [["Region", "Revenue"], ["North", "1,204"], ["South", "986"]]

  defp render(pdf, opts) do
    {rendered, _result} = Table.render(pdf, 50, 700, [200, 120], @rows, opts)
    Tincture.export(rendered)
  end

  # `/S /TH ` with the trailing space, because `/S /TH` alone also matches
  # `/S /THead`.
  defp count_elements(binary, type) do
    length(Regex.scan(~r|/S /#{type} |, binary))
  end

  defp tagged_document(opts) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fn pdf ->
      {rendered, _result} = Table.render(pdf, 50, 700, [200, 120], @rows, opts)
      rendered
    end)
    |> Tincture.export()
  end

  describe "inside a tagged document" do
    setup do
      {:ok, binary: tagged_document(header_rows: 1)}
    end

    test "emits a table containing rows containing cells", %{binary: binary} do
      assert count_elements(binary, "Table") == 1
      assert count_elements(binary, "TR") == 3
      assert count_elements(binary, "TH") == 2
      assert count_elements(binary, "TD") == 4
    end

    test "separates header rows from body rows", %{binary: binary} do
      # /THead lets a reader repeat the headers when speaking row by row.
      assert count_elements(binary, "THead") == 1
      assert count_elements(binary, "TBody") == 1
    end

    test "header cells declare the cells they govern", %{binary: binary} do
      assert length(Regex.scan(~r|/A << /O /Table /Scope /Column >>|, binary)) == 2
    end

    test "borders are artifacts, not untagged content", %{binary: binary} do
      # Six cells, each with a border rectangle. Untagged content in a tagged
      # document is read out as noise and fails conformance, so decoration has
      # to say what it is.
      assert length(Regex.scan(~r|/Artifact BMC|, binary)) == 6
    end

    test "every marked-content sequence is closed", %{binary: binary} do
      opened = length(Regex.scan(~r/BDC|BMC/, binary))
      closed = length(Regex.scan(~r/EMC/, binary))

      # Six cells and six border artifacts; the containers emit nothing.
      assert opened == 12
      assert closed == 12
    end

    test "the table hangs off the document element", %{binary: binary} do
      assert [[_, document_id]] =
               Regex.scan(~r|(\d+) 0 obj\n<< /Type /StructElem /S /Document |, binary)

      assert [[_, table_body]] = Regex.scan(~r|<< /Type /StructElem /S /Table (.*?)>>|s, binary)

      assert table_body =~ "/P #{document_id} 0 R"
    end

    test "the object graph is sound", %{binary: binary} do
      ids =
        ~r/^(\d+) 0 obj/m |> Regex.scan(binary) |> Enum.map(&String.to_integer(Enum.at(&1, 1)))

      refs =
        ~r/(\d+) 0 R/
        |> Regex.scan(binary)
        |> Enum.map(&String.to_integer(Enum.at(&1, 1)))
        |> Enum.uniq()

      assert refs -- ids == []
    end
  end

  describe "with no header rows" do
    test "puts every row in the body" do
      binary =
        Tincture.new()
        |> Tincture.tag(:document, fn pdf ->
          {rendered, _} = Table.render(pdf, 50, 700, [200, 120], @rows, [])
          rendered
        end)
        |> Tincture.export()

      assert count_elements(binary, "TBody") == 1
      assert count_elements(binary, "THead") == 0
      assert count_elements(binary, "TD") == 6
      assert count_elements(binary, "TH") == 0
    end
  end

  describe ":tag defaults to :auto" do
    test "an untagged document stays untagged" do
      # Structure containing nothing but a table reads worse than none at all,
      # so a caller who has not opted into tagging does not silently get it.
      binary = render(Tincture.new(), header_rows: 1)

      refute binary =~ "/StructTreeRoot"
      refute binary =~ "BDC"
      refute binary =~ "Artifact"
    end

    test "a document already carrying structure gets a tagged table" do
      binary =
        Tincture.new()
        |> Tincture.tag(:p, &Tincture.text_at(&1, 10, 10, "before"))
        |> then(fn pdf ->
          {rendered, _} = Table.render(pdf, 50, 700, [200, 120], @rows, header_rows: 1)
          rendered
        end)
        |> Tincture.export()

      assert count_elements(binary, "Table") == 1
    end
  end

  describe ":tag explicitly" do
    test "true tags a table in an otherwise untagged document" do
      binary = render(Tincture.new(), header_rows: 1, tag: true)

      assert binary =~ "/StructTreeRoot"
      assert count_elements(binary, "Table") == 1
    end

    test "false leaves it untagged inside a tagged document" do
      binary = tagged_document(header_rows: 1, tag: false)

      assert count_elements(binary, "Table") == 0
      refute binary =~ "/Artifact BMC"
    end

    test "rejects anything else" do
      assert_raise ArgumentError, ~r/:tag must be true, false or :auto/, fn ->
        render(Tincture.new(), tag: :yes)
      end
    end
  end

  describe "drawing is unchanged by tagging" do
    test "the same cells are drawn either way" do
      plain = render(Tincture.new(), header_rows: 1)
      tagged = tagged_document(header_rows: 1)

      for text <- ["Region", "Revenue", "North", "1,204", "South", "986"] do
        assert plain =~ text
        assert tagged =~ text
      end
    end

    test "the reported geometry is identical" do
      {_pdf, plain} = Table.render(Tincture.new(), 50, 700, [200, 120], @rows, header_rows: 1)

      {_pdf, tagged} =
        Table.render(Tincture.new(), 50, 700, [200, 120], @rows, header_rows: 1, tag: true)

      assert plain == tagged
    end

    test "border: false draws no artifacts, since there is nothing to skip" do
      binary = tagged_document(header_rows: 1, border: false)

      refute binary =~ "/Artifact BMC"
      assert count_elements(binary, "TD") == 4
    end

    test "auto column widths still work when tagging" do
      {_pdf, result} =
        Table.render(Tincture.new(), 50, 700, :auto, @rows, header_rows: 1, tag: true)

      assert length(result.widths) == 2
      assert Enum.all?(result.widths, &(&1 > 0))
    end

    test "an empty cell produces no element, having nothing to read" do
      rows = [["Region", ""], ["North", "1,204"]]

      binary =
        Tincture.new()
        |> Tincture.tag(:document, fn pdf ->
          {rendered, _} = Table.render(pdf, 50, 700, [200, 120], rows, header_rows: 1)
          rendered
        end)
        |> Tincture.export()

      # Three non-empty cells: one header, two body.
      assert count_elements(binary, "TH") == 1
      assert count_elements(binary, "TD") == 2
    end
  end

  describe "artifact/2" do
    test "brackets drawing as decoration" do
      binary =
        Tincture.new()
        |> Tincture.artifact(fn pdf ->
          pdf |> Tincture.line(10, 10, 100, 10) |> Tincture.stroke()
        end)
        |> Tincture.export()

      assert binary =~ "/Artifact BMC"
      assert binary =~ "EMC"
    end

    test "rejects a callback that does not return a document" do
      assert_raise ArgumentError, ~r/must return a %Tincture.PDF{}/, fn ->
        Tincture.artifact(Tincture.new(), fn _pdf -> :oops end)
      end
    end
  end
end
