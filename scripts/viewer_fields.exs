# Writes a document with one field of each kind the appearance generator
# lays out, each with a value, for the viewer check (scripts/viewer_check.py)
# and for reviewing appearances by eye.
#
#   mix run scripts/viewer_fields.exs <out.pdf>
#
# examples/output/form.pdf is the realistic form, but its text fields are
# empty; this one puts something in every field.

[out] = System.argv()

label = fn pdf, top, text ->
  pdf
  |> Tincture.set_font("Helvetica", 8)
  |> Tincture.text_at(50, top + 4, text)
end

pdf =
  Tincture.new()
  |> Tincture.register_ttf_font("Sans", "examples/fonts/LiberationSans-Regular.ttf",
    subset: :none
  )
  |> Tincture.set_metadata(title: "Field appearances")
  |> label.(782, "Single line, auto size")
  |> Tincture.text_field(50, 760, 240, 22, "single", value: "Ada Lovelace")
  |> Tincture.text_field(310, 760, 240, 22, "fixed", value: "Size 9, fixed", size: 9)
  |> label.(732, "Centred / right-aligned")
  |> Tincture.text_field(50, 710, 240, 22, "center", value: "Centred", align: :center)
  |> Tincture.text_field(310, 710, 240, 22, "right", value: "1,234.50", align: :right)
  |> label.(682, "Bordered (2 pt) / WinAnsi")
  |> Tincture.text_field(50, 660, 240, 22, "bordered", value: "With a border", border: {0, 0, 2})
  |> Tincture.text_field(310, 660, 240, 22, "winansi", value: "Größe, café, €12")
  |> label.(616, "Multiline, wrapped at the box")
  |> Tincture.text_field(50, 560, 500, 56, "multiline",
    multiline: true,
    value:
      "A multiline value long enough to wrap at the edge of the box, " <>
        "with a second paragraph after an explicit line break.\nSecond paragraph."
  )
  |> label.(532, "Password / embedded font, Greek")
  |> Tincture.text_field(50, 510, 240, 22, "password", value: "secret", password: true)
  |> Tincture.text_field(310, 510, 240, 22, "greek",
    value: "Ελλάδα",
    font: "Sans",
    full_font: true
  )
  |> label.(482, "Dropdown / editable dropdown, free value")
  |> Tincture.choice_field(50, 460, 240, 22, "combo",
    options: ["Italy", "Norway", "Japan"],
    value: "Norway"
  )
  |> Tincture.choice_field(310, 460, 240, 22, "editable",
    options: ["Italy", "Norway"],
    value: "Peru",
    editable: true
  )
  |> label.(410, "List box, selection scrolled into view (/TI) / sorted list box")
  |> Tincture.choice_field(50, 360, 240, 50, "list",
    options: ["one", "two", "three", "four", "five", "six"],
    value: "five",
    dropdown: false
  )
  |> Tincture.choice_field(310, 360, 240, 50, "sorted",
    options: ["banana", "Apple", "cherry"],
    value: "banana",
    dropdown: false,
    sort: true
  )
  |> label.(332, "Dropdown in the embedded font")
  |> Tincture.choice_field(50, 310, 240, 22, "greek_combo",
    options: ["Αθήνα", "Πάτρα", "Βόλος"],
    value: "Πάτρα",
    font: "Sans",
    full_font: true
  )

File.mkdir_p!(Path.dirname(out))
File.write!(out, Tincture.export(pdf))
IO.puts("wrote #{out}")
