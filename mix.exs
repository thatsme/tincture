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
        "erlguten (Joe Armstrong)" => "https://github.com/CarlWright/NGerlguten"
      },
      maintainers: ["thatsme"],
      files: ["lib", "priv", "mix.exs", "README.md", "LICENSE", "NOTICE"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
