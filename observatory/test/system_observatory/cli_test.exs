# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.CLITest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias SystemObservatory.CLI
  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator

  setup do
    start_supervised!(Store)
    start_supervised!(Correlator)
    :ok
  end

  describe "main/1 routing" do
    test "routes to status command" do
      output = capture_io(fn -> CLI.main(["status"]) end)
      assert String.contains?(output, "System Observatory Status")
    end

    test "routes to version command" do
      output = capture_io(fn -> CLI.main(["version"]) end)
      assert String.contains?(output, "System Observatory v")
    end

    test "routes to help command" do
      output = capture_io(fn -> CLI.main(["help"]) end)
      assert String.contains?(output, "COMMANDS:")
    end

    test "shows help for empty args" do
      output = capture_io(fn -> CLI.main([]) end)
      assert String.contains?(output, "COMMANDS:")
    end

    test "shows error for unknown command" do
      output = capture_io(:stderr, fn -> CLI.main(["unknown"]) end)
      assert String.contains?(output, "Unknown command")
    end
  end

  describe "status/1" do
    test "shows version and schema" do
      output = capture_io(fn -> CLI.status() end)

      assert String.contains?(output, "Version:")
      assert String.contains?(output, "Schema:")
    end

    test "shows metrics count" do
      :ok = Store.record("cpu", 50)
      :ok = Store.record("memory", 70)

      output = capture_io(fn -> CLI.status() end)

      assert String.contains?(output, "Total metrics:")
    end

    test "shows events count" do
      {:ok, _} = Correlator.record_event(:change, "test", %{})

      output = capture_io(fn -> CLI.status() end)

      assert String.contains?(output, "Total events:")
    end

    test "emphasizes observation-only mode" do
      output = capture_io(fn -> CLI.status() end)

      assert String.contains?(output, "Observation only")
    end
  end

  describe "recommend/1" do
    test "shows recommendations" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")

      output = capture_io(fn -> CLI.recommend() end)

      assert String.contains?(output, "Recommendations")
      assert String.contains?(output, "CPU")
    end

    test "shows no recommendations message when empty" do
      output = capture_io(fn -> CLI.recommend() end)

      assert String.contains?(output, "no recommendations")
    end

    test "supports JSON format" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")

      output = capture_io(fn -> CLI.recommend(format: "json") end)

      assert {:ok, _} = Jason.decode(String.trim(output))
    end

    test "filters by priority" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      :ok = Store.record("disk_usage", 90, %{}, source: "scanner")

      output = capture_io(fn -> CLI.recommend(priority: "critical") end)

      assert String.contains?(output, "Disk")
    end
  end

  describe "query/2" do
    test "shows metrics by name" do
      :ok = Store.record("test_metric", 42, %{}, source: "test")

      output = capture_io(fn -> CLI.query("test_metric") end)

      assert String.contains?(output, "Metrics: test_metric")
      assert String.contains?(output, "42")
    end

    test "shows message when no metrics found" do
      output = capture_io(fn -> CLI.query("nonexistent") end)

      assert String.contains?(output, "No metrics found")
    end

    test "includes source in output" do
      :ok = Store.record("cpu", 50, %{}, source: "node-scanner")

      output = capture_io(fn -> CLI.query("cpu") end)

      assert String.contains?(output, "node-scanner")
    end
  end

  describe "version/0" do
    test "shows version number" do
      output = capture_io(fn -> CLI.version() end)

      assert String.contains?(output, SystemObservatory.version())
    end

    test "emphasizes observation-only philosophy" do
      output = capture_io(fn -> CLI.version() end)

      assert String.contains?(output, "Never modifies")
    end
  end

  describe "help/0" do
    test "lists all commands" do
      output = capture_io(fn -> CLI.help() end)

      assert String.contains?(output, "status")
      assert String.contains?(output, "ingest")
      assert String.contains?(output, "recommend")
      assert String.contains?(output, "query")
      assert String.contains?(output, "version")
    end

    test "shows usage examples" do
      output = capture_io(fn -> CLI.help() end)

      assert String.contains?(output, "EXAMPLES:")
    end

    test "states observation-only philosophy" do
      output = capture_io(fn -> CLI.help() end)

      assert String.contains?(output, "NEVER applies changes")
    end
  end

  describe "ingest/2" do
    test "shows error for non-existent path" do
      output = capture_io(:stderr, fn -> CLI.ingest("/nonexistent/path") end)

      assert String.contains?(output, "not found")
    end
  end
end
