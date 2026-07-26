defmodule Tincture.Font.AFMTest do
  use ExUnit.Case

  test "parse_file/1 loads widths, glyph names, and kerning pairs" do
    path = Application.app_dir(:tincture, "priv/afm/V-SECRET.afm")
    afm = Tincture.Font.AFM.parse_file(path)

    assert afm.font_name == "Victorias-Secret"
    assert Tincture.Font.AFM.width_for_code(afm, 84) == 1073
    assert Tincture.Font.AFM.glyph_name_for_code(afm, 111) == "o"
    assert Tincture.Font.AFM.kerning_adjust(afm, "T", "o") == -227
  end
end
