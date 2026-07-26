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
      deps: deps()
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
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
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
