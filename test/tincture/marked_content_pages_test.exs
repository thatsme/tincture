defmodule Tincture.MarkedContentPagesTest do
  # Not async: these tests capture stderr, which the whole VM shares.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # A marked-content sequence has to begin and end in one content stream, and
  # each page is its own stream. Changing page while a content tag or an
  # artifact is open would split the sequence, so it raises ArgumentError, and
  # writes nothing to stderr.

  defp document(fun) do
    Tincture.new()
    |> Tincture.set_language("en-GB")
    |> Tincture.tag(:document, fun)
  end

  # Runs fun, which must raise ArgumentError, with stderr captured. Returns the
  # exception, and asserts nothing was written to stderr.
  defp raises_silently(fun) do
    parent = self()

    stderr =
      capture_io(:stderr, fn ->
        send(parent, {:raised, assert_raise(ArgumentError, fun)})
      end)

    assert stderr == ""
    assert_received {:raised, exception}
    exception
  end

  test "add_page/1 inside a content tag raises, naming the tag" do
    exception =
      raises_silently(fn ->
        document(fn pdf ->
          Tincture.tag(pdf, :p, fn pdf ->
            pdf |> Tincture.text_at(50, 700, "one") |> Tincture.add_page()
          end)
        end)
      end)

    assert exception.message ==
             "Tincture.add_page/1 was called while tag(:p, ...) is open on page 1. Its " <>
               "marked content would begin on one page and end on another, which a content " <>
               "stream cannot hold. Close it before changing page."
  end

  test "names the innermost open content tag" do
    exception =
      raises_silently(fn ->
        document(fn pdf ->
          Tincture.tag(pdf, :p, fn pdf ->
            Tincture.tag(pdf, :span, &Tincture.add_page/1)
          end)
        end)
      end)

    assert exception.message =~ "while tag(:span, ...) is open"
  end

  test "an open artifact is named as such" do
    exception =
      raises_silently(fn ->
        document(&Tincture.artifact(&1, fn pdf -> Tincture.add_page(pdf) end))
      end)

    assert exception.message ==
             "Tincture.add_page/1 was called while an artifact/2 block is open on page 1. " <>
               "Its marked content would begin on one page and end on another, which a " <>
               "content stream cannot hold. Close it before changing page."
  end

  test "set_page/2 to another page inside a content tag raises" do
    exception =
      raises_silently(fn ->
        pdf = Tincture.add_page(Tincture.new())

        pdf
        |> Tincture.set_page(1)
        |> Tincture.tag(:p, &Tincture.set_page(&1, 2))
      end)

    assert exception.message ==
             "Tincture.set_page/2 was called while tag(:p, ...) is open on page 1. Its " <>
               "marked content would begin on one page and end on another, which a content " <>
               "stream cannot hold. Close it before changing page."
  end

  test "set_page/2 to the current page neither raises nor warns" do
    {pdf, warning} =
      with_io(:stderr, fn -> Tincture.tag(Tincture.new(), :p, &Tincture.set_page(&1, 1)) end)

    assert %Tincture.PDF{} = pdf
    assert warning == ""
  end

  test "a container open across pages neither raises nor warns: it has no marked content" do
    {pdf, warning} =
      with_io(:stderr, fn ->
        document(fn pdf ->
          pdf
          |> Tincture.tag(:p, &Tincture.text_at(&1, 50, 700, "one"))
          |> Tincture.add_page()
          |> Tincture.tag(:p, &Tincture.text_at(&1, 50, 700, "two"))
        end)
      end)

    assert is_binary(Tincture.export(pdf))
    assert warning == ""
  end
end
