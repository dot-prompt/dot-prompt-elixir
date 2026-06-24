defmodule DotPrompt.MixProject do
  use Mix.Project

  def project do
    [
      app: :dot_prompt,
      version: "1.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: "A high-performance, native Elixir compiler for the DotPrompt language.",
      package: package(),
      docs: docs(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :telemetry],
      mod: {DotPrompt.Application, []}
    ]
  end

  defp package do
    [
      name: :dot_prompt,
      maintainers: ["DotPrompt Team"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/dot-prompt/dot-prompt-elixir"},
      files: ~w(lib mix.exs README.md CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "DotPrompt",
      extras: ["README.md"]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:req, "~> 0.5"},
      {:telemetry_test, only: :test},
      {:file_system, "~> 0.2"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
    ]
  end
end
