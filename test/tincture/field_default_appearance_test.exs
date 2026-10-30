defmodule Tincture.FieldDefaultAppearanceTest do
  @moduledoc """
  The size a field's /DA names.

  An auto-sized field in an embedded font names the size its own appearance
  draws at, never 0: Acrobat Reader (2026.002.22031) does not redraw such a
  field at auto size after an edit to a value its embedded font draws alone,
  and keeps showing the old appearance while /V holds the new value. At the
  resolved size it redraws. A standard-14 field keeps 0, which Reader redraws.
  """
  use ExUnit.Case, async: true

  @sans "examples/fonts/LiberationSans-Regular.ttf"
  @examples Path.wildcard("examples/output/**/*.pdf")

  defp with_sans(pdf), do: Tincture.register_ttf_font(pdf, "Sans", @sans, subset: :none)

  defp widget(binary, name) do
    case Regex.run(
           ~r/<< \/Type \/Annot \/Subtype \/Widget[^>]*\/T \(#{name}\)(?:<<[^>]*>>|<[0-9A-F]*>|[^<>])*>>/,
           binary
         ) do
      [object] -> object
      _ -> flunk("no widget named #{name}")
    end
  end

  # The /DA of the field `name`: {font alias, size as written}.
  defp default_appearance(binary, name) do
    [_, font, size] = Regex.run(~r"/DA \(/(\S+) (\S+) Tf 0 g\)", widget(binary, name))
    {font, size}
  end

  # Every Tf in the field's appearance stream: [{font alias, size as written}].
  defp appearance_sizes(binary, name) do
    [_, id] = Regex.run(~r/\/AP << \/N (\d+) 0 R >>/, widget(binary, name))

    [_, content] =
      Regex.run(~r/\n#{id} 0 obj\n<< \/Type \/XObject .*? >>\nstream\n(.*?)\nendstream/s, binary)

    ~r"/(\S+) (\S+) Tf"
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(&List.to_tuple/1)
  end

  # The alias of every /DR font that is a Type0 (an embedded font).
  defp embedded_aliases(binary) do
    case Regex.run(~r"/DR << /Font << (.*?) >> >>", binary) do
      [_, fonts] ->
        for [font, id] <- Regex.scan(~r"/(\S+) (\d+) 0 R", fonts, capture: :all_but_first),
            binary =~ ~r"\n#{id} 0 obj\n<< /Type /Font /Subtype /Type0 ",
            do: font

      nil ->
        []
    end
  end

  # Every /DA in the file whose font is an embedded one, by its size.
  defp embedded_default_appearance_sizes(binary) do
    embedded = embedded_aliases(binary)

    for [font, size] <- Regex.scan(~r"/DA \(/(\S+) (\S+) Tf", binary, capture: :all_but_first),
        font in embedded,
        do: size
  end

  defp review_document do
    Tincture.new()
    |> with_sans()
    |> Tincture.text_field(72, 700, 240, 22, "greek",
      value: "Ελλάδα",
      font: "Sans",
      full_font: true
    )
    |> Tincture.text_field(72, 650, 240, 22, "empty", font: "Sans", full_font: true)
    |> Tincture.text_field(72, 600, 240, 22, "secret",
      value: "x",
      password: true,
      font: "Sans",
      full_font: true
    )
    |> Tincture.text_field(72, 520, 400, 56, "notes",
      value: "Πρώτη γραμμή.\nSecond line.",
      multiline: true,
      font: "Sans",
      full_font: true
    )
    |> Tincture.choice_field(72, 470, 240, 22, "city",
      options: ["Αθήνα", "Πάτρα"],
      value: "Πάτρα",
      font: "Sans",
      full_font: true
    )
    |> Tincture.choice_field(72, 400, 240, 50, "pick",
      options: ["ένα", "δύο", "τρία"],
      value: "δύο",
      dropdown: false,
      font: "Sans",
      full_font: true
    )
    |> Tincture.text_field(330, 700, 240, 22, "latin", value: "Ada Lovelace")
    |> Tincture.export()
  end

  describe "an auto-sized field in an embedded font" do
    test "a text field's /DA names the size its appearance draws at" do
      binary = review_document()
      {"Sans", size} = default_appearance(binary, "greek")

      refute size == "0"
      assert appearance_sizes(binary, "greek") == [{"Sans", size}]
    end

    test "a combo box's /DA names the size its appearance draws at" do
      binary = review_document()
      {"Sans", size} = default_appearance(binary, "city")

      refute size == "0"
      assert appearance_sizes(binary, "city") == [{"Sans", size}]
    end

    test "a multiline field and a list box name theirs, every line at that size" do
      binary = review_document()

      for name <- ["notes", "pick"] do
        {"Sans", size} = default_appearance(binary, name)
        refute size == "0"
        assert [_ | _] = sizes = appearance_sizes(binary, name)
        assert Enum.uniq(sizes) == [{"Sans", size}]
      end
    end

    test "an empty field and a password field, which draw no text, name the size their box gives" do
      binary = review_document()
      {"Sans", greek} = default_appearance(binary, "greek")
      refute greek == "0"

      # The same 22-point box as the Greek field, whose value fits it.
      assert default_appearance(binary, "empty") == {"Sans", greek}
      assert default_appearance(binary, "secret") == {"Sans", greek}
      assert appearance_sizes(binary, "empty") == []
      assert appearance_sizes(binary, "secret") == []
    end
  end

  test "a Helvetica field at auto size keeps 0 in /DA, while its appearance resolves a size" do
    binary = review_document()

    assert default_appearance(binary, "latin") == {"Helv", "0"}
    assert [{"Helv", size}] = appearance_sizes(binary, "latin")
    refute size == "0"
  end

  test "an explicit size is written in both places, for an embedded font and for Helvetica" do
    binary =
      Tincture.new()
      |> with_sans()
      |> Tincture.text_field(72, 700, 240, 22, "sans9", value: "Ελλάδα", font: "Sans", size: 9)
      |> Tincture.text_field(72, 650, 240, 22, "helv9", value: "Ada", size: 9)
      |> Tincture.export()

    assert default_appearance(binary, "sans9") == {"Sans", "9"}
    assert appearance_sizes(binary, "sans9") == [{"Sans", "9"}]
    assert default_appearance(binary, "helv9") == {"Helv", "9"}
    assert appearance_sizes(binary, "helv9") == [{"Helv", "9"}]
  end

  describe "no embedded-font field anywhere names 0" do
    test "in the review document" do
      sizes = embedded_default_appearance_sizes(review_document())

      assert length(sizes) == 6
      refute "0" in sizes
    end

    for path <- @examples do
      test "in #{path}" do
        refute "0" in embedded_default_appearance_sizes(File.read!(unquote(path)))
      end
    end
  end
end
