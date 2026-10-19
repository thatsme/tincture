defmodule Examples.Checks do
  @moduledoc """
  The checklists the examples print after writing a file.

  Each row names a requirement, where it is satisfied, and whether the written
  bytes carry it. A row that fails prints `MISSING` and, once the whole table
  has been printed, makes the script exit with status 1 - so a check that fails
  fails the run instead of scrolling past in a log.

  A row's status is one of:

    * `true` / `false` — printed as `ok` / `MISSING`;
    * `{found?, ok_text}` — the same, with its own wording for `ok`;
    * `{:note, text}` — information, never a failure.
  """

  @type status :: boolean() | {boolean(), String.t()} | {:note, String.t()}
  @type row :: {String.t(), String.t(), status()}

  @doc """
  The rows as aligned text, one per line, indented by two spaces.
  """
  @spec table([row()]) :: String.t()
  def table(rows) do
    label_width = column_width(rows, 0)
    where_width = column_width(rows, 1)

    Enum.map_join(rows, "\n", fn {label, where, status} ->
      "  " <>
        String.pad_trailing(label, label_width) <>
        "  " <> String.pad_trailing(where, where_width) <> "  " <> text(status)
    end)
  end

  @doc """
  Exits with status 1 if any row failed. Call it after printing.
  """
  @spec halt_if_missing([row()]) :: :ok
  def halt_if_missing(rows) do
    case Enum.filter(rows, &missing?/1) do
      [] ->
        :ok

      missing ->
        IO.puts(:stderr, "\nMISSING: " <> Enum.map_join(missing, ", ", &elem(&1, 0)))
        System.halt(1)
    end
  end

  defp text(true), do: "ok"
  defp text(false), do: "MISSING"
  defp text({true, ok_text}) when is_binary(ok_text), do: ok_text
  defp text({false, _ok_text}), do: "MISSING"
  defp text({:note, note}), do: note

  defp missing?({_label, _where, false}), do: true
  defp missing?({_label, _where, {false, _ok_text}}), do: true
  defp missing?(_row), do: false

  defp column_width(rows, index),
    do: rows |> Enum.map(&String.length(elem(&1, index))) |> Enum.max()
end
