defmodule Tincture.PageResourcesTest do
  @moduledoc """
  Every page carries /Resources.

  ISO 32000-1 Table 30 makes the entry required, and says what a page that
  needs nothing writes: "If the page requires no resources, the value of this
  entry shall be an empty dictionary. Omitting the entry entirely indicates
  that the resources shall be inherited from an ancestor node in the page
  tree." Tincture's /Pages carries no /Resources to inherit, so through 0.3.11
  a page whose content used no font, image, form XObject, graphics state or
  shading had no resources at all. Viewers repair this silently, and neither
  veraPDF profile in CI checks it.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.PDFObjects

  @examples Path.wildcard("examples/output/**/*.pdf")

  # Each page dictionary, in page order, as written.
  defp pages(binary) do
    %{objects: objects, trailer: trailer} = PDFObjects.read(binary)
    catalog = PDFObjects.resolve(trailer["Root"], objects)
    page_tree = PDFObjects.resolve(catalog["Pages"], objects)
    Enum.map(page_tree["Kids"], &PDFObjects.resolve(&1, objects))
  end

  # The page dictionaries' bytes, found by their /Type, for files the object
  # reader refuses: an incremental update, a cross-reference stream.
  defp page_dictionaries(binary) do
    ~r"\d+ 0 obj\s*(<<(?:(?!endobj).)*?/Type\s*/Page[\s/>](?:(?!endobj).)*?)endobj"s
    |> Regex.scan(binary, capture: :all_but_first)
    |> List.flatten()
  end

  defp one_page(pdf) do
    [page] = pdf |> Tincture.export() |> pages()
    page
  end

  describe "a page whose content uses no resources" do
    test "a blank page has an empty /Resources" do
      assert one_page(Tincture.new())["Resources"] == %{}
    end

    test "a page of paths only has an empty /Resources" do
      page =
        Tincture.new()
        |> Tincture.line(72, 700, 300, 700)
        |> Tincture.rectangle(72, 600, 100, 50)
        |> one_page()

      assert page["Resources"] == %{}
    end

    test "a page holding only a form field has an empty /Resources" do
      page = Tincture.new() |> Tincture.text_field(72, 700, 200, 20, "name") |> one_page()

      assert page["Resources"] == %{}
      assert [_widget] = page["Annots"]
    end

    test "a page holding only a link annotation has an empty /Resources" do
      page =
        Tincture.new() |> Tincture.link(72, 700, 120, 14, "https://hex.pm") |> one_page()

      assert page["Resources"] == %{}
      assert [_link] = page["Annots"]
    end

    test "it is written as the empty dictionary" do
      binary = Tincture.export(Tincture.new())
      assert binary =~ "/MediaBox [0 0 595 842] /Resources << >> /Contents"
    end
  end

  test "a text page keeps its resources, and the blank page after it gets an empty one" do
    [first, second] =
      Tincture.new()
      |> Tincture.set_font("Helvetica", 12)
      |> Tincture.text_at(72, 740, "Page one")
      |> Tincture.add_page()
      |> Tincture.export()
      |> pages()

    assert first["Resources"] == %{
             "Font" => %{
               "F1" => %{
                 "Type" => {:name, "Font"},
                 "Subtype" => {:name, "Type1"},
                 "BaseFont" => {:name, "Helvetica"}
               }
             }
           }

    assert second["Resources"] == %{}
  end

  test "the committed examples are present to check" do
    assert length(@examples) >= 10
  end

  for path <- @examples do
    test "every page of #{path} has /Resources" do
      dictionaries = unquote(path) |> File.read!() |> page_dictionaries()

      assert dictionaries != []

      for dictionary <- dictionaries do
        assert dictionary =~ "/Resources", "a page without /Resources: #{dictionary}"
      end
    end
  end
end
