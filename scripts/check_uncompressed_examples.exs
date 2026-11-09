# Compare the examples built with `compress: false` with the bytes pinned for
# them: those Tincture 0.4.1, the release before stream compression, wrote.
#
#     TINCTURE_EXAMPLES_UNCOMPRESSED=1 mix examples
#     elixir scripts/check_uncompressed_examples.exs
#
# `compress: false` is meant to change nothing but compression, so every
# example built with it must be byte-identical to 0.4.1's file. Those files
# are pinned by SHA-256 in scripts/uncompressed_examples.tsv, one row per
# committed example: its path under examples/output, its size, and the hash.
# An example whose own script has changed since is pinned to its new bytes
# instead, and the TSV says which and why. A signed example mints a new key on
# every run, so its /Contents differs each time; its row gives the /Contents
# span, and the hash covers every byte outside it, which must still match.
#
# The built files are read from tmp/examples-uncompressed, where the examples
# write when TINCTURE_EXAMPLES_UNCOMPRESSED is set. A missing file, an extra
# PDF, or any difference exits 1. Lines of the TSV starting with # are
# comments.

defmodule CheckUncompressedExamples do
  @pins "scripts/uncompressed_examples.tsv"
  @built "tmp/examples-uncompressed"

  def run([]) do
    pins = read_pins()
    built = pdfs(@built)

    extra = built -- Enum.map(pins, & &1.path)
    results = Enum.map(pins, &compare/1) ++ Enum.map(extra, &unexpected/1)

    if Enum.all?(results) do
      IO.puts("PASS  all #{length(pins)} examples built with compress: false match their pinned bytes")
    else
      System.halt(1)
    end
  end

  defp compare(pin) do
    path = Path.join(@built, pin.path)

    with {:ok, binary} <- File.read(path),
         {span, digest} = digest(binary),
         true <- byte_size(binary) == pin.size || {:size, byte_size(binary), pin.size},
         true <- span_text(span) == pin.span || {:contents_span, span_text(span), pin.span},
         true <- digest == pin.digest || {:sha256, digest, pin.digest} do
      outside = if pin.span == "-", do: "", else: " outside /Contents"
      IO.puts("ok    #{pin.path} matches#{outside}")
      true
    else
      {:error, reason} ->
        IO.puts("FAIL  #{pin.path}: not built (#{reason})")
        false

      difference ->
        IO.puts("FAIL  #{pin.path} differs from its pinned bytes: #{inspect(difference)}")
        false
    end
  end

  defp unexpected(relative) do
    IO.puts("FAIL  #{relative}: built, but no bytes are pinned for it")
    false
  end

  # The SHA-256 of the file, or, for a signed file, of every byte outside its
  # /Contents hex string, with the span it left out.
  defp digest(binary) do
    case contents_span(binary) do
      nil ->
        {nil, sha256(binary)}

      {start, stop} = span ->
        outside = [binary_part(binary, 0, start), binary_part(binary, stop, byte_size(binary) - stop)]
        {span, sha256(outside)}
    end
  end

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  # The signature's /Contents hex string, from just after "<" to the ">", in a
  # file that has a /ByteRange; nil in an unsigned file.
  defp contents_span(binary) do
    with {_, _} <- :binary.match(binary, "/ByteRange ["),
         {at, length} <- :binary.match(binary, "/Contents <"),
         start = at + length,
         {stop, 1} <- :binary.match(binary, ">", scope: {start, byte_size(binary) - start}) do
      {start, stop}
    else
      :nomatch -> nil
    end
  end

  defp span_text(nil), do: "-"
  defp span_text({start, stop}), do: "#{start}-#{stop}"

  defp pdfs(root) do
    root
    |> Path.join("**/*.pdf")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  defp read_pins do
    @pins
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      [path, size, digest, span] = String.split(line, "\t")
      %{path: path, size: String.to_integer(size), digest: digest, span: span}
    end)
  end
end

CheckUncompressedExamples.run(System.argv())
