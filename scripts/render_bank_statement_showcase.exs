defmodule Tincture.RenderBankStatementShowcaseScript do
  alias Tincture.Showcase.BankStatement

  def run do
    {variant, out_path} =
      case System.argv() do
        [variant_raw, path | _rest] ->
          {parse_variant(variant_raw), path}

        [path] ->
          {env_variant(), path}

        [] ->
          variant = env_variant()
          {variant, default_out_path(variant)}
      end

    path = BankStatement.write_pdf(out_path, variant)
    IO.puts("Wrote bank statement showcase PDF (#{variant}): #{path}")
  end

  defp env_variant do
    System.get_env("EX_GUTEN_SHOWCASE_VARIANT", "retail")
    |> parse_variant()
  end

  defp default_out_path(:retail_spending), do: "tmp/bank_statement_showcase.pdf"

  defp default_out_path(:joint_fee_interest),
    do: "tmp/bank_statement_joint_fee_interest_showcase.pdf"

  defp parse_variant(raw) when is_binary(raw) do
    case raw do
      "retail" ->
        :retail_spending

      "retail_spending" ->
        :retail_spending

      "joint" ->
        :joint_fee_interest

      "joint_fee_interest" ->
        :joint_fee_interest

      other ->
        raise ArgumentError, "unsupported bank statement showcase variant: #{inspect(other)}"
    end
  end
end

Tincture.RenderBankStatementShowcaseScript.run()
