Code.require_file("support/fonts.exs", __DIR__)

# A digitally signed agreement.
#
# The signature covers the finished file — including where every object landed
# — so it cannot exist until the bytes do. Tincture reserves space for it,
# serialises, measures the real offsets, then signs and patches the result back
# in without moving anything. See `Tincture.PDF.Sign`.
#
# This example mints a throwaway self-signed certificate so it runs anywhere.
# A real signature uses a certificate from an authority a verifier trusts;
# a self-signed one proves the document has not changed, but says nothing about
# who signed it that you did not already have to take on faith.

alias Tincture.Typography.RichText

page_w = 595
page_h = 842
margin = 56
content_w = page_w - margin * 2

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
     # countryName is a PrintableString directly, not the DirectoryString
     # choice the other attributes use, so it takes a bare charlist.
     [{:AttributeTypeAndValue, {2, 5, 4, 6}, ~c"GB"}],
     [{:AttributeTypeAndValue, {2, 5, 4, 10}, {:printableString, ~c"Northgate Instruments Ltd"}}],
     [{:AttributeTypeAndValue, {2, 5, 4, 3}, {:printableString, ~c"R. Aldiss"}}]
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
    title: "Supply agreement NGI-SA-2026-114",
    author: "Northgate Instruments Ltd",
    subject: "Signed supply agreement"
  )
  |> Examples.Fonts.register("Body", "Sans")

body = Examples.Fonts.resolve("Body", embedded?)
sans = Examples.Fonts.resolve("Sans", embedded?)

terms =
  "This agreement is made between Northgate Instruments Ltd and the counterparty " <>
    "named above. The supplier shall deliver the calibration services described in " <>
    "Schedule 1 to the standards set out in Schedule 2, and shall maintain " <>
    "traceability records for the period required by the customer's quality " <>
    "management system. Either party may terminate on ninety days' written notice."

pdf =
  pdf
  |> Tincture.set_fill_color(ink)
  |> Tincture.set_font(body, 21)
  |> Tincture.text_at(margin, page_h - 92, "Supply agreement")
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 9)
  |> Tincture.text_at(margin, page_h - 110, "NGI-SA-2026-114 · Northgate Instruments Ltd")
  |> Tincture.set_stroke_color(rule_grey)
  |> Tincture.set_line_width(0.75)
  |> Tincture.line(margin, page_h - 126, page_w - margin, page_h - 126)
  |> Tincture.stroke()
  |> Tincture.set_fill_color(accent)
  |> Tincture.set_font(sans, 8)
  |> Tincture.text_at(margin, page_h - 156, "TERMS")

{pdf, _lines} =
  {Tincture.text_paragraph(
     pdf |> Tincture.set_fill_color(ink) |> Tincture.set_font(body, 10.5),
     margin,
     page_h - 180,
     RichText.from_plain(terms, font: body, size: 10.5),
     content_w,
     align: :justified,
     line_break: :optimal,
     line_height: 15
   ), nil}

sign_y = 300

pdf =
  pdf
  |> Tincture.set_fill_color(accent)
  |> Tincture.set_font(sans, 8)
  |> Tincture.text_at(margin, sign_y + 74, "SIGNED FOR AND ON BEHALF OF THE SUPPLIER")
  |> Tincture.set_stroke_color(rule_grey)
  |> Tincture.line(margin, sign_y, margin + 260, sign_y)
  |> Tincture.stroke()
  |> Tincture.set_fill_color(muted)
  |> Tincture.set_font(sans, 7.5)
  |> Tincture.text_at(margin, sign_y - 14, "R. Aldiss · Director")
  # The field is placed first, then signed. The signature itself is applied
  # during export, once the file exists.
  |> Tincture.signature_field(margin, sign_y + 4, 260, 56, "supplier_signature",
    tooltip: "Digitally signed by R. Aldiss",
    border: :none
  )
  |> Tincture.sign("supplier_signature",
    private_key: private_key,
    certificate: certificate,
    name: "R. Aldiss",
    reason: "I agree to the terms set out above",
    location: "Sheffield",
    digest: :sha256,
    signing_time: ~U[2026-07-26 12:00:00Z]
  )

binary = Tincture.export(pdf)
path = Examples.Fonts.output_path("signed.pdf")
File.write!(path, binary)

# --- what a verifier sees --------------------------------------------------
[[_, entries]] = Regex.scan(~r/\/ByteRange \[([^\]]*)\]/, binary)
[start_one, length_one, start_two, length_two] = entries |> String.split() |> Enum.map(&String.to_integer/1)

IO.puts("\nwrote #{Path.relative_to_cwd(path)} — #{byte_size(binary)} bytes")

IO.puts("""

The signature covers the file except its own /Contents string:

  bytes #{start_one}–#{length_one} and #{start_two}–#{start_two + length_two}, of #{byte_size(binary)} total
  the #{start_two - length_one} byte gap is exactly the <...> holding the signature

  /SigFlags 3        #{if binary =~ "/SigFlags 3", do: "ok — signed, and append-only", else: "MISSING"}
  detached PKCS#7    #{if binary =~ "/SubFilter /adbe.pkcs7.detached", do: "ok", else: "MISSING"}
  signed at          #{if binary =~ "/M (D:", do: "recorded", else: "MISSING"}

Change any byte outside that gap and the signature stops verifying — which is
the whole point. Check it with:

    openssl asn1parse -inform DER -in <extracted signature>

What this does not give you: proof of *when*. There is no timestamp authority,
so the time above is the signing machine's own claim. Long-term validation
needs an RFC 3161 timestamp, which Tincture does not yet produce.
""")
