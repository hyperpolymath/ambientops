# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule NetworkDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :network_dashboard,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "NetworkDashboard",
      description: "FlatRacoon network module status dashboard"
    ]
  end

  def application do
    [
      mod: {NetworkDashboard.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:bandit, "~> 1.5"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "assets.deploy": ["phx.digest"]
    ]
  end
end
