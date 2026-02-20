defmodule ExGuten.Typography.RichTextTest do
  use ExUnit.Case

  alias ExGuten.Typography.RichText
  alias ExGuten.Typography.RichText.Break
  alias ExGuten.Typography.RichText.Run
  alias ExGuten.Typography.RichText.Space
  alias ExGuten.Typography.RichText.Word

  test "from_plain/2 builds a rich text struct with defaults" do
    rich = RichText.from_plain("Hello world")

    assert %RichText{} = rich
    assert [%Run{text: "Hello world", font: "Helvetica", size: 12}] = rich.runs
    assert [%Word{text: "Hello"}, %Space{text: " "}, %Word{text: "world"}] = rich.tokens
  end

  test "from_plain/2 tokenizes newline as break token" do
    rich = RichText.from_plain("Hello\nworld")

    assert [%Word{text: "Hello"}, %Break{}, %Word{text: "world"}] = rich.tokens
  end

  test "from_runs/1 preserves run font and size metadata in produced tokens" do
    rich =
      RichText.from_runs([
        %Run{text: "Hello", font: "Helvetica", size: 12},
        %Run{text: " world", font: "Times-Roman", size: 10}
      ])

    assert [
             %Word{text: "Hello", font: "Helvetica", size: 12},
             %Space{text: " ", font: "Times-Roman", size: 10},
             %Word{text: "world", font: "Times-Roman", size: 10}
           ] = rich.tokens
  end

  test "from_tokens/1 reconstructs runs while preserving mixed styles" do
    rich =
      RichText.from_tokens([
        %Word{text: "one", font: "Courier", size: 10, width: 18},
        %Space{text: " ", font: "Courier", size: 10, width: 6},
        %Word{text: "two", font: "Helvetica", size: 10, width: 16}
      ])

    assert [
             %Run{text: "one ", font: "Courier", size: 10},
             %Run{text: "two", font: "Helvetica", size: 10}
           ] = rich.runs

    assert [
             %Word{text: "one", font: "Courier"},
             %Space{text: " ", font: "Courier"},
             %Word{text: "two", font: "Helvetica"}
           ] = rich.tokens
  end

  test "from_tokens/1 preserves explicit break tokens" do
    rich =
      RichText.from_tokens([
        %Word{text: "one", font: "Courier", size: 10, width: 18},
        %Break{},
        %Word{text: "two", font: "Courier", size: 10, width: 18}
      ])

    assert [
             %Run{text: "one\ntwo", font: "Courier", size: 10}
           ] = rich.runs

    assert [
             %Word{text: "one"},
             %Break{},
             %Word{text: "two"}
           ] = rich.tokens
  end
end
