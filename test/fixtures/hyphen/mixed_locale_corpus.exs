[
  %{
    text: "anker hyphenation albuen",
    width: 24,
    opts: [],
    locale_by_word: %{"anker" => :da_dk, "albuen" => :nb_no},
    expected: ["an-", "ker", "hy-", "phena-", "tion", "al-", "bu-", "en"]
  },
  %{
    text: "cyklop asiakas hyphenation",
    width: 24,
    opts: [],
    locale_by_word: %{"cyklop" => :sv_se, "asiakas" => :fi_fi},
    expected: ["cy-", "klop", "asia-", "kas", "hy-", "phena-", "tion"]
  },
  %{
    text: "anker hyphenation albuen",
    width: 30,
    opts: [hyphen_left_min: 3, hyphen_right_min: 3],
    locale_by_word: %{"anker" => :da_dk, "albuen" => :nb_no},
    expected: ["anker", "hyphena-", "tion", "albue", "n"]
  },
  %{
    text: "anker cyklop asiakas",
    width: 24,
    opts: [hyphen_left_min: 3, hyphen_right_min: 3],
    locale_by_word: %{"anker" => :da_dk, "cyklop" => :sv_se, "asiakas" => :fi_fi},
    expected: ["anke", "r", "cykl", "op", "asia-", "kas"]
  }
]
