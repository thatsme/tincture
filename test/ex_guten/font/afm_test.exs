defmodule ExGuten.Font.AFMTest do
  use ExUnit.Case

  test "parse_file/1 loads widths, glyph names, and kerning pairs" do
    path = Application.app_dir(:ex_guten, "priv/afm/V-SECRET.afm")
    afm = ExGuten.Font.AFM.parse_file(path)

    assert afm.font_name == "Victorias-Secret"
    assert ExGuten.Font.AFM.width_for_code(afm, 84) == 1073
    assert ExGuten.Font.AFM.glyph_name_for_code(afm, 111) == "o"
    assert ExGuten.Font.AFM.kerning_adjust(afm, "T", "o") == -227
  end
end
