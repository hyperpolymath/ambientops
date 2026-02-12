# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule AmbientOps.Records.Referrals.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/hyperpolymath/ambientops"

  def project do
    [
      app: :ambientops_referrals,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      releases: releases(),

      # Docs
      name: "AmbientOps Referrals",
      description: "AmbientOps Records - automated multi-platform bug reporting with network verification",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :inets],
      mod: {FeedbackATron.Application, []}
    ]
  end

  defp deps do
    [
      # MCP server framework
      {:elixir_mcp_server, "~> 0.1.0"},

      # HTTP client
      {:req, "~> 0.5"},

      # JSON
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9"},

      # CLI argument parsing
      {:optimus, "~> 0.5"},

      # Terminal UI
      {:owl, "~> 0.11"},

      # Config file parsing
      {:toml, "~> 0.7"},

      # Fuzzy string matching for deduplication
      {:the_fuzz, "~> 0.6"},

      # For testing
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [
      main_module: FeedbackATron.CLI,
      name: "ambientops-referrals"
    ]
  end

  defp releases do
    [
      ambientops_referrals: [
        steps: [:assemble, :tar]
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
