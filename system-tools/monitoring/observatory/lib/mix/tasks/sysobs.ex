# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Mix.Tasks.Sysobs do
  @moduledoc """
  Mix task for System Observatory CLI.

  ## Usage

      mix sysobs status
      mix sysobs ingest /path/to/run-bundle/
      mix sysobs recommend
      mix sysobs query <metric> [--since <duration>]
      mix sysobs version
      mix sysobs help

  See `SystemObservatory.CLI` for detailed documentation.
  """

  use Mix.Task

  @shortdoc "System Observatory CLI"

  @impl Mix.Task
  def run(args) do
    # Start the application to ensure GenServers are running
    {:ok, _} = Application.ensure_all_started(:system_observatory)

    SystemObservatory.CLI.main(args)
  end
end
