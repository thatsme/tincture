defmodule Tincture.BankStatementShowcaseTest do
  use ExUnit.Case

  alias Tincture.Showcase.BankStatement

  test "multi-page bank statement showcase renders end-to-end with templates, tables, metadata, and bookmarks" do
    %{
      pdf: pdf,
      doc_result: doc_result,
      transaction_results: transaction_results,
      summary_result: summary_result
    } = BankStatement.build_document()

    pdf_binary = Tincture.export(pdf)

    assert doc_result.pages_used == 3
    assert length(transaction_results) == 3
    assert Enum.all?(transaction_results, fn {_page, result} -> result.rows == 19 end)
    assert Enum.all?(transaction_results, fn {_page, result} -> result.columns == 5 end)
    assert summary_result.rows == 4
    assert summary_result.columns == 2

    assert pdf_binary =~ "/Count 3"
    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Type /Outlines"
    assert pdf_binary =~ "/Title (Bank Statement Showcase Demo)"
    assert pdf_binary =~ "/Title (Account Overview)"
    assert pdf_binary =~ "/Title (Transactions - Continued)"
    assert pdf_binary =~ "/Title (Disclosures and Support)"
    assert pdf_binary =~ "(Fjord Community Bank - Statement 1/3) Tj"
    assert pdf_binary =~ "(Fjord Community Bank - Statement 3/3) Tj"
    assert pdf_binary =~ "(Account: 5550010420) Tj"
    assert pdf_binary =~ "(POS PURCHASE 0001) Tj"
    assert pdf_binary =~ "(ENDING BALANCE) Tj"
  end

  test "joint fee/interest statement variant renders with variant-specific markers" do
    %{
      pdf: pdf,
      doc_result: doc_result,
      transaction_results: transaction_results,
      summary_result: summary_result
    } = BankStatement.build_document(:joint_fee_interest)

    pdf_binary = Tincture.export(pdf)

    assert doc_result.pages_used == 3
    assert length(transaction_results) == 3
    assert Enum.all?(transaction_results, fn {_page, result} -> result.rows == 19 end)
    assert summary_result.rows == 4
    assert summary_result.columns == 2

    assert pdf_binary =~ "/Count 3"
    assert pdf_binary =~ "/Title (Bank Statement Joint Fee/Interest Showcase Demo)"
    assert pdf_binary =~ "/Title (Fees and Interest Activity)"
    assert pdf_binary =~ "(JOINT ACCOUNT STATEMENT) Tj"
    assert pdf_binary =~ "(Account: 5550099911) Tj"
    assert pdf_binary =~ "MONTHLY SERVICE FEE"
    assert pdf_binary =~ "INTEREST PAYMENT"
  end
end
