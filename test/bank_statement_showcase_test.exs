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
    content = Tincture.Test.PDFObjects.decoded(pdf_binary)

    assert doc_result.pages_used == 3
    assert length(transaction_results) == 3
    assert Enum.all?(transaction_results, fn {_page, result} -> result.rows == 19 end)
    assert Enum.all?(transaction_results, fn {_page, result} -> result.columns == 5 end)
    assert summary_result.rows == 4
    assert summary_result.columns == 2

    assert content =~ "/Count 3"
    assert content =~ "/Subtype /Image"
    assert content =~ "/Type /Outlines"
    assert content =~ "/Title (Bank Statement Showcase Demo)"
    assert content =~ "/Title (Account Overview)"
    assert content =~ "/Title (Transactions - Continued)"
    assert content =~ "/Title (Disclosures and Support)"
    assert content =~ "(Fjord Community Bank - Statement 1/3) Tj"
    assert content =~ "(Fjord Community Bank - Statement 3/3) Tj"
    assert content =~ "(Account: 5550010420) Tj"
    assert content =~ "(POS PURCHASE 0001) Tj"
    assert content =~ "(ENDING BALANCE) Tj"
  end

  test "joint fee/interest statement variant renders with variant-specific markers" do
    %{
      pdf: pdf,
      doc_result: doc_result,
      transaction_results: transaction_results,
      summary_result: summary_result
    } = BankStatement.build_document(:joint_fee_interest)

    pdf_binary = Tincture.export(pdf)
    content = Tincture.Test.PDFObjects.decoded(pdf_binary)

    assert doc_result.pages_used == 3
    assert length(transaction_results) == 3
    assert Enum.all?(transaction_results, fn {_page, result} -> result.rows == 19 end)
    assert summary_result.rows == 4
    assert summary_result.columns == 2

    assert content =~ "/Count 3"
    assert content =~ "/Title (Bank Statement Joint Fee/Interest Showcase Demo)"
    assert content =~ "/Title (Fees and Interest Activity)"
    assert content =~ "(JOINT ACCOUNT STATEMENT) Tj"
    assert content =~ "(Account: 5550099911) Tj"
    assert content =~ "MONTHLY SERVICE FEE"
    assert content =~ "INTEREST PAYMENT"
  end
end
