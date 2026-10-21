defmodule Tincture.Font.EmbeddingPermission do
  @moduledoc false

  # The usage permission a font's OS/2 fsType grants, read as OpenType 1.9.1's
  # OS/2 chapter defines it. Bits 0-3 are the permission sub-field: bit 0 is
  # permanently reserved, and bits 1, 2 and 3 are Restricted License, Preview &
  # Print and Editable; none of them set is Installable.
  #
  # Restricted License "takes effect" only when the sub-field is exactly 2.
  # Versions 0 to 2 of the OS/2 table did not make the bits mutually
  # exclusive, and stated that when several are set the least restrictive
  # takes precedence, which applications may still apply to those versions.
  # From version 3 the bits must be mutually exclusive; a font that sets
  # several anyway is malformed, and for a licence check the conservative
  # reading is the most restrictive bit it sets.
  #
  # Every reading of the permission in Tincture goes through this module, so
  # there is one interpretation of fsType.

  import Bitwise

  @type t :: :installable | :restricted | :preview_and_print | :editable

  @restricted 0x0002
  @preview_and_print 0x0004
  @editable 0x0008

  @doc """
  The permission for an `fsType` value and the OS/2 table version it came
  from. A `nil` version is read as version 3 or later, the stricter rule.
  """
  @spec permission(non_neg_integer(), non_neg_integer() | nil) :: t()
  def permission(fs_type, os2_version) when is_integer(fs_type) and fs_type >= 0 do
    set =
      Enum.filter([@restricted, @preview_and_print, @editable], &(band(fs_type, &1) != 0))

    case set do
      [] -> :installable
      [bit] -> name(bit)
      several -> several |> pick(os2_version) |> name()
    end
  end

  defp pick(bits, version) when is_integer(version) and version <= 2, do: Enum.max(bits)
  defp pick(bits, _version), do: Enum.min(bits)

  defp name(@restricted), do: :restricted
  defp name(@preview_and_print), do: :preview_and_print
  defp name(@editable), do: :editable
end
