defmodule Tincture.MarkedContentPagesTest do
  # Not async: these tests capture stderr, which the whole VM shares.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # A marked-content sequence has to begin and end in one content stream, and
  # each page is its own stream. Changing page while a content tag or an
  # artifact is open splits the sequence; it warns, and still exports.

  defp document(fun) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fun)
  end

  test "add_page/1 inside a content tag warns, naming the tag, and still exports" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        document(fn pdf ->
          Tincture.tag(pdf, :p, fn pdf ->
            pdf |> Tincture.text_at(50, 700, "one") |> Tincture.add_page()
          end)
        end)
      end)

    assert warning =~ "Tincture.add_page/1 was called while tag(:p, ...) is open on page 1"
    assert warning =~ "This will raise in 0.4.0."
    assert length(Regex.scan(~r/warning: /, warning)) == 1
    assert is_binary(Tincture.export(pdf))
  end

  test "names the innermost open content tag" do
    {_pdf, warning} =
      with_io(:stderr, fn ->
        document(fn pdf ->
          Tincture.tag(pdf, :p, fn pdf ->
            Tincture.tag(pdf, :span, &Tincture.add_page/1)
          end)
        end)
      end)

    assert warning =~ "while tag(:span, ...) is open"
  end

  test "an open artifact is named as such" do
    {_pdf, warning} =
      with_io(:stderr, fn ->
        document(&Tincture.artifact(&1, fn pdf -> Tincture.add_page(pdf) end))
      end)

    assert warning =~ "while an artifact/2 block is open on page 1"
  end

  test "set_page/2 to another page inside a content tag warns" do
    {_pdf, warning} =
      with_io(:stderr, fn ->
        pdf = Tincture.add_page(Tincture.new())

        pdf
        |> Tincture.set_page(1)
        |> Tincture.tag(:p, &Tincture.set_page(&1, 2))
      end)

    assert warning =~ "Tincture.set_page/2 was called while tag(:p, ...) is open on page 1"
  end

  test "set_page/2 to the current page does not warn" do
    {_pdf, warning} =
      with_io(:stderr, fn -> Tincture.tag(Tincture.new(), :p, &Tincture.set_page(&1, 1)) end)

    assert warning == ""
  end

  test "a container open across pages does not warn: it has no marked content" do
    {_pdf, warning} =
      with_io(:stderr, fn ->
        document(fn pdf ->
          pdf
          |> Tincture.tag(:p, &Tincture.text_at(&1, 50, 700, "one"))
          |> Tincture.add_page()
          |> Tincture.tag(:p, &Tincture.text_at(&1, 50, 700, "two"))
        end)
      end)

    assert warning == ""
  end
end
