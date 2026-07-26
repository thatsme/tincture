defmodule Tincture.LinkTest do
  use ExUnit.Case, async: true

  defp annots(pdf_binary) do
    case Regex.run(~r/\/Annots \[(.*?)\]\s*>>\s*endobj/s, pdf_binary) do
      [_, body] -> body
      _ -> nil
    end
  end

  describe "link/6 with an external URL" do
    test "emits a Link annotation with a URI action" do
      binary =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, "https://elixir-lang.org")
        |> Tincture.export()

      assert binary =~ "/Type /Annot"
      assert binary =~ "/Subtype /Link"
      assert binary =~ "/A << /S /URI /URI (https://elixir-lang.org) >>"
    end

    test "accepts the explicit {:url, url} form" do
      binary =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, {:url, "https://hex.pm"})
        |> Tincture.export()

      assert binary =~ "/URI (https://hex.pm)"
    end

    test "converts x/y/width/height into a lower-left/upper-right rect" do
      binary =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, "https://example.com")
        |> Tincture.export()

      assert binary =~ "/Rect [72 700 192 714]"
    end

    test "normalises a negative width or height instead of emitting a dead rect" do
      binary =
        Tincture.new()
        |> Tincture.link(192, 714, -120, -14, "https://example.com")
        |> Tincture.export()

      assert binary =~ "/Rect [72 700 192 714]"
    end

    test "escapes characters that would break a PDF literal string" do
      binary =
        Tincture.new()
        |> Tincture.link(0, 0, 10, 10, "https://example.com/a(b)c\\d")
        |> Tincture.export()

      assert binary =~ "/S /URI"
      # The parens and backslash must not terminate the literal early.
      assert binary =~ "\\(" and binary =~ "\\)"
    end
  end

  describe "link/6 with an internal page target" do
    test "resolves to the target page's object reference" do
      binary =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, {:page, 2})
        |> Tincture.add_page()
        |> Tincture.text_at(72, 700, "second")
        |> Tincture.export()

      # Page objects are 3, 5, 7... so page 2 is object 5.
      assert binary =~ "/Dest [5 0 R /XYZ null null null]"
    end

    test "supports linking forward to a page that does not exist yet" do
      # A table of contents is written before the pages it points at.
      binary =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, {:page, 3})
        |> Tincture.add_page()
        |> Tincture.add_page()
        |> Tincture.export()

      assert binary =~ "/Dest [7 0 R"
    end

    test "raises at export when the target page never materialises" do
      pdf = Tincture.link(Tincture.new(), 72, 700, 120, 14, {:page, 9})

      assert_raise ArgumentError, ~r/page 9, which does not exist/, fn ->
        Tincture.export(pdf)
      end
    end
  end

  describe "annotation placement" do
    test "a document with no links has no /Annots entry at all" do
      binary =
        Tincture.new()
        |> Tincture.text_at(72, 700, "no links here")
        |> Tincture.export()

      refute binary =~ "/Annots"
    end

    test "links attach to the current page by default" do
      binary =
        Tincture.new()
        |> Tincture.add_page()
        |> Tincture.link(72, 700, 120, 14, "https://example.com")
        |> Tincture.export()

      # Only the second page object carries the annotation.
      [_, first_page_body, second_page_body] =
        Regex.run(~r/(\/Type \/Page .*?)endobj.*?(\/Type \/Page .*?)endobj/s, binary)

      refute first_page_body =~ "/Annots"
      assert second_page_body =~ "/Annots"
    end

    test ":page option attaches a link to an explicit page" do
      binary =
        Tincture.new()
        |> Tincture.add_page()
        |> Tincture.link(72, 700, 120, 14, "https://example.com", page: 1)
        |> Tincture.export()

      [_, first_page_body, second_page_body] =
        Regex.run(~r/(\/Type \/Page .*?)endobj.*?(\/Type \/Page .*?)endobj/s, binary)

      assert first_page_body =~ "/Annots"
      refute second_page_body =~ "/Annots"
    end

    test "multiple links on one page all appear in its /Annots array" do
      binary =
        Tincture.new()
        |> Tincture.link(0, 0, 10, 10, "https://one.example")
        |> Tincture.link(0, 20, 10, 10, "https://two.example")
        |> Tincture.link(0, 40, 10, 10, "https://three.example")
        |> Tincture.export()

      body = annots(binary)
      assert body =~ "one.example"
      assert body =~ "two.example"
      assert body =~ "three.example"
    end

    test "raises for a page that does not exist" do
      assert_raise ArgumentError, ~r/unknown page: 4/, fn ->
        Tincture.link(Tincture.new(), 0, 0, 10, 10, "https://example.com", page: 4)
      end
    end
  end

  describe "borders" do
    test "defaults to no visible border" do
      binary =
        Tincture.new()
        |> Tincture.link(0, 0, 10, 10, "https://example.com")
        |> Tincture.export()

      assert binary =~ "/Border [0 0 0]"
    end

    test "accepts an explicit border" do
      binary =
        Tincture.new()
        |> Tincture.link(0, 0, 10, 10, "https://example.com", border: {0, 0, 2})
        |> Tincture.export()

      assert binary =~ "/Border [0 0 2]"
    end

    test "rejects a malformed border" do
      assert_raise ArgumentError, ~r/border must be/, fn ->
        Tincture.link(Tincture.new(), 0, 0, 10, 10, "https://example.com", border: :thick)
      end
    end
  end

  describe "text_link/5" do
    test "draws the text and covers it with a link" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(72, 700, "Elixir", "https://elixir-lang.org")
        |> Tincture.export()

      assert binary =~ "(Elixir) Tj"
      assert binary =~ "/Subtype /Link"
      assert binary =~ "/URI (https://elixir-lang.org)"
    end

    test "sizes the rect from the measured text width" do
      narrow =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(0, 100, "i", "https://example.com")
        |> Tincture.export()

      wide =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(0, 100, "wwwwwwwwww", "https://example.com")
        |> Tincture.export()

      [[_, narrow_x2]] = Regex.scan(~r/\/Rect \[[\d.]+ [\d.]+ ([\d.]+) /, narrow)
      [[_, wide_x2]] = Regex.scan(~r/\/Rect \[[\d.]+ [\d.]+ ([\d.]+) /, wide)

      assert String.to_float(wide_x2) > String.to_float(narrow_x2)
    end

    test "leaves the fill colour alone by default" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(72, 700, "plain", "https://example.com")
        |> Tincture.export()

      refute binary =~ "rg"
    end

    test ":color wraps the colour change in a save/restore so it does not leak" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(72, 700, "blue", "https://example.com", color: {0.0, 0.3, 0.8})
        |> Tincture.text_at(72, 680, "should not be blue")
        |> Tincture.export()

      assert binary =~ "q\n0.0 0.3 0.8 rg"
      assert binary =~ "Q"

      # The restore must come before the following text is drawn.
      restore_index = :binary.match(binary, "Q") |> elem(0)
      later_text_index = :binary.match(binary, "(should not be blue)") |> elem(0)
      assert restore_index < later_text_index
    end

    test "supports an internal page target" do
      binary =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(72, 700, "See page 2", {:page, 2})
        |> Tincture.add_page()
        |> Tincture.export()

      assert binary =~ "(See page 2) Tj"
      assert binary =~ "/Dest [5 0 R"
    end
  end

  describe "invalid targets" do
    test "rejects a target that is neither a URL nor a page" do
      assert_raise ArgumentError, ~r/link target must be/, fn ->
        Tincture.link(Tincture.new(), 0, 0, 10, 10, {:section, "intro"})
      end
    end

    test "rejects an empty URL" do
      assert_raise ArgumentError, ~r/link target must be/, fn ->
        Tincture.link(Tincture.new(), 0, 0, 10, 10, "")
      end
    end
  end
end
