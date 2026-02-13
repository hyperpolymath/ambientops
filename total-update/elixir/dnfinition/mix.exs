# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://gitlab.com/hyperpolymath/dnfinition"

  def project do
    [
      app: :dnfinition,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),

      # OTP application configuration
      mod: {DNFinition.Application, []},

      # Dialyzer for static analysis
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {DNFinition.Application, []}
    ]
  end

  defp deps do
    [
      # Port/NIF for Ada integration
      {:porcelain, "~> 2.0"},

      # Configuration
      {:toml, "~> 0.7"},

      # Telemetry for observability
      {:telemetry, "~> 1.2"},

      # Development and testing
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    DNFinition - Universal Package Manager TUI with Reversibility.
    Elixir OTP coordinator for Ada TUI process.
    """
  end

  defp package do
    [
      name: "dnfinition",
      licenses: ["AGPL-3.0-or-later"],
      links: %{
        "GitLab" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
