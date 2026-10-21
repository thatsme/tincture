defmodule Tincture.PDF.ContentStreamTest do
  @moduledoc """
  A document's operations are addressed as content streams, named by a key.
  Only page streams exist so far, keyed `{:page, n}`: `stream_operations/2`
  reads one, `current_stream/1` names the one drawing goes to, and each
  resource collector works from one stream's operations.
  """
  use ExUnit.Case, async: true

  alias Tincture.PDF
  alias Tincture.PDF.Serialize

  defp three_pages do
    Tincture.new()
    |> Tincture.text_at(72, 700, "one")
    |> Tincture.add_page()
    |> Tincture.rectangle(72, 600, 100, 50)
    |> Tincture.add_page()
    |> Tincture.text_at(72, 700, "three")
    |> Tincture.set_page(1)
    |> Tincture.text_at(72, 650, "one again")
  end

  describe "stream_operations/2" do
    test "agrees with page_operations/2 on every page" do
      pdf = three_pages()

      for page <- PDF.page_numbers(pdf) do
        assert PDF.stream_operations(pdf, {:page, page}) == PDF.page_operations(pdf, page)
      end

      assert PDF.page_numbers(pdf) == [1, 2, 3]
      assert length(PDF.stream_operations(pdf, {:page, 1})) == 2
    end

    test "agrees with page_operations/2 on an unknown page: both give []" do
      pdf = three_pages()

      assert PDF.stream_operations(pdf, {:page, 4}) == []
      assert PDF.page_operations(pdf, 4) == []
    end
  end

  describe "current_stream/1" do
    test "is page 1 in a new document" do
      assert PDF.current_stream(Tincture.new()) == {:page, 1}
    end

    test "follows add_page/1 and set_page/2" do
      pdf = Tincture.new() |> Tincture.add_page()
      assert PDF.current_stream(pdf) == {:page, 2}

      pdf = Tincture.add_page(pdf)
      assert PDF.current_stream(pdf) == {:page, 3}

      pdf = Tincture.set_page(pdf, 1)
      assert PDF.current_stream(pdf) == {:page, 1}
    end

    test "append_current_op/2 appends to the current stream only" do
      pdf = Tincture.new() |> Tincture.add_page() |> Tincture.set_page(1)
      pdf = PDF.append_current_op(pdf, :stroke)

      assert PDF.stream_operations(pdf, {:page, 1}) == [:stroke]
      assert PDF.stream_operations(pdf, {:page, 2}) == []
      assert pdf.operations == [:stroke]
    end
  end

  describe "resource collectors, on a hand-built operations list" do
    test "font_resources/2 names each font once, embedded by reference" do
      ops = [
        {:text_at, 0, 0, "a", {"Helvetica", 12}},
        {:text_at_rotated, 0, 0, 90, "b", {"Body", 10}},
        {:text_at, 0, 0, "c", {"Helvetica", 9}},
        :stroke
      ]

      assert Serialize.font_resources(ops, %{"Body" => 17}) ==
               {%{"Helvetica" => "F1", "Body" => "F2"},
                "/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> /F2 17 0 R"}
    end

    test "xobject_resources/2 names each image once" do
      ops = [{:image, 0, 0, 10, 10, 2}, {:image, 5, 5, 10, 10, 2}, {:image, 0, 0, 1, 1, 1}]
      refs = %{1 => %{main: 30}, 2 => %{main: 31, smask: 32}}

      assert Serialize.xobject_resources(ops, refs) == "/Im2 31 0 R /Im1 30 0 R"
    end

    test "ext_gstate_resources/1 gives one graphics state per distinct alpha pair" do
      ops = [{:set_alpha, 0.5, 1.0}, {:set_alpha, 0.5, 1.0}, {:set_alpha, 0.25, 0.25}]

      assert Serialize.ext_gstate_resources(ops) ==
               {%{{0.5, 1.0} => "GS0", {0.25, 0.25} => "GS1"},
                "/GS0 << /Type /ExtGState /ca 0.5 /CA 1.0 >> " <>
                  "/GS1 << /Type /ExtGState /ca 0.25 /CA 0.25 >>"}
    end

    test "shading_resources/1 gives one shading per distinct shading" do
      shading = %{
        type: :axial,
        coords: [0, 0, 100, 0],
        stops: [{0, {1, 0, 0}}, {1, {0, 0, 1}}],
        extend: {true, true}
      }

      ops = [{:shading, 0, 0, 100, 10, shading}, {:shading, 0, 20, 100, 10, shading}]

      assert {%{^shading => "Sh0"}, "/Sh0 << /ShadingType 2 " <> _rest} =
               Serialize.shading_resources(ops)
    end

    test "an empty operations list needs no resources" do
      assert Serialize.font_resources([], %{}) == {%{}, ""}
      assert Serialize.xobject_resources([], %{}) == ""
      assert Serialize.ext_gstate_resources([]) == {%{}, ""}
      assert Serialize.shading_resources([]) == {%{}, ""}
    end
  end
end
