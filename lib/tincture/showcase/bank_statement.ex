defmodule Tincture.Showcase.BankStatement do
  @moduledoc false

  alias Tincture.Layout.Table
  alias Tincture.Layout.Template.DocumentResult
  alias Tincture.Layout.Template.RenderResult

  @type variant :: :retail_spending | :joint_fee_interest

  @type build_result :: %{
          pdf: Tincture.PDF.t(),
          doc_result: DocumentResult.t(),
          summary_result: Table.RenderResult.t(),
          transaction_results: [{pos_integer(), Table.RenderResult.t()}]
        }

  @spec build_document() :: build_result()
  def build_document do
    build_document(:retail_spending)
  end

  @spec build_document(variant()) :: build_result()
  def build_document(variant) when variant in [:retail_spending, :joint_fee_interest] do
    config = variant_config(variant)
    logo_path = write_test_logo_png!()

    try do
      pdf =
        Tincture.new()
        |> Tincture.page_size(:letter)
        |> Tincture.set_metadata(
          title: config.metadata_title,
          author: "Tincture",
          subject: config.metadata_subject,
          keywords: config.metadata_keywords
        )
        |> Tincture.add_page()
        |> Tincture.add_page()
        |> add_bookmarks(config.bookmarks)
        |> Tincture.set_page(1)
        |> draw_page_chrome(1, 3, config)
        |> Tincture.image_png(48, 736, 18, 18, logo_path)
        |> Tincture.set_font("Helvetica-Bold", 16)
        |> Tincture.text_at(72, 734, config.hero_title)
        |> Tincture.set_font("Helvetica", 10)
        |> Tincture.text_at(48, 716, config.account_line)
        |> Tincture.text_at(48, 702, config.period_line)
        |> Tincture.text_at_rotated(448, 716, 25, config.stamp_text)

      {pdf, summary_result} =
        Table.render(pdf, 48, 686, [170, 140], summary_rows(variant),
          header_rows: 0,
          font: "Helvetica",
          header_font: "Helvetica-Bold",
          font_size: 9,
          padding: 3,
          valign: :middle
        )

      {pdf, transaction_results} = render_transactions(pdf, transaction_rows(variant), config)

      pdf =
        pdf
        |> Tincture.set_page(3)
        |> Tincture.set_font("Helvetica-Bold", 11)
        |> Tincture.text_at(48, 242, "Support and Disclosures")
        |> Tincture.set_font("Helvetica", 9)
        |> Tincture.text_at(48, 228, "Customer support: (800) 555-0199")
        |> Tincture.text_at(48, 216, "Fraud hotline: (800) 555-0411")
        |> Tincture.text_at(48, 204, "This statement includes simulated transactions for testing.")

      doc_result = %DocumentResult{
        pages_used: 3,
        overflow?: false,
        spill_text: "",
        page_results: [%RenderResult{}, %RenderResult{}, %RenderResult{}]
      }

      %{
        pdf: pdf,
        doc_result: doc_result,
        summary_result: summary_result,
        transaction_results: transaction_results
      }
    after
      File.rm(logo_path)
    end
  end

  @spec pdf_binary() :: binary()
  def pdf_binary do
    %{pdf: pdf} = build_document()
    Tincture.export(pdf)
  end

  @spec pdf_binary(variant()) :: binary()
  def pdf_binary(variant) when variant in [:retail_spending, :joint_fee_interest] do
    %{pdf: pdf} = build_document(variant)
    Tincture.export(pdf)
  end

  @spec write_pdf(Path.t()) :: Path.t()
  def write_pdf(path \\ "tmp/bank_statement_showcase.pdf") when is_binary(path) do
    write_pdf(path, :retail_spending)
  end

  @spec write_pdf(Path.t(), variant()) :: Path.t()
  def write_pdf(path, variant)
      when is_binary(path) and variant in [:retail_spending, :joint_fee_interest] do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pdf_binary(variant))
    path
  end

  defp render_transactions(pdf, rows, config) do
    Enum.reduce(1..3, {pdf, []}, fn page, {acc_pdf, acc_results} ->
      chunk = Enum.slice(rows, (page - 1) * 18, 18)

      table_rows = [
        ["Date", "Description", "Debit", "Credit", "Balance"] | chunk
      ]

      table_top = if page == 1, do: 564, else: 676

      page_pdf =
        acc_pdf
        |> Tincture.set_page(page)
        |> maybe_draw_page_chrome(page, 3, config)
        |> Tincture.set_font("Helvetica-Bold", 10)
        |> Tincture.text_at(48, table_top + 16, "Transactions (Page #{page})")

      {page_pdf, result} =
        Table.render(page_pdf, 48, table_top, :auto, table_rows,
          header_rows: 1,
          font: "Helvetica",
          header_font: "Helvetica-Bold",
          font_size: 8,
          padding: 3,
          valign: :middle,
          table_width: 516,
          min_col_width: 45
        )

      {page_pdf, acc_results ++ [{page, result}]}
    end)
  end

  defp summary_rows(:retail_spending) do
    [
      ["Opening Balance", "$2500.00"],
      ["Deposits and Credits", "$1160.00"],
      ["Withdrawals and Debits", "-$927.44"],
      ["ENDING BALANCE", "$2732.56"]
    ]
  end

  defp summary_rows(:joint_fee_interest) do
    [
      ["Opening Balance", "$10420.11"],
      ["Fees and Charges", "-$86.75"],
      ["Interest Earned", "$39.20"],
      ["ENDING BALANCE", "$10634.56"]
    ]
  end

  defp transaction_rows(:retail_spending) do
    {rows, _final_balance} =
      Enum.map_reduce(1..54, 2500.0, fn idx, balance ->
        delta =
          cond do
            rem(idx, 9) == 0 -> 210.0 + idx
            rem(idx, 5) == 0 -> -(52.75 + idx / 8)
            rem(idx, 3) == 0 -> -(18.10 + idx / 10)
            true -> -(7.35 + rem(idx, 4))
          end

        next_balance = Float.round(balance + delta, 2)
        day = rem(idx - 1, 28) + 1

        row = [
          "2026-01-" <> String.pad_leading(Integer.to_string(day), 2, "0"),
          "POS PURCHASE " <> String.pad_leading(Integer.to_string(idx), 4, "0"),
          if(delta < 0, do: money(-delta), else: ""),
          if(delta > 0, do: money(delta), else: ""),
          money(next_balance)
        ]

        {row, next_balance}
      end)

    rows
  end

  defp transaction_rows(:joint_fee_interest) do
    {rows, _final_balance} =
      Enum.map_reduce(1..54, 10420.11, fn idx, balance ->
        {description, delta} =
          cond do
            rem(idx, 12) == 0 ->
              {"MONTHLY SERVICE FEE " <> String.pad_leading(Integer.to_string(idx), 4, "0"),
               -14.0}

            rem(idx, 9) == 0 ->
              {"INTEREST PAYMENT " <> String.pad_leading(Integer.to_string(idx), 4, "0"),
               6.25 + idx / 20}

            rem(idx, 5) == 0 ->
              {"ATM WITHDRAWAL " <> String.pad_leading(Integer.to_string(idx), 4, "0"),
               -(42.0 + idx / 10)}

            rem(idx, 4) == 0 ->
              {"ACH PAYROLL " <> String.pad_leading(Integer.to_string(idx), 4, "0"), 320.0 + idx}

            true ->
              {"DEBIT CARD " <> String.pad_leading(Integer.to_string(idx), 4, "0"),
               -(11.5 + rem(idx, 7))}
          end

        next_balance = Float.round(balance + delta, 2)
        day = rem(idx - 1, 28) + 1

        row = [
          "2026-02-" <> String.pad_leading(Integer.to_string(day), 2, "0"),
          description,
          if(delta < 0, do: money(-delta), else: ""),
          if(delta > 0, do: money(delta), else: ""),
          money(next_balance)
        ]

        {row, next_balance}
      end)

    rows
  end

  defp money(value) when is_number(value) do
    "$" <> :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp add_bookmarks(pdf, bookmarks) do
    Enum.reduce(bookmarks, pdf, fn {title, page}, acc ->
      Tincture.add_bookmark(acc, title, page)
    end)
  end

  defp maybe_draw_page_chrome(pdf, 1, _total, _config), do: pdf
  defp maybe_draw_page_chrome(pdf, page, total, config), do: draw_page_chrome(pdf, page, total, config)

  defp draw_page_chrome(pdf, page, total, config) do
    pdf
    |> Tincture.set_font("Helvetica-Bold", 11)
    |> Tincture.text_at(48, 758, interpolate_page(config.header_text, page, total))
    |> Tincture.set_font("Helvetica", 9)
    |> Tincture.text_at(48, 30, interpolate_page(config.footer_text, page, total))
  end

  defp interpolate_page(text, page, total) do
    text
    |> String.replace("{page}", Integer.to_string(page))
    |> String.replace("{total}", Integer.to_string(total))
  end

  defp variant_config(:retail_spending) do
    %{
      header_text: "Fjord Community Bank - Statement {page}/{total}",
      footer_text: "Account **** 0420 - Page {page} of {total}",
      metadata_title: "Bank Statement Showcase Demo",
      metadata_subject: "Multi-page statement integration test",
      metadata_keywords: "bank-statement,showcase,pdf",
      hero_title: "BANK STATEMENT",
      account_line: "Account: 5550010420",
      period_line: "Statement Period: 2026-01-01 to 2026-01-31",
      stamp_text: "E-STATEMENT",
      bookmarks: [
        {"Account Overview", 1},
        {"Transactions - Continued", 2},
        {"Disclosures and Support", 3}
      ]
    }
  end

  defp variant_config(:joint_fee_interest) do
    %{
      header_text: "Fjord Community Bank - Joint Statement {page}/{total}",
      footer_text: "Joint Account **** 9911 - Page {page} of {total}",
      metadata_title: "Bank Statement Joint Fee/Interest Showcase Demo",
      metadata_subject: "Joint account fees and interest integration test",
      metadata_keywords: "bank-statement,joint,fees,interest,showcase,pdf",
      hero_title: "JOINT ACCOUNT STATEMENT",
      account_line: "Account: 5550099911",
      period_line: "Statement Period: 2026-02-01 to 2026-02-28",
      stamp_text: "RECONCILED",
      bookmarks: [
        {"Account Overview", 1},
        {"Fees and Interest Activity", 2},
        {"Disclosures and Support", 3}
      ]
    }
  end

  defp write_test_logo_png! do
    path =
      Path.join(
        System.tmp_dir!(),
        "tincture_statement_logo_#{System.unique_integer([:positive])}.png"
      )

    :ok = File.write(path, test_logo_png_binary())
    path
  end

  defp test_logo_png_binary do
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = <<1::32-big, 1::32-big, 8, 6, 0, 0, 0>>
    idat = :zlib.compress(<<0, 0, 30, 120, 255>>)

    signature <>
      png_chunk("IHDR", ihdr) <>
      png_chunk("IDAT", idat) <>
      png_chunk("IEND", "")
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32-big, type::binary-size(4), data::binary, crc::32-big>>
  end
end
