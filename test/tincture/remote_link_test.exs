defmodule Tincture.RemoteLinkTest do
  @moduledoc """
  `/GoToR` — links into another PDF file.

  The bytes asserted here are the bytes a spike confirmed in a viewer before
  any of this was written: SumatraPDF opens `/D [12 /Fit]` at the thirteenth
  page, and a `/GoToR` with no `/D` at the first. Both were checked against a
  hand-written document, so these assertions pin behaviour that was observed
  rather than a format read off a specification.
  """

  use ExUnit.Case, async: true

  defp action(binary) do
    case Regex.run(~r|/A << /S /GoToR[^>]*>>|, binary) do
      [match] -> match
      nil -> nil
    end
  end

  defp linked(target, opts \\ []) do
    Tincture.new()
    |> Tincture.link(72, 700, 120, 14, target, opts)
    |> Tincture.export()
    |> action()
  end

  describe "the action" do
    test "page 13 serialises as /D [12 /Fit]" do
      assert linked({:file, "Attached documents/Secondary-pdf-1.pdf", 13}) ==
               "/A << /S /GoToR /F (Attached documents/Secondary-pdf-1.pdf) /D [12 /Fit] >>"
    end

    # The conversion is the most likely silent defect in this feature: an
    # off-by-one lands in a document the author no longer has, pointing at the
    # wrong page rather than failing visibly.
    test "counts from 1, so the first page is index 0" do
      assert linked({:file, "a.pdf", 1}) =~ "/D [0 /Fit]"
      assert linked({:file, "a.pdf", 2}) =~ "/D [1 /Fit]"
      assert linked({:file, "a.pdf", 100}) =~ "/D [99 /Fit]"
    end

    test "omits /D entirely when no page is named" do
      assert linked({:file, "a.pdf"}) == "/A << /S /GoToR /F (a.pdf) >>"
    end

    test "uses /Fit, where an internal link uses /XYZ" do
      assert linked({:file, "a.pdf", 3}) =~ "/Fit"

      internal =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, {:page, 1})
        |> Tincture.export()

      assert internal =~ "/XYZ null null null"
    end
  end

  describe "the same target through either entry point" do
    test "link/7 and text_link/6 produce the same action" do
      via_link =
        Tincture.new()
        |> Tincture.link(72, 700, 120, 14, {:file, "a.pdf", 4})
        |> Tincture.export()
        |> action()

      via_text =
        Tincture.new()
        |> Tincture.set_font("Helvetica", 12)
        |> Tincture.text_link(72, 700, "see appendix", {:file, "a.pdf", 4})
        |> Tincture.export()
        |> action()

      assert via_link == via_text
      assert via_link =~ "/D [3 /Fit]"
    end
  end

  describe "the path" do
    test "backslashes become forward slashes" do
      path = "sub" <> <<92>> <> "dir" <> <<92>> <> "c.pdf"
      assert linked({:file, path, 2}) =~ "/F (sub/dir/c.pdf)"
    end

    test "a relative path with spaces survives unchanged" do
      assert linked({:file, "Attached documents/a b.pdf"}) =~ "/F (Attached documents/a b.pdf)"
    end
  end

  describe "rejections" do
    # A file target resolves nothing, ever, so normalisation is the only place
    # a mistake can be caught. Each message is pinned, not just the raising.
    test "page 0" do
      assert_raise ArgumentError, ~r/must be a positive integer, counting from 1/, fn ->
        linked({:file, "a.pdf", 0})
      end
    end

    test "a negative page" do
      assert_raise ArgumentError, ~r/must be a positive integer, counting from 1/, fn ->
        linked({:file, "a.pdf", -3})
      end
    end

    test "a non-integer page" do
      assert_raise ArgumentError, ~r/must be a positive integer, counting from 1/, fn ->
        linked({:file, "a.pdf", 1.5})
      end
    end

    test "an absolute path" do
      assert_raise ArgumentError, ~r/must be relative to the document that carries it/, fn ->
        linked({:file, "/etc/a.pdf"})
      end
    end

    test "a drive-letter path" do
      assert_raise ArgumentError, ~r/must be relative to the document that carries it/, fn ->
        linked({:file, "C:/tmp/a.pdf"})
      end
    end

    test "a UNC path" do
      assert_raise ArgumentError, ~r/must be relative to the document that carries it/, fn ->
        linked({:file, <<92, 92>> <> "server/share/a.pdf"})
      end
    end

    test "a non-ASCII path" do
      assert_raise ArgumentError, ~r/must be ASCII/, fn ->
        linked({:file, "rapport-financiér.pdf"})
      end
    end

    test "a blank path" do
      assert_raise ArgumentError, ~r/needs a path to the target document/, fn ->
        linked({:file, "   "})
      end
    end

    test "the error names every accepted form" do
      error = assert_raise(ArgumentError, fn -> linked({:remote, "a.pdf"}) end)
      message = Exception.message(error)

      assert message =~ "{:url, url}"
      assert message =~ "{:page, page_number}"
      assert message =~ "{:file, path}"
      assert message =~ "{:file, path, page_number}"
    end
  end

  describe "/NewWindow" do
    # A genuine tri-state, and the absent case is the one that will rot: it is
    # the difference between overriding the reader's preference and leaving it
    # alone. SumatraPDF opened a new tab with the key absent, which is exactly
    # the choice being preserved.
    test "true writes the key" do
      assert linked({:file, "a.pdf", 1}, new_window: true) =~ "/NewWindow true"
    end

    test "false writes the key" do
      assert linked({:file, "a.pdf", 1}, new_window: false) =~ "/NewWindow false"
    end

    test "omitting the option omits the key" do
      refute linked({:file, "a.pdf", 1}) =~ "/NewWindow"
    end

    test "a non-boolean is refused" do
      assert_raise ArgumentError, ~r/must be true or false/, fn ->
        linked({:file, "a.pdf", 1}, new_window: :maybe)
      end
    end
  end

  describe "a tagged remote link" do
    # None of this is new work - it falls out of the /OBJR and /Contents
    # machinery from 0.3.0. It is asserted anyway, because "it should follow
    # from existing machinery" is what was believed about link annotations
    # before 0.3.0, and it was wrong.
    defp tagged_remote(opts) do
      Tincture.new()
      |> Tincture.set_language("en-GB")
      |> Tincture.tag(:document, fn doc ->
        Tincture.tag(doc, :link, fn page ->
          page
          |> Tincture.set_font("Helvetica", 12)
          |> Tincture.text_link(72, 700, "appendix B", {:file, "b.pdf", 3}, opts)
        end)
      end)
    end

    test "carries /Contents and is reachable through /OBJR" do
      binary = tagged_remote(contents: "appendix B, page 3") |> Tincture.export()

      assert binary =~ "/S /GoToR"
      assert binary =~ "/Contents (appendix B, page 3)"
      assert binary =~ ~r/<< \/Type \/OBJR \/Obj \d+ 0 R >>/
      assert binary =~ ~r/\/StructParent \d+/
    end

    test "is refused without a description, like any other tagged link" do
      pdf = tagged_remote([])

      assert [%{rule: :link_without_description}] = Tincture.pdf_ua_violations(pdf)

      assert_raise ArgumentError, ~r/no alternate description/, fn ->
        Tincture.export(pdf)
      end
    end
  end
end
