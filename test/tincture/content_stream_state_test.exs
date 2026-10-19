defmodule Tincture.ContentStreamStateTest do
  use ExUnit.Case, async: true

  alias Tincture.Layout.Box
  alias Tincture.Layout.Template
  alias Tincture.Test.ContentStreamState
  alias Tincture.Test.FixtureDocuments
  alias Tincture.Test.StructureLayout
  alias Tincture.Typography.RichText

  # Every PDF Tincture can be seen writing - the committed examples, the locked
  # fixtures, every showcase, and a build of each layout module - is held to
  # what a validator does not check:
  #
  #   * content streams follow the operator order of ISO 32000-1 Figure 9.
  #     Viewers skip an operator in the wrong state and veraPDF does not check
  #     the order, so a violation is invisible until a stricter consumer
  #     refuses the file;
  #   * structure elements carry the layout attributes §14.8.5.4 calls for: a
  #     /BBox on every Figure, and /Placement /Block on exactly the inline
  #     elements that sit in a grouping element;
  #   * an example with headings has an outline, so the navigation the
  #     headings offer is available without walking the structure tree.

  @examples Path.wildcard("examples/output/**/*.pdf")

  test "the committed examples are present to check" do
    assert length(@examples) >= 10
  end

  for path <- @examples do
    test "example #{path}" do
      assert_clean(File.read!(unquote(path)), unquote(path), outline: true)
    end
  end

  for name <- FixtureDocuments.names() do
    test "fixture #{name}" do
      assert_clean(FixtureDocuments.build(unquote(name)))
    end
  end

  test "every locked fixture is covered" do
    locked =
      "test/fixtures/pdf/*.sha256"
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".sha256"))

    assert Enum.sort(locked) == Enum.sort(FixtureDocuments.names())
  end

  describe "showcases" do
    test "every Showcase module" do
      {:ok, modules} = :application.get_key(:tincture, :modules)

      showcases =
        Enum.filter(
          modules,
          &String.starts_with?(Atom.to_string(&1), "Elixir.Tincture.Showcase.")
        )

      assert length(showcases) >= 5

      for module <- showcases do
        Code.ensure_loaded!(module)

        assert function_exported?(module, :pdf_binary, 0),
               "#{inspect(module)} has no pdf_binary/0 to check"

        assert_clean(module.pdf_binary(), inspect(module))
      end
    end

    test "the bank statement's second variant" do
      assert_clean(Tincture.Showcase.BankStatement.pdf_binary(:joint_fee_interest))
    end
  end

  test "Layout.Box" do
    rich =
      RichText.from_plain("A box of text that wraps over a few lines. " |> String.duplicate(6))

    pdf =
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.tag(:document, fn pdf ->
        pdf |> Box.flow_text(72, 700, 300, 200, rich) |> elem(0)
      end)

    assert_clean(Tincture.export(pdf), "Layout.Box", tagged: true)
  end

  test "Layout.Template" do
    rich =
      RichText.from_plain("Body text that runs onto a second page. " |> String.duplicate(400))

    template =
      Template.new(columns: 2)
      |> Template.with_header("Header")
      |> Template.with_footer("Page {page}")

    {pdf, result} =
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.PDF.begin_structure(:document)
      |> Template.render_document(template, rich)

    pdf = Tincture.PDF.end_structure(pdf)

    assert result.pages_used > 1
    assert_clean(Tincture.export(pdf), "Layout.Template", tagged: true)
  end

  defp assert_clean(pdf, label \\ nil, opts \\ []) do
    label = label || "document"
    %{streams: streams, violations: violations} = ContentStreamState.check_pdf(pdf)

    assert streams > 0, "#{label}: no content stream was found to check"

    assert violations == [],
           Enum.map_join(
             violations,
             "\n",
             &"#{label}: #{ContentStreamState.format_violation(&1)}"
           )

    layout = StructureLayout.check(pdf)

    assert layout.problems == [], Enum.map_join(layout.problems, "\n", &"#{label}: #{&1}")

    if opts[:tagged], do: assert(layout.elements > 0, "#{label}: no structure element to check")

    if opts[:outline] && layout.headings?,
      do: assert(layout.outlines?, "#{label}: has headings but no /Outlines in its catalog")
  end
end
