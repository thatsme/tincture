defmodule Tincture.Font.EmbeddingPermissionTest do
  @moduledoc """
  The usage permission in a font's OS/2 `fsType`, read as OpenType 1.9.1's
  OS/2 chapter defines it: Restricted License takes effect only when the
  permission sub-field is exactly 2; a version 0-2 table may combine bits,
  and the least restrictive then applies; from version 3 the bits are
  mutually exclusive.

  Registration reads the permission the same way. Before, it flagged any
  font with bit 1 set, so a version 0-2 font combining bits 1 and 3 was
  reported as Restricted License although it is Editable.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tincture.Font.EmbeddingPermission

  @vendored "examples/fonts/LiberationSans-Regular.ttf"

  describe "permission/2" do
    test "one bit, or none, in any version" do
      for version <- [0, 2, 3, 4, nil] do
        assert EmbeddingPermission.permission(0, version) == :installable
        assert EmbeddingPermission.permission(2, version) == :restricted
        assert EmbeddingPermission.permission(4, version) == :preview_and_print
        assert EmbeddingPermission.permission(8, version) == :editable
      end
    end

    test "bit 0 is reserved and ignored, and bits 8 and 9 do not change the permission" do
      assert EmbeddingPermission.permission(1, 3) == :installable
      assert EmbeddingPermission.permission(0x0100, 3) == :installable
      assert EmbeddingPermission.permission(0x0200 + 8, 3) == :editable
      assert EmbeddingPermission.permission(0x0100 + 4, 2) == :preview_and_print
    end

    test "versions 0 to 2: several bits give the least restrictive" do
      for version <- [0, 1, 2] do
        assert EmbeddingPermission.permission(10, version) == :editable
        assert EmbeddingPermission.permission(6, version) == :preview_and_print
        assert EmbeddingPermission.permission(12, version) == :editable
        assert EmbeddingPermission.permission(14, version) == :editable
      end
    end

    test "version 3 and later, or unknown: several bits give the most restrictive" do
      for version <- [3, 4, 5, nil] do
        assert EmbeddingPermission.permission(10, version) == :restricted
        assert EmbeddingPermission.permission(6, version) == :restricted
        assert EmbeddingPermission.permission(12, version) == :preview_and_print
      end
    end
  end

  # A copy of the vendored Liberation Sans with its OS/2 table's version
  # (offset 0) and fsType (offset 8) overwritten. The table is found through
  # the table directory: 12 bytes of header, then 16-byte records of tag,
  # checksum, offset and length. The checksums are not updated; Tincture does
  # not verify them.
  defp patched_font(version, fs_type) do
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

    patched = <<head::binary, version::16, middle::binary, fs_type::16, tail::binary>>

    path =
      Path.join(
        System.tmp_dir!(),
        "tincture_permission_#{System.unique_integer([:positive])}.ttf"
      )

    File.write!(path, patched)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp register(path, opts \\ []),
    do: Tincture.register_ttf_font(Tincture.new(), "Sans", path, opts)

  describe "registration reads the permission, not bit 1" do
    test "the patched copy reads back as patched" do
      pdf = register(patched_font(2, 10))
      metrics = pdf.embedded_fonts["Sans"].ttf_metrics

      assert metrics.os2_version == 2
      assert metrics.os2_fs_type == 10
    end

    # The logger is global and these tests are async, so a capture may hold
    # other tests' warnings too; only the lines naming this font's file count.
    defp warnings_about(path) do
      capture_log(fn -> register(path) end)
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, path))
    end

    test "a version-2 font with fsType 10 (Editable) neither warns nor is refused" do
      path = patched_font(2, 10)

      assert warnings_about(path) == []
      assert %Tincture.PDF{} = register(path, enforce_embedding_permissions: true)
    end

    test "a version-2 font with fsType 6 (Preview & Print) neither warns nor is refused" do
      path = patched_font(2, 6)

      assert warnings_about(path) == []
      assert %Tincture.PDF{} = register(path, enforce_embedding_permissions: true)
    end

    test "fsType 2 still warns, and is refused under enforce_embedding_permissions" do
      path = patched_font(2, 2)

      assert [warning] = warnings_about(path)
      assert warning =~ "restrictive OS/2 fsType (2)"

      assert_raise ArgumentError, ~r/restricted by OS\/2 fsType \(2\)/, fn ->
        register(path, enforce_embedding_permissions: true)
      end
    end

    test "a version-3 font with fsType 10 is read as Restricted License" do
      path = patched_font(3, 10)

      assert [warning] = warnings_about(path)
      assert warning =~ "restrictive OS/2 fsType (10)"
    end
  end
end
