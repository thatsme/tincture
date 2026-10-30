defmodule Tincture.FieldAppearanceTest do
  @moduledoc """
  Text and choice fields carry their own appearance stream (/AP /N), laid out
  by Tincture, so they display the same in every viewer and wherever no
  viewer regenerates them. /NeedAppearances is never written.

  The layout follows what Adobe Acrobat Reader (2026.002.22031) writes for
  the same fields. The values marked "Acrobat:" below are the ones measured
  from its saved appearance streams for Helvetica fields; Tincture's must be
  within 0.005 point of them.
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

  # The size and the first baseline of an appearance.
  defp size_and_baseline(content) do
    [_, size] = Regex.run(~r/\/\S+ (\S+) Tf/, content)
    [_, x, y] = Regex.run(~r/\n(\S+) (\S+) Td\n/, content)
    {to_float(size), to_float(x), to_float(y)}
  end

  defp to_float(text), do: text |> Float.parse() |> elem(0)

  describe "against Acrobat's appearances" do
    test "a single-line field at auto size" do
      # Acrobat: /Helv 16.302 Tf, 0 4.9524 Td, in a 240 x 22 field.
      assert content(single([value: "Ada Lovelace"], {240, 22}), "f") ==
               "/Tx BMC\n0 0 0 rg\nBT\n/Helv 16.3011 Tf\n0 4.9523 Td\n(Ada Lovelace) Tj\nET\nEMC\n"
    end

    test "a single-line field at a fixed size" do
      # Acrobat: /Helv 9 Tf, 0 7.6615 Td.
      {size, x, y} = size_and_baseline(content(single([value: "x", size: 9], {240, 22}), "f"))
      assert {size, x} == {9.0, 0.0}
      assert_in_delta y, 7.6615, 0.005
    end

    test "a bordered field" do
      # Acrobat, /Border [0 0 2]: /Helv 13.334 Tf, 4 6.0536 Td.
      {size, x, y} =
        size_and_baseline(content(single([value: "x", border: {0, 0, 2}], {240, 22}), "f"))

      assert_in_delta size, 13.334, 0.005
      assert x == 4.0
      assert_in_delta y, 6.0536, 0.005
    end

    test "centred and right-aligned" do
      # Acrobat: 91.008 for "Centred", 176.568 for "1,234.50", at 16.302.
      {_, x, _} =
        size_and_baseline(content(single([value: "Centred", align: :center], {240, 22}), "f"))

      assert_in_delta x, 91.008, 0.005

      {_, x, _} =
        size_and_baseline(content(single([value: "1,234.50", align: :right], {240, 22}), "f"))

      assert_in_delta x, 176.568, 0.015
    end

    test "a list box with its selection drawn on a band" do
      # Acrobat: 0.600006 0.756866 0.854904 rg, 0 36.1279 240 13.8721 re f,
      # baselines 38.6119, 24.7399 and 10.8679, /TI 3.
      binary =
        Tincture.new()
        |> Tincture.choice_field(72, 600, 240, 50, "c",
          options: ~w(one two three four five six),
          value: "four",
          dropdown: false
        )
        |> export()

      assert content(binary, "c") ==
               "/Tx BMC\n0.600006 0.756866 0.854904 rg\n0 36.128 240 13.872 re\nf\n" <>
                 "0 0 0 rg\nBT\n/Helv 12 Tf\n0 38.612 Td\n(four) Tj\nET\n" <>
                 "BT\n/Helv 12 Tf\n0 24.74 Td\n(five) Tj\nET\n" <>
                 "BT\n/Helv 12 Tf\n0 10.868 Td\n(six) Tj\nET\nEMC\n"

      assert widget(binary, "c") =~ "/TI 3"
    end

    test "a multiline field" do
      # Acrobat, 500 x 56: /Helv 12 Tf, first baseline 42.1279, then 13.872
      # lower; "after" ends the first line and "an" starts the second.
      binary =
        Tincture.new()
        |> Tincture.text_field(50, 560, 500, 56, "m",
          multiline: true,
          value:
            "A multiline value long enough to wrap at the edge of the box, " <>
              "with a second paragraph after an explicit line break.\nSecond paragraph."
        )
        |> export()

      content = content(binary, "m")
      baselines = for [_, y] <- Regex.scan(~r/\n0 (\S+) Td\n/, content), do: to_float(y)
      assert_in_delta hd(baselines), 42.1279, 0.005
      assert_in_delta Enum.at(baselines, 0) - Enum.at(baselines, 1), 13.872, 0.005

      assert [first, "an explicit line break.", "Second paragraph."] =
               for([_, text] <- Regex.scan(~r/\((.*?)\) Tj/, content), do: text)

      assert String.ends_with?(first, "paragraph after")
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

    test "a standard font is the /DR object under the /DA alias, with WinAnsi" do
      binary = single(value: "x", font: "Courier")
      {dictionary, content} = appearance(binary, "f")

      [_, font_id] = Regex.run(~r"/Resources << /Font << /Courier (\d+) 0 R >> >>", dictionary)
      assert binary =~ "/DR << /Font << /Courier #{font_id} 0 R >> >>"

      assert binary =~
               "\n#{font_id} 0 obj\n<< /Type /Font /Subtype /Type1 " <>
                 "/BaseFont /Courier /Encoding /WinAnsiEncoding >>\nendobj"

      assert content =~ ~r"/Courier \S+ Tf"
    end

    test "standard-14 text is written in WinAnsi, not UTF-16" do
      content = content(single(value: "Größe"), "f")
      assert content =~ ~S"(Gr\366\337e) Tj"
      refute content =~ "FEFF"
    end
  end

  describe "the /Tx marking and the border" do
    test "with no border, everything is inside the marking, with no clip of its own" do
      # Acrobat writes no clip and no q/Q; the /BBox clips.
      content = content(single(value: "x"), "f")
      assert content =~ ~r/\A\/Tx BMC\n0 0 0 rg\nBT\n/
      refute content =~ " re\nW\n"
    end

    test "a border is stroked before the marking, and the text starts at twice its width" do
      content = content(single(value: "x", border: {0, 0, 2}), "f")
      assert content =~ ~r/\A0 0 0 RG\n2 w\n1 1 198 22 re\nS\n\/Tx BMC\n/
      assert content =~ ~r/\n4 \S+ Td\n/
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

    test "follows the height, as Acrobat's does, with no cap at 12" do
      # (h - 2b) / (1.156 + 2 x 0.0968): Acrobat's 16.302 for 22 points.
      assert_in_delta size_of(content(single([value: "Ada"], {200, 22}), "f")), 16.302, 0.005
      assert_in_delta size_of(content(single([value: "Ada"], {200, 12}), "f")), 8.892, 0.005
    end

    test "is scaled down to the width for a long value, not below 4" do
      long = String.duplicate("W", 40)
      size = size_of(content(single([value: long], {200, 24}), "f"))
      assert size < 12 and size >= 4

      width = Tincture.Font.text_width("Helvetica", size, long)
      assert_in_delta width, 200, 0.01

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

      # The leading is the font's bounding-box height, 1.156 x size, and the
      # first baseline one leading below the top.
      baselines =
        for [_, y] <- Regex.scan(~r/\n0 (\S+) Td\n/, content), do: elem(Float.parse(y), 0)

      assert_in_delta hd(baselines), 80 - 11.56, 0.0001
      assert_in_delta Enum.at(baselines, 0) - Enum.at(baselines, 1), 11.56, 0.0001
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

      assert content(binary, "c") =~ ~r/\n0 \S+ Td\n\(Norway\) Tj/
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
      center = single(value: "Ada", align: :center, size: 12)
      width = Tincture.Font.text_width("Helvetica", 12, "Ada")
      assert widget(center, "f") =~ "/Q 1"
      {_, x, _} = size_and_baseline(content(center, "f"))
      assert_in_delta x, (200 - width) / 2, 0.0001

      # With no border the padding is 0, so right-aligned text ends at the edge.
      right = single(value: "Ada", align: :right, size: 12)
      assert widget(right, "f") =~ "/Q 2"
      {_, x, _} = size_and_baseline(content(right, "f"))
      assert_in_delta x, 200 - width, 0.0001
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
