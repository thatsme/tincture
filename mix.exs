defmodule Tincture.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/thatsme/tincture"

  def project do
    [
      app: :tincture,
      name: "Tincture",
      version: @version,
      description:
        "Native, high-fidelity PDF generation for Elixir, distilled from the heritage of Joe Armstrong.",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        # :underspecs is deliberately omitted. It flags every public spec that is
        # broader than the inferred success typing (e.g. `map()` for an image
        # metadata map), which is noise rather than signal on a library API.
        flags: [:error_handling, :extra_return, :missing_return]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        check: :test
      ]
    ]
  end

  # Test-only fixtures live in test/support so they compile once rather than
  # being required from test_helper.exs, which Elixir 1.19 warns about.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl],
      mod: {Tincture.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
    ]
  end

  # `mix check` runs every gate CI runs, in the same order.
  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "coveralls"
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "erlguten (Joe Armstrong)" => "https://github.com/CarlWright/NGerlguten"
      },
      maintainers: ["thatsme"],
      files: [
        "lib",
        "priv",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "ROADMAP.md",
        "LICENSE",
        "NOTICE"
      ]
    ]
  end

  defp docs do
    [
      main: "Tincture",
      extras: ["README.md", "CHANGELOG.md", "ROADMAP.md", "NOTICE", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      # Mermaid is rendered client-side; ExDoc ships no diagram support itself.
      before_closing_body_tag: &before_closing_body_tag/1,
      groups_for_modules: [
        Layout: [
          Tincture.Layout.Template,
          Tincture.Layout.Box,
          Tincture.Layout.Table
        ],
        Typography: [
          Tincture.Typography,
          Tincture.Typography.RichText,
          Tincture.Typography.Hyphen
        ],
        # The font layer is public because a caller may legitimately want to
        # inspect a font without generating a PDF, and because each module
        # documents one on-disk format.
        "Font formats": [
          Tincture.Font.Binary,
          Tincture.Font.CFF,
          Tincture.Font.TTF,
          Tincture.Font.TTF.Cmap,
          Tincture.Font.TTF.Glyf,
          Tincture.Font.TTF.Name,
          Tincture.Font.UnicodeRanges,
          Tincture.Font.OpenType.Common,
          Tincture.Font.OpenType.GPOS,
          Tincture.Font.OpenType.GSUB
        ],
        "PDF internals": [
          Tincture.PDF,
          Tincture.PDF.Object,
          Tincture.PDF.Serialize,
          Tincture.PDF.FontEmbed
        ]
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        for (const pre of document.querySelectorAll("pre code.mermaid")) {
          const div = document.createElement("div");
          div.className = "mermaid";
          div.textContent = pre.textContent;
          pre.parentNode.replaceWith(div);
        }

        mermaid.initialize({startOnLoad: true});
      });
    </script>
    """
  end

  defp before_closing_body_tag(_format), do: ""
end
