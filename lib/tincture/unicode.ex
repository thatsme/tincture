defmodule Tincture.Unicode do
  @moduledoc false
  @combining_mark_regex ~r/^\p{M}$/u

  @spec zero_advance_codepoint?(integer()) :: boolean()
  def zero_advance_codepoint?(codepoint) when is_integer(codepoint) do
    variation_selector_codepoint?(codepoint) or join_control_codepoint?(codepoint) or
      combining_mark_codepoint?(codepoint)
  end

  def zero_advance_codepoint?(_codepoint), do: false

  @spec variation_selector_codepoint?(integer()) :: boolean()
  def variation_selector_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0xFE00 and codepoint <= 0xFE0F,
      do: true

  def variation_selector_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0xE0100 and codepoint <= 0xE01EF,
      do: true

  def variation_selector_codepoint?(_codepoint), do: false

  @spec join_control_codepoint?(integer()) :: boolean()
  def join_control_codepoint?(0x200C), do: true
  def join_control_codepoint?(0x200D), do: true
  def join_control_codepoint?(0x2060), do: true
  def join_control_codepoint?(_codepoint), do: false

  @spec combining_mark_codepoint?(integer()) :: boolean()
  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x0300 and codepoint <= 0x036F,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x1AB0 and codepoint <= 0x1AFF,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x1DC0 and codepoint <= 0x1DFF,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0x20D0 and codepoint <= 0x20FF,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0xFE20 and codepoint <= 0xFE2F,
      do: true

  def combining_mark_codepoint?(codepoint)
      when is_integer(codepoint) and codepoint >= 0 and codepoint <= 0x10FFFF do
    try do
      Regex.match?(@combining_mark_regex, <<codepoint::utf8>>)
    rescue
      _ -> false
    end
  end

  def combining_mark_codepoint?(_codepoint), do: false
end
