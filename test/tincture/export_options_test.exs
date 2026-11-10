defmodule Tincture.ExportOptionsTest do
  @moduledoc """
  export/2 and save/3 refuse an option they do not know. Until 0.4.1 such a
  key was ignored without a word, so a misspelt `compres: false` exported the
  document as if nothing had been passed; 0.4.1 warned (W10), and 0.5.0
  raises, before anything is exported or written.
  """
  # Not async: these tests capture stderr, which the whole VM shares.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp warnings(fun), do: capture_io(:stderr, fun)

  defp document, do: Tincture.text_at(Tincture.new(), 72, 700, "x")

  defp refusal(fun) do
    error = assert_raise ArgumentError, fun
    error.message
  end

  test "one unknown key is named, with the known options" do
    assert refusal(fn -> Tincture.export(document(), compres: false) end) ==
             "export/2 got the unknown option :compres. Known options: :enforce."
  end

  test "two unknown keys are named in one refusal" do
    assert refusal(fn -> Tincture.export(document(), compres: false, password: "p") end) ==
             "export/2 got the unknown options :compres and :password. Known options: :enforce."
  end

  test "a key given twice is named once" do
    assert refusal(fn -> Tincture.export(document(), compres: false, compres: true) end) ==
             "export/2 got the unknown option :compres. Known options: :enforce."
  end

  test "a known option alongside an unknown one" do
    assert refusal(fn -> Tincture.export(document(), enforce: false, compres: false) end) ==
             "export/2 got the unknown option :compres. Known options: :enforce."
  end

  test "save/3 refuses the same, before it creates the directory or the file" do
    dir = Path.join(System.tmp_dir!(), "tincture_w10_#{System.unique_integer([:positive])}")
    path = Path.join(dir, "out.pdf")
    on_exit(fn -> File.rm_rf(dir) end)

    assert refusal(fn -> Tincture.save(document(), path, compres: false) end) ==
             "export/2 got the unknown option :compres. Known options: :enforce."

    refute File.exists?(dir)
  end

  test "known options and no options neither refuse nor warn" do
    assert warnings(fn -> Tincture.export(document()) end) == ""
    assert warnings(fn -> Tincture.export(document(), []) end) == ""
    assert warnings(fn -> Tincture.export(document(), enforce: false) end) == ""
    assert warnings(fn -> Tincture.export(document(), enforce: true) end) == ""
  end
end
