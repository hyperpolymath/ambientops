# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule ServiceAutopsy.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hyperpolymath/ambientops"

  def project do
    [
      app: :service_autopsy,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "AmbientOps Records - post-mortem analysis of crashed systemd services",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ServiceAutopsy.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "service_autopsy",
      licenses: ["PMPL-1.0-or-later"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url
    ]
  end
end
