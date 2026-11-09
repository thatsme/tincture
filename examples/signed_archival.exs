Code.require_file("support/fonts.exs", __DIR__)
Code.require_file("support/checks.exs", __DIR__)

# A signed archival document: PDF/A-2a, tagged, so PDF/UA-1 as well, and
# digitally signed.
#
# An archival file can carry a signature (ISO 19005-2 clause 6.4.3), as long
# as it is a detached PKCS#7 signature, its field draws itself, and the font
# its label draws with is in the file. Tagged, the signature widget is owned
# by a Form structure element inside the paragraph that draws its label, and
# its :tooltip is the name a screen reader announces.
#
# As in signed.exs, the example mints a throwaway self-signed certificate so
# it runs anywhere. It proves the document has not changed since signing; it
# says nothing about who signed it.
#
#     verapdf --flavour 2a examples/output/signed_archival.pdf
#     verapdf --flavour 2b examples/output/signed_archival.pdf
#     verapdf --flavour 2u examples/output/signed_archival.pdf
#     verapdf --flavour ua1 examples/output/signed_archival.pdf

page_w = 595
page_h = 842
margin = 56

ink = {0.13, 0.14, 0.16}
muted = {0.42, 0.45, 0.50}
accent = {0.06, 0.35, 0.55}
rule_grey = {0.85, 0.86, 0.88}

# --- a throwaway signer ----------------------------------------------------
IO.puts("generating a self-signed certificate...")

{:RSAPrivateKey, _v, modulus, exponent, _d, _p, _q, _e1, _e2, _c, _o} =
  private_key = :public_key.generate_key({:rsa, 2048, 65_537})

name =
  {:rdnSequence,
   [
     [{:AttributeTypeAndValue, {2, 5, 4, 6}, ~c"GB"}],
     [{:AttributeTypeAndValue, {2, 5, 4, 10}, {:printableString, ~c"Northgate Instruments Ltd"}}],
     [{:AttributeTypeAndValue, {2, 5, 4, 3}, {:printableString, ~c"M. Kaur"}}]
   ]}

certificate =
  :public_key.pkix_sign(
    {:OTPTBSCertificate, :v3, 1, {:SignatureAlgorithm, {1, 2, 840, 113_549, 1, 1, 11}, :asn1_NOVALUE},
     name, {:Validity, {:utcTime, ~c"260101000000Z"}, {:utcTime, ~c"360101000000Z"}}, name,
     {:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, {1, 2, 840, 113_549, 1, 1, 1}, :asn1_NOVALUE},
      {:RSAPublicKey, modulus, exponent}}, :asn1_NOVALUE, :asn1_NOVALUE, :asn1_NOVALUE},
    private_key
  )

# --- the document ----------------------------------------------------------
{pdf, embedded?} =
  Tincture.new()
  |> Tincture.page_size(:a4)
  |> Tincture.set_metadata(
    title: "Calibration acceptance NGI-CA-0388",
    author: "Northgate Instruments Ltd",
    subject: "Signed acceptance of a calibration, retained with the certificate",
    keywords: "calibration, acceptance, archival, signature"
  )
  |> Tincture.set_language("en-GB")
  |> Tincture.set_pdf_a(:a2a)
  |> Examples.Fonts.register("Body", "Sans")

unless embedded? do
  IO.puts("""
  No embeddable TrueType font was found on this machine, so the text falls
  back to the standard 14 fonts, which PDF/A forbids. The document below is
  exported with `enforce: false`: it is still produced, and it will not
  validate.
  """)
end

sans = Examples.Fonts.resolve("Sans", embedded?)
body = Examples.Fonts.resolve("Body", embedded?)

heading = fn pdf, level, y, text ->
  {size, colour} = if level == :h1, do: {20, accent}, else: {13, ink}

  pdf
  |> Tincture.tag(level, fn pdf ->
    pdf
    |> Tincture.set_fill_color(colour)
    |> Tincture.set_font(sans, size)
    |> Tincture.text_at(margin, y, text)
  end)
  |> Tincture.add_bookmark(text, pdf.current_page)
end

# A paragraph of lines, drawn and tagged together.
paragraph = fn pdf, y, lines ->
  Tincture.tag(pdf, :p, fn pdf ->
    lines
    |> Enum.with_index()
    |> Enum.reduce(
      pdf |> Tincture.set_fill_color(ink) |> Tincture.set_font(body, 10.5),
      fn {line, i}, pdf -> Tincture.text_at(pdf, margin, y - i * 15, line) end
    )
  end)
end

rule = fn pdf, x, y, width ->
  Tincture.artifact(pdf, fn pdf ->
    pdf
    |> Tincture.set_stroke_color(rule_grey)
    |> Tincture.set_line_width(0.75)
    |> Tincture.line(x, y, x + width, y)
  end)
