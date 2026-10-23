defmodule Tincture.FieldAppearanceTest do
  @moduledoc """
  Text and choice fields carry their own appearance stream (/AP /N), laid out
  by Tincture, so they display the same in every viewer and wherever no
  viewer regenerates them. /NeedAppearances is never written.

  The layout rules are those of docs/design/0.4.0-forms.md, section D; the
  bytes asserted here are the ones it gives.
  """
  use ExUnit.Case, async: true

  @sans "examples/fonts/LiberationSans-Regular.ttf"

  defp export(pdf), do: Tincture.export(pdf)

  # The widget dictionary of the field `name`, which may hold one level of
  # nested dictionary (/AP's).
  defp widget(binary, name) do
    case Regex.run(
           ~r/<< \/Type \/Annot \/Subtype \/Widget[^>]*\/T \(#{name}\)(?:<<[^>]*>>|<[0-9A-F]*>|[^<>])*>>/,
           binary
         ) do
      [object] -> object
      _ -> flunk("no widget named #{name}")
    end
  end

  # The appearance stream of the field `name`: {dictionary, content}.
  defp appearance(binary, name) do
    [_, id] = Regex.run(~r/\/AP << \/N (\d+) 0 R >>/, widget(binary, name))

    [_, dictionary, content] =
      Regex.run(
        ~r/\n#{id} 0 obj\n(<< \/Type \/XObject .*? >>)\nstream\n(.*?)\nendstream/s,
        binary
      )

    {dictionary, content}
  end

  defp content(binary, name), do: binary |> appearance(name) |> elem(1)

  defp single(opts, size \\ {200, 24}) do
    {w, h} = size
    Tincture.new() |> Tincture.text_field(72, 700, w, h, "f", opts) |> export()
  end

  defp list_box(options, value, height \\ 54) do
    Tincture.new()
    |> Tincture.choice_field(72, 600, 200, height, "c",
      options: options,
      value: value,
      dropdown: false
    )
    |> export()
  end

  describe "the bytes of section D" do
    test "a single-line field" do
      assert content(single(value: "Ada Lovelace"), "f") ==
               "/Tx BMC\nq\n1 1 198 22 re\nW\nn\n0 0 0 rg\nBT\n/Helv 12 Tf\n2 9 Td\n" <>
                 "(Ada Lovelace) Tj\nET\nQ\nEMC\n"
    end

    test "a list box with its selection drawn on a band" do
      assert content(list_box(["Italy", "Norway", "Japan"], "Norway"), "c") ==
               "/Tx BMC\nq\n1 1 198 52 re\nW\nn\n0.6 0.75 0.9 rg\n1 25.4 198 13.8 re\nf\n" <>
                 "0 0 0 rg\nBT\n/Helv 12 Tf\n2 43.1 Td\n(Italy) Tj\nET\n" <>
                 "BT\n/Helv 12 Tf\n2 29.3 Td\n(Norway) Tj\nET\n" <>
                 "BT\n/Helv 12 Tf\n2 15.5 Td\n(Japan) Tj\nET\nQ\nEMC\n"
    end
  end

  describe "the appearance dictionary" do
    test "every text and choice widget has /AP with only /N, a stream, and no /AS" do
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 700, 200, 24, "t", value: "x")
        |> Tincture.text_field(72, 650, 200, 24, "p", value: "x", password: true)
        |> Tincture.text_field(72, 550, 200, 60, "m", value: "x", multiline: true)
        |> Tincture.choice_field(72, 500, 200, 24, "c", options: ["a"])
        |> Tincture.choice_field(72, 400, 200, 54, "l", options: ["a"], dropdown: false)
        |> export()

      for name <- ~w(t p m c l) do
        widget = widget(binary, name)
        assert widget =~ ~r/\/AP << \/N \d+ 0 R >>/
        refute widget =~ "/AS"
        refute widget =~ ~r"/AP << [^>]*/(R|D) "

        {dictionary, _content} = appearance(binary, name)
        assert dictionary =~ "/Type /XObject /Subtype /Form"
      end
    end

    test "/BBox is the widget's size" do
      {dictionary, _content} = appearance(single([value: "x"], {150, 30}), "f")
      assert dictionary =~ "/BBox [0 0 150 30]"
    end

    test "a standard font is the /DR dictionary under the /DA alias, with WinAnsi" do
      {dictionary, content} = appearance(single(value: "x", font: "Courier"), "f")

      assert dictionary =~
               "/Resources << /Font << /Courier << /Type /Font /Subtype /Type1 " <>
                 "/BaseFont /Courier /Encoding /WinAnsiEncoding >> >> >>"

      assert content =~ "/Courier 12 Tf"
    end

    test "standard-14 text is written in WinAnsi, not UTF-16" do
      content = content(single(value: "Größe"), "f")
      assert content =~ ~S"(Gr\366\337e) Tj"
      refute content =~ "FEFF"
    end
  end

  describe "the /Tx marking, the clip and the border" do
    test "with no border, everything is inside the marking, clipped 1 point in" do
      assert content(single(value: "x"), "f") =~ ~r/\A\/Tx BMC\nq\n1 1 198 22 re\nW\nn\n/
    end

    test "a border is stroked before the marking, and the clip is inset by its width" do
      content = content(single(value: "x", border: {0, 0, 2}), "f")

      assert content =~
               ~r/\A0 0 0 RG\n2 w\n1 1 198 22 re\nS\n\/Tx BMC\nq\n2 2 196 20 re\nW\nn\n/

      assert content =~ ~r/\n3 \S+ Td\n/
    end

    test "nothing to draw is an empty marking" do
      assert content(single([]), "f") == "/Tx BMC\nEMC\n"

      binary =
        Tincture.new() |> Tincture.choice_field(72, 700, 200, 24, "c", options: ["a"]) |> export()

      assert content(binary, "c") == "/Tx BMC\nEMC\n"
    end

    test "a password field draws nothing, though its value is still /V" do
      binary = single(value: "secret", password: true)
      assert content(binary, "f") == "/Tx BMC\nEMC\n"
      assert widget(binary, "f") =~ "/V (secret)"
    end
  end

  describe "the auto size" do
    defp size_of(content) do
      [_, size] = Regex.run(~r/\/Helv (\S+) Tf/, content)
      String.to_float(size <> if(String.contains?(size, "."), do: "", else: ".0"))
    end

    test "is 12 when the line fits" do
      assert size_of(content(single(value: "Ada"), "f")) == 12
    end

    test "follows a short box's height" do
      # (12 - 2) / 1.15
      assert size_of(content(single([value: "Ada"], {200, 12}), "f")) == 8.6957
    end

    test "is scaled down to the width for a long value, not below 4" do
      long = String.duplicate("W", 40)
      size = size_of(content(single([value: long], {200, 24}), "f"))
      assert size < 12 and size >= 4

      width = Tincture.Font.text_width("Helvetica", size, long)
      assert_in_delta width, 196, 0.01

      assert size_of(content(single([value: String.duplicate("W", 400)], {200, 24}), "f")) == 4
    end

    test "a fixed size is kept, and /DA keeps 0 Tf for an auto size" do
      binary = single(value: "Ada", size: 9)
      assert content(binary, "f") =~ "/Helv 9 Tf"
      assert widget(binary, "f") =~ "/DA (/Helv 9 Tf 0 g)"
      assert widget(single(value: "Ada"), "f") =~ "/DA (/Helv 0 Tf 0 g)"
    end
  end

  describe "multiline" do
    defp lines(content), do: for([_, text] <- Regex.scan(~r/\((.*?)\) Tj/, content), do: text)

    test "breaks at line breaks, and wraps at spaces to the box's width" do
      binary =
        Tincture.new()
        |> Tincture.text_field(72, 600, 120, 80, "m",
          multiline: true,
          size: 10,
          value: "one two three four five six seven\nend"
        )
        |> export()

      content = content(binary, "m")
      lines = lines(content)
      assert List.last(lines) == "end"
      assert length(lines) > 2

      for line <- lines do
        assert Tincture.Font.text_width("Helvetica", 10, line) <= 120 - 4
      end

      # The leading is 1.15 x size, from the top inset.
      baselines =
        for [_, y] <- Regex.scan(~r/\n2 (\S+) Td\n/, content), do: elem(Float.parse(y), 0)

      assert hd(baselines) == 80 - 1 - 7.5 - 0.75
      assert_in_delta Enum.at(baselines, 0) - Enum.at(baselines, 1), 11.5, 0.0001
    end

    test "the auto size steps down until the text fits, with a floor of 4" do
      value = String.duplicate("word ", 60)

      binary =
        Tincture.new()
        |> Tincture.text_field(72, 600, 200, 40, "m", multiline: true, value: value)
        |> export()

      [_, size] = Regex.run(~r/\/Helv (\S+) Tf/, content(binary, "m"))
      {size, _} = Float.parse(size)
      assert size < 12 and size >= 4
      assert Float.round(size * 2) == size * 2
    end
  end

  describe "choice fields" do
    test "a combo box shows its value" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(72, 700, 200, 24, "c", options: ["a", "Norway"], value: "Norway")
        |> export()

      assert content(binary, "c") =~ "2 9 Td\n(Norway) Tj"
    end

    test "an editable combo shows a free value" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(72, 700, 200, 24, "c",
          options: ["a"],
          value: "Peru",
          editable: true
        )
        |> export()

      assert content(binary, "c") =~ "(Peru) Tj"
    end

    test "a list box draws its rows in the written /Opt order" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(72, 600, 200, 54, "c",
          options: ["b", "c", "a"],
          dropdown: false,
          sort: true
        )
        |> export()

      assert widget(binary, "c") =~ "/Opt [(a) (b) (c)]"
      assert lines(content(binary, "c")) == ["a", "b", "c"]
    end
  end

  describe "/TI" do
    @six ~w(one two three four five six)

    test "is not written when the selection is visible" do
      binary = list_box(@six, "three")
      refute widget(binary, "c") =~ "/TI"
      assert lines(content(binary, "c")) == ~w(one two three)
    end

    test "scrolls a selection below the box into view, keeping the box full" do
      # Three rows fit; min(k, len - rows).
      for {value, top} <- [{"four", 3}, {"five", 3}, {"six", 3}] do
        binary = list_box(@six, value)
        assert widget(binary, "c") =~ "/TI #{top}"
        assert lines(content(binary, "c")) == ~w(four five six)
      end
    end

    test "with more options than rows below the selection, the selection is first" do
      binary = list_box(@six ++ ~w(seven eight), "four")
      assert widget(binary, "c") =~ "/TI 3"
      assert lines(content(binary, "c")) == ~w(four five six)
    end
  end

  describe ":align" do
    test "center and right are written as /Q and offset the text" do
      width = Tincture.Font.text_width("Helvetica", 12, "Ada")

      center = single(value: "Ada", align: :center)
      assert widget(center, "f") =~ "/Q 1"
      assert content(center, "f") =~ "#{Float.round((200 - width) / 2, 4)} 9 Td"

      right = single(value: "Ada", align: :right)
      assert widget(right, "f") =~ "/Q 2"
      assert content(right, "f") =~ "#{Float.round(200 - 2 - width, 4)} 9 Td"
    end

    test "left is the default, and writes no /Q" do
      refute widget(single(value: "Ada", align: :left), "f") =~ "/Q"
      refute widget(single(value: "Ada"), "f") =~ "/Q"
    end

    test "a choice field takes it too" do
      binary =
        Tincture.new()
        |> Tincture.choice_field(72, 700, 200, 24, "c", options: ["a"], value: "a", align: :right)
        |> export()

      assert widget(binary, "c") =~ "/Q 2"
    end

    test "anything else is refused, and so is :align on other field types" do
      assert_raise ArgumentError, ~r/:align must be :left, :center or :right/, fn ->
        single(value: "x", align: :justify)
      end

      assert_raise ArgumentError, ~r/checkbox fields do not take :align/, fn ->
        Tincture.checkbox(Tincture.new(), 72, 700, 12, "b", align: :center)
      end
    end
  end

  describe "/DA and /DR" do
    test "every widget's /DA names a font /DR holds, and the /AP uses that font" do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("Sans", @sans, subset: :none)
        |> Tincture.text_field(72, 700, 200, 24, "t", value: "x", font: "Sans")
        |> Tincture.text_field(72, 650, 200, 24, "u", value: "y", font: "Courier")
        |> Tincture.choice_field(72, 600, 200, 24, "c", options: ["a"], value: "a")
        |> export()

      [_, dr] = Regex.run(~r/\/DR << \/Font << (.*?) >> >> >>/, binary)

      for name <- ~w(t u c) do
        [_, font_alias] = Regex.run(~r/\/DA \(\/(\S+) /, widget(binary, name))
        assert dr =~ "/#{font_alias} "
        {dictionary, content} = appearance(binary, name)
        assert content =~ "/#{font_alias} "

        case Regex.run(~r/\/#{font_alias} (\d+ 0 R)/, dr) do
          [_, reference] -> assert dictionary =~ "/#{font_alias} #{reference}"
          nil -> assert dictionary =~ "/#{font_alias} << /Type /Font"
        end
      end
    end
  end

  describe "fonts: section C, acceptance 1" do
    defp stream_of(binary, object_id) do
      [_, header, length] =
        Regex.run(~r/\n#{object_id} 0 obj\n(<< \/Length (\d+)[^>]*>>)\nstream\n/, binary)

      {start, _} = :binary.match(binary, "#{header}\nstream\n")
      data = binary_part(binary, start + byte_size(header) + 8, String.to_integer(length))
      if header =~ "FlateDecode", do: :zlib.uncompress(data), else: data
    end

    defp referenced(binary, key) do
      [_, id] = Regex.run(~r/\/#{key} (\d+) 0 R/, binary)
      String.to_integer(id)
    end

    defp gid(binary, cid) do
      map = stream_of(binary, referenced(binary, "CIDToGIDMap"))
      <<gid::16>> = binary_part(map, cid * 2, 2)
      gid
    end

    # Whether the embedded program's glyph has an outline: loca[gid] differs
    # from loca[gid + 1].
    defp outline?(binary, gid) do
      font = stream_of(binary, referenced(binary, "FontFile2"))
      <<_version::32, tables::16, _::binary>> = font

      directory =
        for i <- 0..(tables - 1), into: %{} do
          <<tag::binary-4, _checksum::32, offset::32, length::32>> =
            binary_part(font, 12 + i * 16, 16)

          {tag, binary_part(font, offset, length)}
        end

      <<_::binary-50, long::16-signed, _::binary>> = directory["head"]
      loca = directory["loca"]

      {a, b} =
        if long == 1 do
          <<_::binary-size(gid * 4), a::32, b::32, _::binary>> = loca
          {a, b}
        else
          <<_::binary-size(gid * 2), a::16, b::16, _::binary>> = loca
          {a, b}
        end

      b > a
    end

    defp widths_has?(binary, cid) do
      [_, w] = Regex.run(~r/\/W \[(.*?)\] >>/s, binary)
      w =~ ~r/(^|\s)#{cid} \[/
    end

    test "a glyph drawn only by a read-only field's appearance is in the subset" do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("Sans", @sans)
        |> Tincture.set_font("Sans", 12)
        |> Tincture.text_at(72, 750, "ABC")
        |> Tincture.text_field(72, 700, 200, 24, "t", value: "Q", font: "Sans", read_only: true)
        |> export()

      # The page never draws Q; the appearance does, through Identity-H.
      assert content(binary, "t") =~ "<0051> Tj"
      assert widths_has?(binary, ?Q)
      gid = gid(binary, ?Q)
      assert gid != 0
      assert outline?(binary, gid)
    end

    test "a non-editable combo's subset holds an option it does not show" do
      binary =
        Tincture.new()
        |> Tincture.register_ttf_font("Sans", @sans)
        |> Tincture.choice_field(72, 700, 200, 24, "c",
          options: ["Q", "Z"],
          value: "Z",
          font: "Sans"
        )
        |> export()

      refute content(binary, "c") =~ "<0051>"
      assert outline?(binary, gid(binary, ?Q))
      assert outline?(binary, gid(binary, ?Z))
    end
  end
end
