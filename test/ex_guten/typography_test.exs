defmodule ExGuten.TypographyTest do
  use ExUnit.Case

  alias ExGuten.Typography
  alias ExGuten.Typography.LayoutResult
  alias ExGuten.Typography.RichText
  alias ExGuten.Typography.RichText.Space
  alias ExGuten.Typography.RichText.Word

  test "layout_paragraph/3 lays out plain text into single line when it fits" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    assert [line] = Typography.layout_paragraph(rich, 42)
    assert line.text == "one two"
    assert line.width == 42.0
    assert line.x == 0.0
  end

  test "layout_paragraph/3 wraps and returns styled fragments" do
    rich =
      RichText.from_runs([
        %{text: "Hello", font: "Helvetica", size: 12},
        %{text: " ", font: "Helvetica", size: 12},
        %{text: "world", font: "Times-Roman", size: 12}
      ])

    [line] = Typography.layout_paragraph(rich, 200)

    assert [
             %Word{text: "Hello", font: "Helvetica"},
             %Space{text: " ", font: "Helvetica"},
             %Word{text: "world", font: "Times-Roman"}
           ] = line.tokens
  end

  test "layout_paragraph/3 supports center and right alignment" do
    rich = RichText.from_plain("one", font: "Courier", size: 10)

    [centered] = Typography.layout_paragraph(rich, 60, align: :center)
    [right] = Typography.layout_paragraph(rich, 60, align: :right)

    assert centered.width == 18.0
    assert centered.x == 21.0

    assert right.width == 18.0
    assert right.x == 42.0
  end

  test "layout_paragraph/3 assigns line y positions with explicit line_height" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    lines = Typography.layout_paragraph(rich, 30, line_height: 14)

    assert Enum.map(lines, & &1.text) == ["one", "two", "three"]
    assert Enum.map(lines, & &1.y) == [0.0, -14.0, -28.0]
  end

  test "layout_paragraph/3 justification expands spaces for non-final lines" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    [first, last] = Typography.layout_paragraph(rich, 60, align: :justified)

    assert first.text == "one two"
    assert first.width == 60.0
    assert [%Word{text: "one"}, %Space{width: 24.0}, %Word{text: "two"}] = first.tokens

    assert last.text == "three"
    assert last.width == 30.0
    assert [%Word{text: "three"}] = last.tokens
  end

  test "layout_paragraph/3 supports constrained space stretch for justification" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    [first, last] =
      Typography.layout_paragraph(rich, 60,
        align: :justified,
        justify_max_space_multiplier: 2.0
      )

    assert first.text == "one two"
    assert first.width == 48.0
    assert [%Word{text: "one"}, %Space{width: 12.0}, %Word{text: "two"}] = first.tokens

    assert last.text == "three"
    assert last.width == 30.0
  end

  test "layout_paragraph/3 supports constrained space shrink for justification" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    baseline = Typography.layout_paragraph(rich, 39, align: :justified)

    shrunk =
      Typography.layout_paragraph(rich, 39,
        align: :justified,
        justify_min_space_multiplier: 0.5
      )

    assert Enum.map(baseline, & &1.text) == ["one", "two", "three"]
    assert Enum.map(shrunk, & &1.text) == ["one two", "three"]
    assert hd(shrunk).width == 39.0
    assert [%Word{text: "one"}, %Space{width: 3.0}, %Word{text: "two"}] = hd(shrunk).tokens
  end

  test "layout_paragraph/3 can shrink justified single-line paragraphs when enabled" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    baseline = Typography.layout_paragraph(rich, 39, align: :justified)

    shrunk =
      Typography.layout_paragraph(rich, 39,
        align: :justified,
        justify_min_space_multiplier: 0.5
      )

    assert Enum.map(baseline, & &1.text) == ["one", "two"]
    assert Enum.map(shrunk, & &1.text) == ["one two"]
    assert hd(shrunk).width == 39.0
    assert [%Word{text: "one"}, %Space{width: 3.0}, %Word{text: "two"}] = hd(shrunk).tokens
  end

  test "layout_paragraph/3 with line_break: :optimal balances raggedness globally" do
    rich = RichText.from_plain("aa bb cc dd eeeeee", font: "Courier", size: 10)

    greedy = Typography.layout_paragraph(rich, 48)
    optimal = Typography.layout_paragraph(rich, 48, line_break: :optimal)

    assert Enum.map(greedy, & &1.text) == ["aa bb cc", "dd", "eeeeee"]
    assert Enum.map(optimal, & &1.text) == ["aa bb", "cc dd", "eeeeee"]
  end

  test "layout_paragraph/3 rejects unknown line_break strategy" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    assert_raise ArgumentError, "line_break must be :greedy or :optimal", fn ->
      Typography.layout_paragraph(rich, 42, line_break: :balanced)
    end
  end

  test "layout_paragraph/3 rejects unknown optimal_cost_model strategy" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    assert_raise ArgumentError, "optimal_cost_model must be :quadratic or :box_glue", fn ->
      Typography.layout_paragraph(rich, 42,
        line_break: :optimal,
        optimal_cost_model: :legacy
      )
    end
  end

  test "layout_paragraph/3 supports mixed-run justification with optimal line-breaking" do
    rich =
      RichText.from_runs([
        %{text: "aa", font: "Courier", size: 10},
        %{text: " ", font: "Courier", size: 10},
        %{text: "bb", font: "Courier-Bold", size: 10},
        %{text: " ", font: "Courier-Bold", size: 10},
        %{text: "cc", font: "Courier-Oblique", size: 10},
        %{text: " ", font: "Courier-Oblique", size: 10},
        %{text: "dd", font: "Courier-BoldOblique", size: 10},
        %{text: " ", font: "Courier-BoldOblique", size: 10},
        %{text: "eeeeee", font: "Courier", size: 10}
      ])

    [first, second, last] =
      Typography.layout_paragraph(rich, 48, line_break: :optimal, align: :justified)

    assert Enum.map([first, second, last], & &1.text) == ["aa bb", "cc dd", "eeeeee"]
    assert first.width == 48.0
    assert second.width == 48.0
    assert last.width == 36.0

    assert [%Word{font: "Courier"}, %Space{width: 24.0}, %Word{font: "Courier-Bold"}] =
             first.tokens
  end

  test "layout_paragraph/3 with widow_penalty in optimal mode avoids one-word last lines" do
    rich = RichText.from_plain("aa bb cc dd", font: "Courier", size: 10)

    baseline = Typography.layout_paragraph(rich, 48, line_break: :optimal)

    penalized =
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        widow_penalty: 5_000
      )

    assert Enum.map(baseline, & &1.text) == ["aa bb cc", "dd"]
    assert Enum.map(penalized, & &1.text) == ["aa bb", "cc dd"]
  end

  test "layout_paragraph/3 rejects negative optimal penalties" do
    rich = RichText.from_plain("aa bb", font: "Courier", size: 10)

    assert_raise ArgumentError, "widow_penalty must be >= 0", fn ->
      Typography.layout_paragraph(rich, 48, line_break: :optimal, widow_penalty: -1)
    end

    assert_raise ArgumentError, "fitness_class_penalty must be >= 0", fn ->
      Typography.layout_paragraph(rich, 48, line_break: :optimal, fitness_class_penalty: -1)
    end

    assert_raise ArgumentError, "consecutive_hyphen_penalty must be >= 0", fn ->
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        consecutive_hyphen_penalty: -1
      )
    end
  end

  test "layout_paragraph/3 rejects invalid justify_max_space_multiplier values" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    assert_raise ArgumentError, "justify_max_space_multiplier must be >= 1.0", fn ->
      Typography.layout_paragraph(rich, 60,
        align: :justified,
        justify_max_space_multiplier: 0.5
      )
    end
  end

  test "layout_paragraph/3 rejects invalid justify_min_space_multiplier values" do
    rich = RichText.from_plain("one two three", font: "Courier", size: 10)

    assert_raise ArgumentError, "justify_min_space_multiplier must be > 0 and <= 1.0", fn ->
      Typography.layout_paragraph(rich, 60,
        align: :justified,
        justify_min_space_multiplier: 0
      )
    end

    assert_raise ArgumentError, "justify_min_space_multiplier must be > 0 and <= 1.0", fn ->
      Typography.layout_paragraph(rich, 60,
        align: :justified,
        justify_min_space_multiplier: 1.2
      )
    end
  end

  test "layout_paragraph/3 with fitness_class_penalty in optimal mode penalizes abrupt class jumps" do
    rich = RichText.from_plain("aa aa aa aa aa", font: "Courier", size: 10)

    baseline = Typography.layout_paragraph(rich, 48, line_break: :optimal)

    penalized =
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        fitness_class_penalty: 800
      )

    assert Enum.map(baseline, & &1.text) == ["aa aa aa", "aa aa"]
    assert Enum.map(penalized, & &1.text) == ["aa aa", "aa aa", "aa"]
  end

  test "layout_paragraph/3 with optimal_cost_model :box_glue can change break choices under tight stretch caps" do
    rich = RichText.from_plain("aa bb cc dd eeeeee", font: "Courier", size: 10)

    quadratic =
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        align: :justified,
        justify_max_space_multiplier: 2.0,
        optimal_cost_model: :quadratic
      )

    box_glue =
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        align: :justified,
        justify_max_space_multiplier: 2.0,
        optimal_cost_model: :box_glue
      )

    assert Enum.map(quadratic, & &1.text) == ["aa bb", "cc dd", "eeeeee"]
    assert Enum.map(box_glue, & &1.text) == ["aa bb cc", "dd", "eeeeee"]
  end

  test "layout_paragraph/3 optimal mode defaults to :box_glue cost model" do
    rich = RichText.from_plain("aa bb cc dd eeeeee", font: "Courier", size: 10)

    default_optimal =
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        align: :justified,
        justify_max_space_multiplier: 2.0
      )

    quadratic =
      Typography.layout_paragraph(rich, 48,
        line_break: :optimal,
        align: :justified,
        justify_max_space_multiplier: 2.0,
        optimal_cost_model: :quadratic
      )

    assert Enum.map(default_optimal, & &1.text) == ["aa bb cc", "dd", "eeeeee"]
    assert Enum.map(quadratic, & &1.text) == ["aa bb", "cc dd", "eeeeee"]
  end

  test "layout_paragraph/3 with consecutive_hyphen_penalty in optimal mode avoids repeated hyphen endings" do
    rich = RichText.from_plain("aa- aa- aaa- aa aa-", font: "Courier", size: 10)

    baseline = Typography.layout_paragraph(rich, 36, line_break: :optimal)

    penalized =
      Typography.layout_paragraph(rich, 36,
        line_break: :optimal,
        consecutive_hyphen_penalty: 800
      )

    assert Enum.map(baseline, & &1.text) == ["aa-", "aa-", "aaa-", "aa aa-"]
    assert Enum.map(penalized, & &1.text) == ["aa-", "aa-", "aaa-", "aa", "aa-"]
  end

  test "layout_paragraph_with_spill/4 returns no overflow when content fits in max_lines" do
    rich = RichText.from_plain("one two", font: "Courier", size: 10)

    assert %LayoutResult{
             overflow?: false,
             lines: [line],
             spill_lines: [],
             spill_text: ""
           } = Typography.layout_paragraph_with_spill(rich, 42, 2)

    assert line.text == "one two"
  end

  test "layout_paragraph_with_spill/4 reports spill lines when max_lines is exceeded" do
    rich = RichText.from_plain("one two three four", font: "Courier", size: 10)

    assert %LayoutResult{
             overflow?: true,
             lines: visible,
             spill_lines: spill,
             spill_text: "three\nfour"
           } = Typography.layout_paragraph_with_spill(rich, 30, 2, line_height: 14)

    assert Enum.map(visible, & &1.text) == ["one", "two"]
    assert Enum.map(spill, & &1.text) == ["three", "four"]
  end
end
