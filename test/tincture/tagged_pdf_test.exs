defmodule Tincture.TaggedPDFTest do
  @moduledoc """
  Tests for tagged PDF — the logical structure that makes a document
  accessible.

  An untagged PDF records where each glyph sits and nothing about what it
  means, so assistive technology has no headings to navigate by, no table
  structure and no reliable reading order. Tagging adds a structure tree in the
  catalog plus marked content in the page linking drawn operators to it, and
  both halves have to agree — an element pointing at an MCID that no `BDC`
  emitted is as useless as no tagging at all.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF.Structure

  defp export(pdf), do: Tincture.export(pdf)

  defp struct_elements(binary) do
    ~r/^(\d+) 0 obj\n(<< \/Type \/StructElem.*?)\nendobj/ms
    |> Regex.scan(binary)
    |> Enum.map(fn [_, id, body] -> {String.to_integer(id), body} end)
  end

  defp element_of_type(binary, type) do
    binary
    |> struct_elements()
    |> Enum.filter(fn {_id, body} -> body =~ "/S /#{type} " end)
  end

  defp simple_tagged do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.set_font("Helvetica", 12)
    |> Tincture.tag(:document, fn pdf ->
      pdf
      |> Tincture.tag(:h1, &Tincture.text_at(&1, 50, 760, "Title"))
      |> Tincture.tag(:p, &Tincture.text_at(&1, 50, 730, "Body text."))
    end)
  end

  describe "the catalog" do
    test "declares the document tagged" do
      binary = export(simple_tagged())

      # Without /MarkInfo a reader may ignore the structure tree entirely.
      assert binary =~ "/MarkInfo << /Marked true >>"
      assert binary =~ ~r|/StructTreeRoot \d+ 0 R|
    end

    test "carries the document language" do
      assert export(simple_tagged()) =~ "/Lang (en-GB)"
    end

    test "an untagged document gains no structure entries" do
      binary = Tincture.new() |> Tincture.text_at(10, 10, "plain") |> export()

      refute binary =~ "/StructTreeRoot"
      refute binary =~ "/MarkInfo"
      refute binary =~ "BDC"
    end

    test "language can be set without tagging" do
      binary =
        Tincture.new()
        |> Tincture.set_language("fr")
        |> Tincture.text_at(10, 10, "bonjour")
        |> export()

      assert binary =~ "/Lang (fr)"
      refute binary =~ "/StructTreeRoot"
    end
  end

  describe "marked content" do
    test "content elements bracket what they draw" do
      binary = export(simple_tagged())

      assert binary =~ "/H1 <</MCID 0>> BDC"
      assert binary =~ "/P <</MCID 1>> BDC"
      assert length(Regex.scan(~r/BDC/, binary)) == 2
      assert length(Regex.scan(~r/EMC/, binary)) == 2
    end

    test "container elements emit none, having no content of their own" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:table, fn pdf ->
          Tincture.tag(pdf, :tr, fn pdf ->
            Tincture.tag(pdf, :td, &Tincture.text_at(&1, 10, 10, "cell"))
          end)
        end)
        |> export()

      # :table and :tr are containers; only :td draws.
      assert length(Regex.scan(~r/BDC/, binary)) == 1
      assert binary =~ "/TD <</MCID 0>> BDC"
    end

    test "marked-content ids are allocated per page, not per document" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:p, &Tincture.text_at(&1, 10, 10, "page one"))
        |> Tincture.add_page()
        |> Tincture.tag(:p, &Tincture.text_at(&1, 10, 10, "page two"))
        |> export()

      # Both start at 0: an MCID only has to be unique within its own stream.
      assert length(Regex.scan(~r|/P <</MCID 0>> BDC|, binary)) == 2
    end

    test "every BDC is closed" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:document, fn pdf ->
          pdf
          |> Tincture.tag(:h1, &Tincture.text_at(&1, 10, 700, "a"))
          |> Tincture.tag(:list, fn pdf ->
            Tincture.tag(pdf, :list_item, fn pdf ->
              Tincture.tag(pdf, :list_body, &Tincture.text_at(&1, 10, 680, "b"))
            end)
          end)
        end)
        |> export()

      assert length(Regex.scan(~r/BDC/, binary)) == length(Regex.scan(~r/EMC/, binary))
    end
  end

  describe "the structure tree" do
    setup do
      pdf =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:document, fn pdf ->
          pdf
          |> Tincture.tag(:h1, &Tincture.text_at(&1, 50, 760, "Title"))
          |> Tincture.tag(:table, fn pdf ->
            Tincture.tag(pdf, :tr, fn pdf ->
              pdf
              |> Tincture.tag(:th, [scope: :column], &Tincture.text_at(&1, 50, 700, "Region"))
              |> Tincture.tag(:td, &Tincture.text_at(&1, 200, 700, "North"))
            end)
          end)
        end)

      {:ok, pdf: pdf, binary: export(pdf)}
    end

    test "nests elements as they were nested in the calls", %{binary: binary} do
      assert [{document_id, document}] = element_of_type(binary, "Document")
      assert [{table_id, table}] = element_of_type(binary, "Table")
      assert [{tr_id, tr}] = element_of_type(binary, "TR")
      assert [{th_id, _}] = element_of_type(binary, "TH")
      assert [{td_id, _}] = element_of_type(binary, "TD")

      assert document =~ "#{table_id} 0 R"
      assert table =~ "/K [#{tr_id} 0 R]"
      assert tr =~ "/K [#{th_id} 0 R #{td_id} 0 R]"
      assert is_integer(document_id)
    end

    test "every element points back at its parent", %{binary: binary} do
      assert [{table_id, _}] = element_of_type(binary, "Table")
      assert [{tr_id, tr}] = element_of_type(binary, "TR")
      assert [{_, th}] = element_of_type(binary, "TH")

      assert tr =~ "/P #{table_id} 0 R"
      assert th =~ "/P #{tr_id} 0 R"
    end

    test "root elements point at the structure tree root", %{binary: binary} do
      assert [_, root_id] = Regex.run(~r|/StructTreeRoot (\d+) 0 R|, binary)
      assert [{_, document}] = element_of_type(binary, "Document")

      assert document =~ "/P #{root_id} 0 R"
    end

    test "content elements claim their marked-content id", %{binary: binary} do
      assert [{_, h1}] = element_of_type(binary, "H1")
      assert h1 =~ "/K [0]"
    end

    test "containers claim no marked-content id", %{binary: binary} do
      assert [{_, table}] = element_of_type(binary, "Table")

      # /K holds only element references, no bare integer.
      assert table =~ ~r|/K \[\d+ 0 R\]|
    end

    test "every element records the page it appears on", %{binary: binary} do
      for {_id, body} <- struct_elements(binary) do
        assert body =~ ~r|/Pg \d+ 0 R|
      end
    end

    test "the parent tree maps each marked-content id back to its element",
         %{binary: binary} do
      assert [_, nums] = Regex.run(~r|/Nums \[0 \[([^\]]+)\]\]|, binary)
      refs = Regex.scan(~r/(\d+) 0 R/, nums) |> Enum.map(&String.to_integer(Enum.at(&1, 1)))

      assert [{h1_id, _}] = element_of_type(binary, "H1")
      assert [{th_id, _}] = element_of_type(binary, "TH")
      assert [{td_id, _}] = element_of_type(binary, "TD")

      # Indexed by MCID: h1 was tagged first, then th, then td.
      assert refs == [h1_id, th_id, td_id]
    end

    test "the object graph is sound", %{binary: binary} do
      ids =
        ~r/^(\d+) 0 obj/m
        |> Regex.scan(binary)
        |> Enum.map(fn [_, id] -> String.to_integer(id) end)

      refs =
        ~r/(\d+) 0 R/
        |> Regex.scan(binary)
        |> Enum.map(fn [_, id] -> String.to_integer(id) end)
        |> Enum.uniq()

      assert refs -- ids == []
      assert ids == Enum.to_list(1..length(ids))
    end
  end

  describe "accessibility metadata" do
    test "a figure carries alternative text" do
      binary =
        Tincture.new()
        |> Tincture.tag(:figure, [alt: "Bar chart of revenue"], fn pdf ->
          Tincture.rectangle(pdf, 10, 10, 50, 50, :fill)
        end)
        |> export()

      assert binary =~ "/Alt (Bar chart of revenue)"
    end

    test "a header cell records the cells it governs" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:th, [scope: :row], &Tincture.text_at(&1, 10, 10, "Total"))
        |> export()

      # In an attribute dictionary owned by /Table, not as a direct key. A bare
      # /Scope is ignored by a reader, which leaves the table's structure
      # undeterminable and fails ISO 14289-1 clause 7.5. veraPDF caught this.
      assert binary =~ "/A << /O /Table /Scope /Row >>"
    end

    test "carries actual text, for when the glyphs are not the words" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:span, [actual_text: "ffi"], &Tincture.text_at(&1, 10, 10, "ﬃ"))
        |> export()

      assert binary =~ "/ActualText (ffi)"
    end

    test "an element can override the document language" do
      binary =
        Tincture.new()
        |> Tincture.set_language("en-GB")
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:p, [lang: "cy"], &Tincture.text_at(&1, 10, 10, "Croeso"))
        |> export()

      assert binary =~ "/Lang (en-GB)"
      assert binary =~ "/Lang (cy)"
    end

    test "a title is carried through" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.tag(:section, [title: "Appendix"], fn pdf ->
          Tincture.tag(pdf, :p, &Tincture.text_at(&1, 10, 10, "text"))
        end)
        |> export()

      assert binary =~ "/T (Appendix)"
    end
  end

  describe "validation" do
    test "rejects an unknown tag, listing the ones it knows" do
      error =
        assert_raise ArgumentError, fn ->
          Tincture.tag(Tincture.new(), :marquee, & &1)
        end

      assert error.message =~ "unknown structure tag: :marquee"
      assert error.message =~ ":p"
    end

    test "rejects :scope on anything but a header cell" do
      assert_raise ArgumentError, ~r/:scope only applies to a :th/, fn ->
        Tincture.tag(Tincture.new(), :p, [scope: :row], & &1)
      end
    end

    test "rejects an invalid scope" do
      assert_raise ArgumentError, ~r/:scope must be :row, :column or :both/, fn ->
        Tincture.tag(Tincture.new(), :th, [scope: :diagonal], & &1)
      end
    end

    test "rejects a callback that does not return a document" do
      assert_raise ArgumentError, ~r/must return a %Tincture.PDF{}/, fn ->
        Tincture.tag(Tincture.new(), :p, fn _pdf -> :oops end)
      end
    end

    test "rejects an empty language" do
      assert_raise ArgumentError, ~r/non-empty string/, fn ->
        Tincture.set_language(Tincture.new(), "")
      end
    end
  end

  describe "tagged?/1" do
    test "is false until something is tagged" do
      refute Tincture.tagged?(Tincture.new())
      refute Tincture.new() |> Tincture.text_at(10, 10, "x") |> Tincture.tagged?()
    end

    test "is true once an element is closed" do
      assert Tincture.new()
             |> Tincture.tag(:p, &Tincture.text_at(&1, 10, 10, "x"))
             |> Tincture.tagged?()
    end
  end

  describe "Structure" do
    test "classifies every known tag as container or content, never both" do
      for {tag, _name} <- Structure.tags() do
        assert Structure.container?(tag) != Structure.content?(tag),
               "#{inspect(tag)} must be exactly one of container or content"
      end
    end

    test "maps tags to their specification names" do
      assert Structure.tag_name(:h1) == "H1"
      assert Structure.tag_name(:list) == "L"
      assert Structure.tag_name(:list_body) == "LBody"
      assert Structure.tag_name(:block_quote) == "BlockQuote"
    end

    test "flattens a tree parents-first, so a parent is always numbered before its kids" do
      tree = [
        %{
          tag: :document,
          page_number: 1,
          mcid: nil,
          kids: [
            %{tag: :h1, page_number: 1, mcid: 0, kids: []},
            %{tag: :p, page_number: 1, mcid: 1, kids: []}
          ]
        }
      ]

      assert Structure.flatten(tree) |> Enum.map(& &1.tag) == [:document, :h1, :p]
    end
  end
end
