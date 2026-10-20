# Extracts what an external verifier needs from a signed PDF.
#
#     elixir scripts/extract_signature.exs examples/output/signed.pdf tmp/sig
#
# writes two files into the output directory:
#
#   signature.der  the detached CMS SignedData, as DER
#   content.bin    the bytes the /ByteRange covers, concatenated
#
# which `openssl cms -verify` then checks:
#
#     openssl cms -verify -binary -inform DER -in tmp/sig/signature.der \
#       -content tmp/sig/content.bin -noverify -out /dev/null
#
# It reads the file the way any verifier does, from the bytes alone, and shares
# no code with Tincture.PDF.Sign or Tincture.PDF.CMS. A check that reused the
# code it is checking would agree with that code's mistakes.
#
# The blob is cut to the length its own DER header declares, not by stripping
# trailing zeros from the padded /Contents: a signature can end in a zero byte.
#
# Plain Elixir with no dependencies, and not a Mix task: those live in lib/ and
# would ship.

defmodule Tincture.ExtractSignature do
  def main([pdf_path, out_dir]) do
    pdf = File.read!(pdf_path)
    [start_one, length_one, start_two, length_two] = byte_range(pdf)

    check(start_one == 0, "the byte range does not start at the beginning of the file")

    check(
      start_two + length_two == byte_size(pdf),
      "the byte range does not reach the end of the file"
    )

    check(start_two > length_one, "the two byte ranges overlap")

    gap = binary_part(pdf, length_one, start_two - length_one)
    content = binary_part(pdf, start_one, length_one) <> binary_part(pdf, start_two, length_two)

    File.mkdir_p!(out_dir)
    File.write!(Path.join(out_dir, "signature.der"), signature(gap))
    File.write!(Path.join(out_dir, "content.bin"), content)

    IO.puts(
      "#{pdf_path}: byte range [#{start_one} #{length_one} #{start_two} #{length_two}], " <>
        "#{byte_size(content)} signed bytes, written to #{out_dir}"
    )
  end

  def main(_args) do
    IO.puts(:stderr, "usage: elixir scripts/extract_signature.exs <signed.pdf> <out_dir>")
    System.halt(2)
  end

  # Exactly one signature: a second /ByteRange would mean this script cannot
  # say which one it checked.
  defp byte_range(pdf) do
    case Regex.scan(~r/\/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]/, pdf) do
      [[_match | numbers]] -> Enum.map(numbers, &String.to_integer/1)
      [] -> fail("no /ByteRange found")
      _many -> fail("more than one /ByteRange found")
    end
  end

  # The excluded span is the /Contents hex string, angle brackets included.
  defp signature(gap) do
    case Regex.run(~r/\A<([0-9A-Fa-f]+)>\z/, gap) do
      [_match, hex] -> hex |> Base.decode16!(case: :mixed) |> der_value()
      nil -> fail("the bytes outside the byte range are not a single hex string")
    end
  end

  # A SEQUENCE, cut to its declared length.
  defp der_value(<<0x30, length, _rest::binary>> = der) when length < 0x80,
    do: take(der, 2 + length)

  defp der_value(<<0x30, first, rest::binary>> = der) when first > 0x80 do
    count = first - 0x80
    <<length::unsigned-big-size(count)-unit(8), _tail::binary>> = rest
    take(der, 2 + count + length)
  end

  defp der_value(_other), do: fail("/Contents does not hold a DER SEQUENCE")

  defp take(der, size) when size <= byte_size(der), do: binary_part(der, 0, size)
  defp take(_der, _size), do: fail("the DER length runs past the end of /Contents")

  defp check(true, _message), do: :ok
  defp check(false, message), do: fail(message)

  defp fail(message) do
    IO.puts(:stderr, "extract_signature: " <> message)
    System.halt(1)
  end
end

Tincture.ExtractSignature.main(System.argv())
