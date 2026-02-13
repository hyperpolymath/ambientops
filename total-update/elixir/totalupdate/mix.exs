# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://gitlab.com/hyperpolymath/totalupdate"

  def project do
    [
      app: :totalupdate,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),

      # OTP application configuration
      mod: {TotalUpdate.Application, []},

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl],
      mod: {TotalUpdate.Application, []}
    ]
  end

  defp deps do
    [
      # DNFinition for package operations
      {:dnfinition, path: "../dnfinition"},

      # HTTP client for update checks
      {:finch, "~> 0.18"},

      # Configuration
      {:toml, "~> 0.7"},

      # Scheduling
      {:quantum, "~> 3.5"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Development
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    TotalUpdate - Universal Package Update Daemon.
    Automated background updates for all package managers with safety guarantees.
    """
  end

  defp package do
    [
      name: "totalupdate",
      licenses: ["AGPL-3.0-or-later"],
      links: %{"GitLab" => @source_url}
    ]
  end
end
