defmodule Tincture.ExportOptionsTest do
  @moduledoc """
  W10: export/2 names an option it does not know. Until 0.4.1 such a key was
  ignored without a word, so a misspelt `compres: false` exported the document
  as if nothing had been passed. It warns now and raises in 0.5.0.
  """
  # Not async: these tests capture stderr, which the whole VM shares.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp warnings(fun), do: capture_io(:stderr, fun)

  defp document, do: Tincture.text_at(Tincture.new(), 72, 700, "x")

  test "one unknown key is named, with the known options" do
    stderr = warnings(fn -> Tincture.export(document(), compres: false) end)

    assert stderr =~
             "export/2 got the unknown option :compres. Known options: :enforce. " <>
               "Unknown options are ignored now; this will raise in 0.5.0."
  end

  test "two unknown keys are named in one warning" do
    stderr = warnings(fn -> Tincture.export(document(), compres: false, password: "p") end)

    assert stderr =~
             "export/2 got the unknown options :compres and :password. Known options: " <>
               ":enforce. Unknown options are ignored now; this will raise in 0.5.0."

    assert length(String.split(stderr, "export/2 got the unknown")) == 2
  end

  test "a key given twice is named once" do
    stderr = warnings(fn -> Tincture.export(document(), compres: false, compres: true) end)

    assert stderr =~ "export/2 got the unknown option :compres. Known options: :enforce."
    assert length(String.split(stderr, "export/2 got the unknown")) == 2
  end

  test "an unknown key changes nothing in the output" do
    plain = Tincture.export(document())
    warnings(fn -> send(self(), {:binary, Tincture.export(document(), compres: false)}) end)

    assert_received {:binary, ^plain}
  end

  test "save/3 passes its options to export/2, and warns the same" do
    path = Path.join(System.tmp_dir!(), "tincture_w10_#{System.unique_integer([:positive])}.pdf")
    on_exit(fn -> File.rm(path) end)

    stderr = warnings(fn -> :ok = Tincture.save(document(), path, compres: false) end)

    assert stderr =~ "export/2 got the unknown option :compres. Known options: :enforce."
  end

  test "known options and no options warn nothing" do
    assert warnings(fn -> Tincture.export(document()) end) == ""
    assert warnings(fn -> Tincture.export(document(), []) end) == ""
    assert warnings(fn -> Tincture.export(document(), enforce: false) end) == ""
    assert warnings(fn -> Tincture.export(document(), enforce: true) end) == ""
  end
end
