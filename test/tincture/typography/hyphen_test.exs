defmodule Tincture.Typography.HyphenTest do
  use ExUnit.Case

  alias Tincture.Typography.Hyphen

  test "hyphenate/1 returns upstream-compatible English splits" do
    assert Hyphen.hyphenate("hyphenation") == ["hy", "phena", "tion"]
    assert Hyphen.hyphenate("algorithm") == ["al", "gorithm"]

    assert Hyphen.hyphenate("supercalifragilisticexpialidocious") == [
             "su",
             "per",
             "cal",
             "i",
             "fra",
             "gil",
             "istic",
             "ex",
             "pi",
             "al",
             "ido",
             "cious"
           ]
  end

  test "hyphenate/1 respects known exception entries" do
    assert Hyphen.hyphenate("however") == ["how", "ever"]
  end

  test "hyphenate/1 keeps short words unchanged" do
    assert Hyphen.hyphenate("tree") == ["tree"]
  end

  test "hyphenate/2 supports additional locales loaded from .dic files" do
    assert Hyphen.hyphenate("anker", :da_dk) == ["an", "ker"]

    assert is_list(Hyphen.hyphenate("ananas", :fi_fi))
    assert is_list(Hyphen.hyphenate("ananas", :nb_no))
    assert is_list(Hyphen.hyphenate("ananas", :sv_se))
  end

  test "hyphenate/2 preserves regression corpus samples across .dic locales" do
    assert Hyphen.hyphenate("diagno", :da_dk) == ["di", "ag", "no"]
    assert Hyphen.hyphenate("asiakas", :fi_fi) == ["asia", "kas"]
    assert Hyphen.hyphenate("albuen", :nb_no) == ["al", "bu", "en"]
    assert Hyphen.hyphenate("cyklop", :sv_se) == ["cy", "klop"]
  end

  test "hyphenate/2 preserves known exception corpus parity for :en_gb and :nb_no" do
    assert Hyphen.hyphenate("however", :en_gb) == ["how", "ever"]
    assert Hyphen.hyphenate("manuscript", :en_gb) == ["ma", "nu", "script"]
    assert Hyphen.hyphenate("manuscripts", :en_gb) == ["ma", "nu", "scripts"]
    assert Hyphen.hyphenate("reciprocity", :en_gb) == ["re", "ci", "pro", "city"]
    assert Hyphen.hyphenate("something", :en_gb) == ["some", "thing"]
    assert Hyphen.hyphenate("throughout", :en_gb) == ["through", "out"]
    assert Hyphen.hyphenate("universities", :en_gb) == ["uni", "ver", "sit", "ies"]
    assert Hyphen.hyphenate("university", :en_gb) == ["uni", "ver", "sity"]

    assert Hyphen.hyphenate("andror", :nb_no) == ["and", "ror"]
    assert Hyphen.hyphenate("androren", :nb_no) == ["and", "ro", "ren"]
    assert Hyphen.hyphenate("attende", :nb_no) == ["atten", "de"]
    assert Hyphen.hyphenate("bakover", :nb_no) == ["bak", "over"]
    assert Hyphen.hyphenate("bortafor", :nb_no) == ["borta", "for"]
  end

  test "hyphenate/3 supports left_min and right_min controls" do
    assert Hyphen.hyphenate("hyphenation", :en_gb, left_min: 4) == ["hyphena", "tion"]
    assert Hyphen.hyphenate("hyphenation", :en_gb, right_min: 5) == ["hy", "phenation"]
    assert Hyphen.hyphenate("hyphenation", :en_gb, left_min: 4, right_min: 5) == ["hyphenation"]
  end

  test "hyphenate/3 rejects invalid left_min/right_min values" do
    assert_raise ArgumentError, "left_min must be a positive integer", fn ->
      Hyphen.hyphenate("hyphenation", :en_gb, left_min: 0)
    end

    assert_raise ArgumentError, "right_min must be a positive integer", fn ->
      Hyphen.hyphenate("hyphenation", :en_gb, right_min: -1)
    end
  end
end