end

top = page_h - margin
sign_y = top - 360

pdf =
  Tincture.tag(pdf, :document, fn pdf ->
    pdf
    |> heading.(:h1, top - 30, "Calibration acceptance")
    |> Tincture.tag(:p, fn pdf ->
      pdf
      |> Tincture.set_fill_color(muted)
      |> Tincture.set_font(sans, 9)
      |> Tincture.text_at(margin, top - 50, "NGI-CA-0388 · Northgate Instruments Ltd")
    end)
    |> rule.(margin, top - 64, page_w - margin * 2)
    |> Tincture.tag(:section, fn pdf ->
      pdf
      |> heading.(:h2, top - 100, "The calibration")
      |> paragraph.(top - 124, [
        "The pressure gauge NGI-PG-1142 was calibrated on 3 November 2026 against",
        "the laboratory's reference standard, at seven points across its range.",
        "Every reading fell within the tolerance its specification states, and",
        "the certificate NGI-C-4471 records the results."
      ])
    end)
    |> Tincture.tag(:section, fn pdf ->
      pdf
      |> heading.(:h2, top - 220, "Acceptance")
      |> paragraph.(top - 244, [
        "By signing below, the approving engineer accepts the calibration and",
        "releases the instrument for use until its next calibration falls due."
      ])
      |> Tincture.tag(:p, fn pdf ->
        pdf
        |> Tincture.set_fill_color(muted)
        |> Tincture.set_font(sans, 9)
        |> Tincture.text_at(margin, sign_y + 62, "Signature of the approving engineer")
        # The field is placed first, then signed: the signature is applied
        # during export, once the file exists.
        |> Tincture.signature_field(margin, sign_y, 260, 50, "approval",
          label: "Approved: M. Kaur",
          font: sans,
          size: 11,
          border: {0, 0, 0.75},
          tooltip: "Digital signature of the approving engineer"
        )
      end)
    end)
  end)
  |> Tincture.sign("approval",
    private_key: private_key,
    certificate: certificate,
    name: "M. Kaur",
    reason: "I accept this calibration",
    location: "Sheffield",
    digest: :sha256,
    signing_time: ~U[2026-11-04 15:30:00Z]
  )

binary =
  if embedded?,
    do: Tincture.export(pdf, compress: Examples.Fonts.compress?()),
    else: Tincture.export(pdf, enforce: false, compress: Examples.Fonts.compress?())
path = Examples.Fonts.output_path("signed_archival.pdf")
File.write!(path, binary)

# The checks read the streams inflated; the size is the file's.
file_size = byte_size(binary)
binary = Examples.Checks.inflated(binary)

IO.puts("wrote #{Path.relative_to_cwd(path)} — #{file_size} bytes")

signature_widget =
  case Regex.run(~r|<< [^\n]*/FT /Sig /T \(approval\)[^\n]*|, binary) do
    [dictionary] -> dictionary
    nil -> ""
  end

checks =
  [
    {"conformance in XMP, level A", "set_pdf_a/2", binary =~ ~s(pdfaid:conformance>A<)},
    {"PDF/UA identification in XMP", "tagged", binary =~ "<pdfuaid:part>1</pdfuaid:part>"},
    {"/SigFlags 3", "6.4.3", binary =~ "/SigFlags 3"},
    # Padded with spaces: the offsets are patched in after signing, into
    # space reserved before the file was laid out.
    {"/ByteRange", "6.4.3", binary =~ ~r|/ByteRange \[\s*\d+\s+\d+\s+\d+\s+\d+\s*\]|},
    {"/SubFilter /adbe.pkcs7.detached", "6.4.3-1", binary =~ "/SubFilter /adbe.pkcs7.detached"},
    {"signature widget: /AP /N a stream", "6.3.3-1, 6.3.3-4",
     signature_widget =~ ~r|/AP << /N \d+ 0 R >>|},
    {"label in an embedded font", "6.2.11.4.1",
     if(embedded?, do: true, else: {:note, "NO - standard 14 in use"})}
  ] ++ Examples.Checks.form_rows(binary, widgets: 1, fields: 1, headings: 3)

IO.puts("""

What the signed archival document needed, and where it came from:

#{Examples.Checks.table(checks)}

Validate it:

    verapdf --flavour 2a #{Path.relative_to_cwd(path)}
    verapdf --flavour 2b #{Path.relative_to_cwd(path)}
    verapdf --flavour 2u #{Path.relative_to_cwd(path)}
    verapdf --flavour ua1 #{Path.relative_to_cwd(path)}
""")

Examples.Checks.halt_if_missing(checks)
