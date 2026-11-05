# Compare a regenerated signed example with its committed bytes, outside the
# signature.
#
#     elixir scripts/compare_outside_contents.exs examples/output/signed.pdf ...
#
# A signed example mints a new key on every run, so its /Contents - the
# PKCS#7 signature, certificate included - differs each time, and nothing
# else may. For each path this reads the committed bytes (`git show
# HEAD:<path>`) and the file on disk, and requires the same length, the
# /Contents hex string at the same offsets, and identical bytes before and
# after it. Exits 1 on the first difference.

defmodule CompareOutsideContents do
  def run(paths) do
    results = Enum.map(paths, &compare/1)
    if Enum.all?(results), do: :ok, else: System.halt(1)
  end

  defp compare(path) do
    {committed, 0} = System.cmd("git", ["show", "HEAD:" <> path])
    regenerated = File.read!(path)

    with {:ok, {start, stop}} <- contents_span(committed),
         {:ok, {^start, ^stop}} <- contents_span(regenerated),
         true <- byte_size(committed) == byte_size(regenerated),
         true <- binary_part(committed, 0, start) == binary_part(regenerated, 0, start),
         true <- tail(committed, stop) == tail(regenerated, stop) do
      IO.puts("PASS  #{path} matches its committed bytes outside /Contents (#{start}-#{stop})")
      true
    else
      other ->
        IO.puts("FAIL  #{path} differs from its committed bytes outside /Contents: #{inspect(other)}")
        false
    end
  end

  # The first /Contents hex string: the signature's. Its offsets, from just
  # after "<" to the closing ">".
  defp contents_span(binary) do
    case :binary.match(binary, "/Contents <") do
      {at, length} ->
        start = at + length

        case :binary.match(binary, ">", scope: {start, byte_size(binary) - start}) do
          {stop, 1} -> {:ok, {start, stop}}
          :nomatch -> {:error, :unterminated_contents}
        end

      :nomatch ->
        {:error, :no_contents}
    end
  end

  defp tail(binary, from), do: binary_part(binary, from, byte_size(binary) - from)
end

CompareOutsideContents.run(System.argv())
