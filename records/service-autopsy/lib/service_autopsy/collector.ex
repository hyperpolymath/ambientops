# SPDX-License-Identifier: MPL-2.0

defmodule ServiceAutopsy.Collector do
  @moduledoc """
  Collects crash context for a failed systemd service.

  Gathers:
  - Journal entries (last 50 lines from the unit)
  - Coredump information (via coredumpctl)
  - D-Bus service state (via busctl)
  - Dependency graph (via systemctl list-dependencies)
  - Unit file contents
  - Service status at time of failure

  Produces a structured autopsy report conforming to
  evidence-envelope.schema.json.

  ## Author

  Jonathan D.A. Jewell
  """

  require Logger

  @source "psa"
  @journal_lines 50
  @envelope_version "1.0.0"

  @doc """
  Collect all available crash context for a systemd unit.

  Returns an evidence-envelope conformant map.
  """
  @spec collect(String.t()) :: {:ok, map()} | {:error, term()}
  def collect(unit_name) do
    envelope_id = generate_envelope_id()
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Collect all context in parallel via Task.async
    tasks = %{
      journal: Task.async(fn -> collect_journal(unit_name) end),
      status: Task.async(fn -> collect_status(unit_name) end),
      coredump: Task.async(fn -> collect_coredump(unit_name) end),
      deps: Task.async(fn -> collect_dependencies(unit_name) end),
      unit_file: Task.async(fn -> collect_unit_file(unit_name) end),
      dbus: Task.async(fn -> collect_dbus_state(unit_name) end)
    }

    # Await all with a 10-second timeout per task
    results =
      tasks
      |> Enum.map(fn {key, task} ->
        result = Task.await(task, 10_000)
        {key, result}
      end)
      |> Map.new()

    # Build the evidence envelope
    artifacts = build_artifacts(results, unit_name)
    findings = build_findings(results, unit_name)

    envelope = %{
      "version" => @envelope_version,
      "envelope_id" => envelope_id,
      "created_at" => timestamp,
      "source" => %{
        "tool" => @source,
        "host" => %{
          "hostname" => hostname()
        }
      },
      "subject" => %{
        "type" => "systemd_unit",
        "name" => unit_name
      },
      "artifacts" => artifacts,
      "findings" => findings,
      "context" => %{
        "journal_lines" => results[:journal],
        "service_status" => results[:status],
        "coredump_info" => results[:coredump],
        "dependency_graph" => results[:deps],
        "unit_file" => results[:unit_file],
        "dbus_state" => results[:dbus]
      }
    }

    {:ok, envelope}
  rescue
    e ->
      Logger.error("#{@source}: collection failed for #{unit_name}: #{Exception.message(e)}")
      {:error, {:collection_failed, Exception.message(e)}}
  end

  # --- Individual Collectors ---

  @doc false
  def collect_journal(unit_name) do
    args = [
      "--unit=#{unit_name}",
      "--no-pager",
      "--lines=#{@journal_lines}",
      "--output=short-iso"
    ]

    case System.cmd("journalctl", args, stderr_to_stdout: true) do
      {output, _code} ->
        output
        |> String.split("\n", trim: true)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc false
  def collect_status(unit_name) do
    case System.cmd("systemctl", ["status", unit_name, "--no-pager"], stderr_to_stdout: true) do
      {output, _code} ->
        parse_status_output(output)

      _ ->
        %{"error" => "systemctl not available"}
    end
  rescue
    _ -> %{"error" => "systemctl command failed"}
  end

  @doc false
  def collect_coredump(unit_name) do
    # Extract service name without .service suffix for coredumpctl
    service_name = String.replace_suffix(unit_name, ".service", "")

    case System.cmd("coredumpctl", ["list", "--no-pager", service_name], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.take(10)

      {_output, _code} ->
        []
    end
  rescue
    _ -> []
  end

  @doc false
  def collect_dependencies(unit_name) do
    case System.cmd("systemctl", ["list-dependencies", unit_name, "--no-pager", "--plain"],
           stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc false
  def collect_unit_file(unit_name) do
    case System.cmd("systemctl", ["cat", unit_name, "--no-pager"], stderr_to_stdout: true) do
      {output, 0} -> output
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc false
  def collect_dbus_state(unit_name) do
    # Check if the service has a D-Bus name registered
    service_name = String.replace_suffix(unit_name, ".service", "")

    case System.cmd("busctl", ["--no-pager", "list"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.contains?(&1, service_name))
        |> Enum.take(5)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  # --- Report Building ---

  defp build_artifacts(results, unit_name) do
    artifacts = []

    artifacts =
      if results[:journal] != [] do
        [%{
          "artifact_id" => generate_artifact_id(),
          "type" => "log",
          "path" => "journal/#{unit_name}.log",
          "label" => "Journal entries for #{unit_name}",
          "line_count" => length(results[:journal] || [])
        } | artifacts]
      else
        artifacts
      end

    artifacts =
      if results[:coredump] != [] do
        [%{
          "artifact_id" => generate_artifact_id(),
          "type" => "report",
          "path" => "coredumps/#{unit_name}.report",
          "label" => "Coredumps for #{unit_name}",
          "entry_count" => length(results[:coredump] || [])
        } | artifacts]
      else
        artifacts
      end

    artifacts =
      if results[:unit_file] != nil do
        [%{
          "artifact_id" => generate_artifact_id(),
          "type" => "config",
          "path" => "units/#{unit_name}",
          "label" => "Unit file for #{unit_name}"
        } | artifacts]
      else
        artifacts
      end

    artifacts
  end

  defp build_findings(results, unit_name) do
    findings = []

    # Check if service is in failed state
    status = results[:status] || %{}
    active_state = Map.get(status, "ActiveState", "unknown")

    findings =
      if active_state == "failed" do
        [%{
          "finding_id" => generate_artifact_id(),
          "severity" => "high",
          "category" => "service_failure",
          "title" => "#{unit_name} is in failed state",
          "description" => "Service #{unit_name} has entered the failed state. " <>
            "Exit code: #{Map.get(status, "ExecMainStatus", "unknown")}",
          "auto_fixable" => false
        } | findings]
      else
        findings
      end

    # Check for coredumps
    findings =
      if length(results[:coredump] || []) > 0 do
        [%{
          "finding_id" => generate_artifact_id(),
          "severity" => "high",
          "category" => "crash",
          "title" => "Coredump(s) found for #{unit_name}",
          "description" => "#{length(results[:coredump])} coredump entries found",
          "auto_fixable" => false
        } | findings]
      else
        findings
      end

    findings
  end

  # --- Status Parsing ---

  defp parse_status_output(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.reduce(lines, %{}, fn line, acc ->
      cond do
        String.contains?(line, "Active:") ->
          state = extract_active_state(line)
          Map.put(acc, "ActiveState", state)

        String.contains?(line, "Main PID:") ->
          case Regex.run(~r/Main PID:\s*(\d+)/, line) do
            [_, pid] -> Map.put(acc, "MainPID", pid)
            _ -> acc
          end

        String.contains?(line, "Status:") ->
          status = String.trim(line) |> String.replace_prefix("Status: ", "")
          Map.put(acc, "StatusText", status)

        true ->
          acc
      end
    end)
  end

  defp extract_active_state(line) do
    cond do
      String.contains?(line, "failed") -> "failed"
      String.contains?(line, "active (running)") -> "active"
      String.contains?(line, "inactive") -> "inactive"
      String.contains?(line, "activating") -> "activating"
      true -> "unknown"
    end
  end

  # --- Helpers ---

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "unknown"
    end
  end

  defp generate_envelope_id do
    generate_uuid()
  end

  defp generate_artifact_id do
    generate_uuid()
  end

  # Generate a RFC 4122 v4 UUID from random bytes.
  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid_hex()
  end

  defp format_uuid_hex(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>) do
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end
end
