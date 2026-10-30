defmodule Tincture.ButtonAppearanceBytesTest do
  @moduledoc """
  The checkbox, radio, push-button and signature widgets, and every
  appearance stream they carry, byte for byte.

  Pinned before the button builders moved from assembled strings to
  operation lists, so that the move is proved to write the same bytes: each
  document's widget dictionaries and appearance streams, whole, as the
  string builders wrote them. A push button's caption size is the float
  `12.0` in a 24-point button and the integer `12` in a 26-point one, from
  `min(height * 0.5, 12)`; its inline caption font is named `/Helv` whatever
  the field's font.
  """
  use ExUnit.Case, async: true

  # The document's widget, field and form XObject objects, in order, whole.
  defp objects(pdf) do
    binary = Tincture.export(pdf)

    ~r/\n(\d+ 0 obj\n.*?\nendobj)/s
    |> Regex.scan(binary, capture: :all_but_first)
    |> List.flatten()
    |> Enum.filter(&(&1 =~ ~r"/Widget|/FT /Btn|/Subtype /Form"))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  test "a checked checkbox" do
    assert objects(Tincture.checkbox(Tincture.new(), 72, 700, 14, "agree", value: true)) == ~S"""
           5 0 obj
           << /Type /Annot /Subtype /Widget /FT /Btn /T (agree) /Rect [72 700 86 714] /P 3 0 R /F 4 /Border [0 0 0] /DA (/Helv 0 Tf 0 g) /V /Yes /DV /Yes /AS /Yes /AP << /N << /Yes 6 0 R /Off 7 0 R >> >> >>
           endobj
           6 0 obj
           << /Type /XObject /Subtype /Form /BBox [0 0 14 14] /Resources << >> /Length 71 >>
           stream
           0 G 0 g 1 w
           0.5 0.5 13 13 re
           S
           3.08 7.28 m
           5.88 3.92 l
           10.92 10.08 l
           S

           endstream
           endobj
           7 0 obj
           << /Type /XObject /Subtype /Form /BBox [0 0 14 14] /Resources << >> /Length 31 >>
           stream
           0 G 0 g 1 w
           0.5 0.5 13 13 re
           S

           endstream
           endobj
           """
  end

  test "a radio group of two, the first selected" do
    pdf =
      Tincture.radio_group(
        Tincture.new(),
        "plan",
        [[value: "a", x: 72, y: 700, size: 12], [value: "b", x: 92, y: 700, size: 12]],
        selected: "a"
      )

    assert objects(pdf) == ~S"""
           5 0 obj
           << /FT /Btn /T (plan) /Ff 49152 /V /a /DV /a /DA (/Helv 0 Tf 0 g) /Kids [6 0 R 9 0 R] >>
           endobj
           6 0 obj
           << /Type /Annot /Subtype /Widget /Parent 5 0 R /Rect [72 700 84 712] /P 3 0 R /F 4 /Border [0 0 0] /MK << /BC [0] /BG [1] >> /AS /a /AP << /N << /a 7 0 R /Off 8 0 R >> >> >>
           endobj
           7 0 obj
           << /Type /XObject /Subtype /Form /BBox [0 0 12 12] /Resources << >> /Length 336 >>
           stream
           0 G 0 g 1 w
           11.5 6.0 m
           11.5 9.03765 9.03765 11.5 6.0 11.5 c
           2.96235 11.5 0.5 9.03765 0.5 6.0 c
           0.5 2.96235 2.96235 0.5 6.0 0.5 c
           9.03765 0.5 11.5 2.96235 11.5 6.0 c
           S
           8.75 6.0 m
           8.75 7.518825 7.518825 8.75 6.0 8.75 c
           4.481175 8.75 3.25 7.518825 3.25 6.0 c
           3.25 4.481175 4.481175 3.25 6.0 3.25 c
           7.518825 3.25 8.75 4.481175 8.75 6.0 c
           f

           endstream
           endobj
           8 0 obj
           << /Type /XObject /Subtype /Form /BBox [0 0 12 12] /Resources << >> /Length 167 >>
           stream
           0 G 0 g 1 w
           11.5 6.0 m
           11.5 9.03765 9.03765 11.5 6.0 11.5 c
           2.96235 11.5 0.5 9.03765 0.5 6.0 c
           0.5 2.96235 2.96235 0.5 6.0 0.5 c
           9.03765 0.5 11.5 2.96235 11.5 6.0 c
           S

           endstream
           endobj
           9 0 obj
           << /Type /Annot /Subtype /Widget /Parent 5 0 R /Rect [92 700 104 712] /P 3 0 R /F 4 /Border [0 0 0] /MK << /BC [0] /BG [1] >> /AS /Off /AP << /N << /b 10 0 R /Off 11 0 R >> >> >>
           endobj
           10 0 obj
           << /Type /XObject /Subtype /Form /BBox [0 0 12 12] /Resources << >> /Length 336 >>
           stream
           0 G 0 g 1 w
           11.5 6.0 m
           11.5 9.03765 9.03765 11.5 6.0 11.5 c
           2.96235 11.5 0.5 9.03765 0.5 6.0 c
           0.5 2.96235 2.96235 0.5 6.0 0.5 c
           9.03765 0.5 11.5 2.96235 11.5 6.0 c
           S
           8.75 6.0 m
           8.75 7.518825 7.518825 8.75 6.0 8.75 c
           4.481175 8.75 3.25 7.518825 3.25 6.0 c
           3.25 4.481175 4.481175 3.25 6.0 3.25 c
           7.518825 3.25 8.75 4.481175 8.75 6.0 c
           f

           endstream
           endobj
           11 0 obj
           << /Type /XObject /Subtype /Form /BBox [0 0 12 12] /Resources << >> /Length 167 >>
           stream
           0 G 0 g 1 w
           11.5 6.0 m
           11.5 9.03765 9.03765 11.5 6.0 11.5 c
           2.96235 11.5 0.5 9.03765 0.5 6.0 c
           0.5 2.96235 2.96235 0.5 6.0 0.5 c
           9.03765 0.5 11.5 2.96235 11.5 6.0 c
           S

           endstream
           endobj
           """
  end

  describe "a push button" do
    test "24 points high, whose caption size is the float 12.0" do
      pdf =
        Tincture.push_button(Tincture.new(), 72, 700, 90, 24, "send",
          label: "Send",
          action: :reset
        )

      assert objects(pdf) == ~S"""
             5 0 obj
             << /Type /Annot /Subtype /Widget /FT /Btn /T (send) /Rect [72 700 162 724] /P 3 0 R /F 4 /Ff 65536 /Border [0 0 0] /DA (/Helv 0 Tf 0 g) /A << /S /ResetForm >> /MK << /CA (Send) >> /AP << /N 6 0 R >> >>
             endobj
             6 0 obj
             << /Type /XObject /Subtype /Form /BBox [0 0 90 24] /Resources << /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> >> >> /Length 129 >>
             stream
             0.93 0.93 0.94 rg
             0 0 90 24 re
             f
             0.55 0.57 0.60 RG
             0.75 w
             0.4 0.4 89.2 23.2 re
             S
             0 g
             BT
             /Helv 12.0 Tf
             30.99 7.68 Td
             (Send) Tj
             ET

             endstream
             endobj
             """
    end

    test "26 points high, whose caption size is the integer 12" do
      pdf =
        Tincture.push_button(Tincture.new(), 72, 700, 96, 26, "send",
          label: "Send",
          action: :reset
        )

      assert objects(pdf) == ~S"""
             5 0 obj
             << /Type /Annot /Subtype /Widget /FT /Btn /T (send) /Rect [72 700 168 726] /P 3 0 R /F 4 /Ff 65536 /Border [0 0 0] /DA (/Helv 0 Tf 0 g) /A << /S /ResetForm >> /MK << /CA (Send) >> /AP << /N 6 0 R >> >>
             endobj
             6 0 obj
             << /Type /XObject /Subtype /Form /BBox [0 0 96 26] /Resources << /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> >> >> /Length 127 >>
             stream
             0.93 0.93 0.94 rg
             0 0 96 26 re
             f
             0.55 0.57 0.60 RG
             0.75 w
             0.4 0.4 95.2 25.2 re
             S
             0 g
             BT
             /Helv 12 Tf
             33.99 8.68 Td
             (Send) Tj
             ET

             endstream
             endobj
             """
    end

    test "in Courier, whose inline caption font is still named /Helv" do
      pdf =
        Tincture.push_button(Tincture.new(), 72, 700, 90, 24, "send",
          label: "Send",
          action: :reset,
          font: "Courier"
        )

      assert objects(pdf) == ~S"""
             5 0 obj
             << /Type /Annot /Subtype /Widget /FT /Btn /T (send) /Rect [72 700 162 724] /P 3 0 R /F 4 /Ff 65536 /Border [0 0 0] /DA (/Courier 0 Tf 0 g) /A << /S /ResetForm >> /MK << /CA (Send) >> /AP << /N 6 0 R >> >>
             endobj
             6 0 obj
             << /Type /XObject /Subtype /Form /BBox [0 0 90 24] /Resources << /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >> >> >> /Length 128 >>
             stream
             0.93 0.93 0.94 rg
             0 0 90 24 re
             f
             0.55 0.57 0.60 RG
             0.75 w
             0.4 0.4 89.2 23.2 re
             S
             0 g
             BT
             /Helv 12.0 Tf
             30.6 7.68 Td
             (Send) Tj
             ET

             endstream
             endobj
             """
    end

    test "without a label, a face and empty resources" do
      pdf = Tincture.push_button(Tincture.new(), 72, 700, 90, 24, "send", action: :reset)

      assert objects(pdf) == ~S"""
             5 0 obj
             << /Type /Annot /Subtype /Widget /FT /Btn /T (send) /Rect [72 700 162 724] /P 3 0 R /F 4 /Ff 65536 /Border [0 0 0] /DA (/Helv 0 Tf 0 g) /A << /S /ResetForm >> /AP << /N 6 0 R >> >>
             endobj
             6 0 obj
             << /Type /XObject /Subtype /Form /BBox [0 0 90 24] /Resources << >> /Length 81 >>
             stream
             0.93 0.93 0.94 rg
             0 0 90 24 re
             f
             0.55 0.57 0.60 RG
             0.75 w
             0.4 0.4 89.2 23.2 re
             S

             endstream
             endobj
             """
    end
  end

  test "a signature field, which carries no appearance" do
    pdf = Tincture.signature_field(Tincture.new(), 72, 600, 200, 40, "sig")

    assert objects(pdf) == ~S"""
           5 0 obj
           << /Type /Annot /Subtype /Widget /FT /Sig /T (sig) /Rect [72 600 272 640] /P 3 0 R /F 4 /Border [0 0 0] /DA (/Helv 0 Tf 0 g) >>
           endobj
           """
  end
end
