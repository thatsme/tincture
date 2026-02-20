defmodule ExGuten.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ex_guten,
      name: "ExGuten",
      version: @version,
      description: "Typographic-quality PDF generation for Elixir",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/hwatkins/ex_guten",
      homepage_url: "https://github.com/hwatkins/ex_guten",
      docs: docs(),
      package: package(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl],
      mod: {ExGuten.Application, []}
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
      links: %{"GitHub" => "https://github.com/hwatkins/ex_guten"},
      maintainers: ["hwatkins"],
      files: ["lib", "priv", "mix.exs", "README.MD", "LICENSE"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.MD"],
      source_ref: "v#{@version}",
      source_url: "https://github.com/hwatkins/ex_guten"
    ]
  end
end
