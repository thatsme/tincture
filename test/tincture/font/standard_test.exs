defmodule Tincture.Font.StandardTest do
  use ExUnit.Case

  alias Tincture.Font.Standard

  # These are the guards for a failure that has already happened once: a CRLF
  # checkout left a \r before every newline, the metric regexes matched nothing,
  # and all fourteen fonts loaded with empty width tables. Nothing raised. Every
  # string measured zero wide, and the damage surfaced 44 tests away in
  # justification, line breaking and fixture hashes, where the cause was
  # invisible. Assert the metrics directly so the next such failure names itself.

  test "every base 14 font parses a non-empty width table" do
    for name <- Standard.names() do
      assert {:ok, metrics} = Standard.fetch_metrics(name)

      refute metrics.widths_by_code == %{},
             "#{name} parsed no glyph widths - every string would measure 0.0 wide"
    end
  end

  test "parsed widths carry real values, not zeros" do
    assert {:ok, metrics} = Standard.fetch_metrics("Helvetica")

    # 'H' is 722 units in Helvetica, per the Adobe metrics.
    assert Map.fetch!(metrics.widths_by_code, ?H) == 722
  end

  test "kerning pairs parse for a font that has them" do
    assert {:ok, metrics} = Standard.fetch_metrics("Times-Roman")

    refute metrics.kern_by_code == %{}, "Times-Roman parsed no kerning pairs"
    assert Map.fetch!(metrics.kern_by_code, {?T, ?o}) == -80
  end

  test "fetch_metrics/1 returns :error for a font that is not one of the 14" do
    assert :error = Standard.fetch_metrics("Not-A-Standard-Font")
  end

  # The regexes tolerate a trailing \r, so a CRLF checkout still parses. This
  # asserts the other half: that the files themselves are checked out LF, which
  # is what .gitattributes pins. A failure here means the working tree was
  # normalised by core.autocrlf and .gitattributes is missing or not applied.
  test "shipped metric files are checked out with LF line endings" do
    :tincture
    |> Application.app_dir("priv/standard_fonts")
    |> Path.join("eg_font_*.erl")
    |> Path.wildcard()
    |> tap(fn paths -> assert length(paths) == 14 end)
    |> Enum.each(fn path ->
      refute File.read!(path) =~ "\r\n", "#{Path.basename(path)} has CRLF line endings"
    end)
  end
end
