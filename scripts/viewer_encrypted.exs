# Writes one document twice, unencrypted and encrypted with the user password
# "p", for scripts/encrypted_render_check.py: an image with a soft mask, a
# placed form XObject, and a filled form (text, choice, checkbox, radio group,
# push button and a visible signature field).
#
#   mix run scripts/viewer_encrypted.exs <out_dir>
#
# Writes <out_dir>/plain.pdf, <out_dir>/encrypted.pdf and the PNG the document
# embeds. A reader that decrypts the second file as ISO 32000-1 7.6.2 requires
# should draw exactly what it draws for the first.

[out_dir] = System.argv()
File.mkdir_p!(out_dir)

# 2 x 2 RGBA: red, green, blue, and white at half opacity, so the image
# carries a soft mask.
png = Path.join(out_dir, "image.png")

chunk = fn type, data ->
  <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
end

rows = <<0, 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255, 128>>

File.write!(
  png,
  <<137, 80, 78, 71, 13, 10, 26, 10>> <>
    chunk.("IHDR", <<2::32, 2::32, 8, 6, 0, 0, 0>>) <>
    chunk.("IDAT", :zlib.compress(rows)) <> chunk.("IEND", "")
)

pdf =
  Tincture.new()
  |> Tincture.set_metadata(title: "Encrypted streams")
  |> Tincture.set_font("Helvetica", 14)
  |> Tincture.text_at(50, 780, "Page text")
  |> Tincture.image_png(50, 640, 120, 120, png)
  |> Tincture.form_xobject("stamp", 160, 50, fn pdf ->
    pdf
    |> Tincture.set_stroke_color({0.7, 0.1, 0.1})
    |> Tincture.rectangle(2, 2, 156, 46)
    |> Tincture.set_font("Helvetica-Bold", 16)
    |> Tincture.text_at(18, 18, "APPROVED")
  end)
  |> Tincture.place_form_xobject("stamp", 200, 680)
  |> Tincture.text_field(50, 580, 240, 22, "name", value: "Ada Lovelace")
  |> Tincture.choice_field(310, 580, 150, 22, "city", options: ["Oslo", "Rome"], value: "Rome")
  |> Tincture.checkbox(50, 540, 14, "agree", checked: true)
  |> Tincture.radio_group(
    "size",
    [[value: "s", x: 100, y: 540, size: 14], [value: "m", x: 130, y: 540, size: 14]],
    value: "m"
  )
  |> Tincture.push_button(50, 490, 90, 24, "reset", label: "Reset", action: :reset)
  |> Tincture.signature_field(50, 410, 220, 50, "approval", label: "Signature of the approver")

File.write!(Path.join(out_dir, "plain.pdf"), Tincture.export(pdf))

File.write!(
  Path.join(out_dir, "encrypted.pdf"),
  pdf |> Tincture.encrypt(user_password: "p") |> Tincture.export()
)

IO.puts("wrote #{out_dir}/plain.pdf and #{out_dir}/encrypted.pdf")
