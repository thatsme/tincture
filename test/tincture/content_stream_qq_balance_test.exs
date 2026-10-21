defmodule Tincture.ContentStreamQqBalanceTest do
  @moduledoc """
  The content-stream checker holds every stream to ISO 32000-1 §8.4.2: "Occurrences
  of the q and Q operators shall be balanced within a given content stream".
  A form XObject is a content stream of its own, so this applies to each one
  separately from the page that places it.
  """
  use ExUnit.Case, async: true

  alias Tincture.Test.ContentStreamState

  defp operators(stream),
    do: stream |> ContentStreamState.check_stream() |> Enum.map(&{&1.operator, &1.state})

  test "T25: a q left open at the end of the stream is reported" do
    assert operators("q 1 0 0 1 10 10 cm 0 0 5 5 re f") ==
             [{"<end of stream, 1 graphics state(s) saved and not restored>", :page}]
  end

  test "T25: a Q with nothing saved is reported" do
    assert operators("0 0 5 5 re f Q") == [{"Q (no graphics state saved)", :page}]
  end

  test "T25: balanced and nested q/Q pass" do
    assert operators("q q 0 0 5 5 re f Q /Fm1 Do Q") == []
  end

  test "T25: a q refused in its state saves nothing, so it is reported once, not twice" do
    assert operators("BT /F1 12 Tf q ET") == [{"q", :text}]
  end

  test "T25: an unbalanced form XObject in a file is reported against its own object" do
    data = "q\nQ\nQ\n"
    body = "<< /Type /XObject /Subtype /Form /BBox [0 0 10 10] /Length #{byte_size(data)} >>"
    object = "1 0 obj\n#{body}\nstream\n#{data}\nendstream\nendobj\n"
    header = "%PDF-1.4\n"
    offset = byte_size(header)

    xref =
      "xref\n0 2\n0000000000 65535 f \n" <>
        String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"

    trailer_at = byte_size(header <> object)
    file = header <> object <> xref <> "trailer\n<< /Size 2 >>\nstartxref\n#{trailer_at}\n%%EOF\n"

    assert %{streams: 1, violations: [violation]} = ContentStreamState.check_pdf(file)
    assert violation.object == 1
    assert violation.operator == "Q (no graphics state saved)"
  end
end
