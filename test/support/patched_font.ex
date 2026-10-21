defmodule Tincture.Test.PatchedFont do
  @moduledoc """
  A copy of the vendored Liberation Sans with its OS/2 table's `version`
  (offset 0) and `fsType` (offset 8) overwritten, for testing how an embedding
  permission is read.

  The OS/2 table is found through the table directory: 12 bytes of header,
  then 16-byte records of tag, checksum, offset and length. The checksums are
  not updated; Tincture does not verify them.
  """

  @vendored "examples/fonts/LiberationSans-Regular.ttf"

  @doc "Write the patched font to a temporary file and return its path."
  @spec write!(non_neg_integer(), non_neg_integer()) :: Path.t()
  def write!(version, fs_type) do
    path =
      Path.join(System.tmp_dir!(), "tincture_patched_#{System.unique_integer([:positive])}.ttf")

    File.write!(path, binary(version, fs_type))
    path
  end

  @doc "The patched font as a binary."
  @spec binary(non_neg_integer(), non_neg_integer()) :: binary()
  def binary(version, fs_type) do
    data = File.read!(@vendored)
    <<_sfnt::32, num_tables::16, _rest::binary>> = data

    offset =
      Enum.find_value(0..(num_tables - 1), fn index ->
        case binary_part(data, 12 + index * 16, 16) do
          <<"OS/2", _checksum::32, offset::32, _length::32>> -> offset
          _other -> nil
        end
      end)

    <<head::binary-size(offset), _version::16, middle::binary-size(6), _fs_type::16,
      tail::binary>> = data

    <<head::binary, version::16, middle::binary, fs_type::16, tail::binary>>
  end
end
