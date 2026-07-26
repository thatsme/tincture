defmodule Tincture.FixtureLockScript do
  alias Tincture.Layout.Table
  alias Tincture.Showcase.BankStatement
  alias Tincture.Showcase.Invoice
  alias Tincture.Typography.RichText

  def run do
    check_only? = parse_env_bool("EX_GUTEN_FIXTURE_LOCK_CHECK", false)

    mismatches =
      Enum.flat_map(fixtures(), fn {path, render_fun} ->
        hash = render_fun.() |> sha256_hex()

        case maybe_read_hash(path) do
          {:ok, existing} when existing == hash ->
            maybe_write(path, hash, check_only?)
            []

          {:ok, existing} ->
            maybe_write(path, hash, check_only?)
            ["#{path}: expected #{existing}, actual #{hash}"]

          :missing ->
            maybe_write(path, hash, check_only?)
            ["#{path}: missing fixture lock (would write #{hash})"]
        end
      end)

    case {check_only?, mismatches} do
      {true, []} ->
        IO.puts("Fixture locks: PASS")

      {true, _} ->
        IO.puts("Fixture locks: FAIL")
        Enum.each(mismatches, &IO.puts("  - " <> &1))
        System.halt(1)

      {false, []} ->
        IO.puts("Fixture locks refreshed: no changes")

      {false, _} ->
        IO.puts("Fixture locks refreshed:")
        Enum.each(mismatches, &IO.puts("  - " <> &1))
    end
  end

  defp fixtures do
    [
      {"test/fixtures/pdf/core_text.sha256", &core_text_pdf/0},
      {"test/fixtures/pdf/optimal_typography.sha256", &optimal_typography_pdf/0},
      {"test/fixtures/pdf/table_layout.sha256", &table_layout_pdf/0},
      {"test/fixtures/pdf/invoice_showcase.sha256", &invoice_showcase_pdf/0},
      {"test/fixtures/pdf/bank_statement_showcase.sha256", &bank_statement_showcase_pdf/0},
      {"test/fixtures/pdf/bank_statement_joint_fee_interest_showcase.sha256",
       &bank_statement_joint_fee_interest_showcase_pdf/0}
    ]
  end

  defp maybe_read_hash(path) do
    case File.read(path) do
      {:ok, value} -> {:ok, String.trim(value)}
      {:error, _reason} -> :missing
    end
  end

  defp maybe_write(_path, _hash, true), do: :ok

  defp maybe_write(path, hash, false) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, hash <> "\n")
  end

  defp core_text_pdf do
    Tincture.new()
    |> Tincture.page_size(:letter)
    |> Tincture.set_font("Times-Roman", 16)
    |> Tincture.text_at(72, 720, "Locked fixture: core text")
    |> Tincture.text_at_rotated(300, 300, 30, "Rotation")
    |> Tincture.line(72, 710, 400, 710)
    |> Tincture.export()
  end

  defp optimal_typography_pdf do
    rich =
      RichText.from_plain(
        "aa bb cc dd eeeeee aa- aa- aaa- aa aa- hyphenation strategy",
        font: "Courier",
        size: 10
      )

    Tincture.new()
    |> Tincture.text_paragraph(72, 700, rich, 220,
      align: :justified,
      line_break: :optimal,
      optimal_cost_model: :box_glue,
      justify_max_space_multiplier: 2.0,
      justify_min_space_multiplier: 0.75,
      widow_penalty: 800,
      orphan_penalty: 800,
      hyphen_penalty: 250,
      consecutive_hyphen_penalty: 350,
      fitness_class_penalty: 500
    )
    |> Tincture.export()
  end

  defp table_layout_pdf do
    rows = [
      ["Item", "Qty", "Price"],
      ["Pencil", "12", "$1.50"],
      ["Notebook", "4", "$8.00"],
      ["Eraser", "6", "$0.75"]
    ]

    {pdf, _result} =
      Tincture.new()
      |> Tincture.page_size(:letter)
      |> Table.render(72, 700, :auto, rows,
        header_rows: 1,
        font: "Helvetica",
        header_font: "Helvetica-Bold",
        font_size: 10,
        padding: 4,
        table_width: 280
      )

    Tincture.export(pdf)
  end

  defp invoice_showcase_pdf do
    Invoice.pdf_binary()
  end

  defp bank_statement_showcase_pdf do
    BankStatement.pdf_binary()
  end

  defp bank_statement_joint_fee_interest_showcase_pdf do
    BankStatement.pdf_binary(:joint_fee_interest)
  end

  defp sha256_hex(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  defp parse_env_bool(var, default) do
    case System.get_env(var) do
      nil -> default
      "1" -> true
      "true" -> true
      "TRUE" -> true
      "yes" -> true
      "YES" -> true
      "on" -> true
      "ON" -> true
      "0" -> false
      "false" -> false
      "FALSE" -> false
      "no" -> false
      "NO" -> false
      "off" -> false
      "OFF" -> false
      _ -> default
    end
  end
end

Tincture.FixtureLockScript.run()
