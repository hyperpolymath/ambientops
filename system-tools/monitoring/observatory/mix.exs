# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.MixProject do
  use Mix.Project

  @version "1.2.0"
  @source_url "https://github.com/hyperpolymath/system-observatory"

  def project do
    [
      app: :system_observatory,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Systems Observatory - Observability layer for AmbientOps",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SystemObservatory.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "system_observatory",
      licenses: ["PMPL-1.0-or-later"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.adoc", "ROADMAP.adoc"]
    ]
  end
end
