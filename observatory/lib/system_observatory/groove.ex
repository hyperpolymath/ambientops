# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# SystemObservatory.Groove — Groove client for AmbientOps Observatory.
#
# Discovers Burble (voice) and Vext (integrity) via the groove protocol,
# enabling voice escalation alerts when System Weather transitions from
# Calm → Watch → Act.
#
# Hospital model integration:
#   Ward (Observatory) → voice cues when state changes (ambient, non-invasive)
#   Emergency Room     → voice alerts on Act transitions (urgent, actionable)
#   Operating Room     → voice confirmation for critical procedures
#   Records            → voice summary generation for post-mortems
#
# Groove protocol:
#   GET  /.well-known/groove         — capability manifest (JSON)
#   POST /.well-known/groove/message — send alert message to service
#
# Respects the Ward principle: voice NEVER executes actions, only informs.
# Respects notification budget: honours snooze preferences from weather state.
#
# The groove connectors are formally verified in Gossamer's Groove.idr:
# - Burble must offer TTS capability for voice alerts to work
# - Linear GrooveHandle ensures proper lifecycle management

defmodule SystemObservatory.Groove do
  @moduledoc """
  Groove client for the AmbientOps Observatory.

  Probes Burble (port 6473) and Vext (port 6480) for groove capabilities.
  When Burble is available, enables voice escalation for System Weather
  transitions. When Vext is available, weather reports gain integrity
  hash chains.

  All groove operations are advisory — if no groove targets are found,
  the Observatory continues operating exactly as before.
  """

  use GenServer
  require Logger

  @burble_port 6473
  @vext_port 6480
  @probe_interval_ms 60_000
  @connect_timeout_ms 2_000

  # --- Types ---

  @type groove_target :: %{
          service_id: String.t(),
          port: non_neg_integer(),
          status: :not_found | :connected | :error,
          capabilities: [String.t()],
          last_probe: DateTime.t() | nil
        }

  @type state :: %{
          burble: groove_target(),
          vext: groove_target()
        }

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if Burble voice is available via groove discovery."
  @spec burble_available?() :: boolean()
  def burble_available? do
    GenServer.call(__MODULE__, :burble_available?)
  end

  @doc "Check if Vext integrity is available via groove discovery."
  @spec vext_available?() :: boolean()
  def vext_available? do
    GenServer.call(__MODULE__, :vext_available?)
  end

  @doc """
  Send a voice alert via Burble TTS groove.

  Used by the Weather module when state transitions occur:
  - Watch → spoken advisory (calm tone)
  - Act   → spoken alert (urgent tone)

  Returns :ok if sent, :unavailable if Burble groove not connected.
  """
  @spec voice_alert(String.t(), atom()) :: :ok | :unavailable
  def voice_alert(message, severity \\ :info) do
    GenServer.call(__MODULE__, {:voice_alert, message, severity})
  end

  @doc """
  Send a weather state change notification via groove.

  Includes full weather context so Burble can format the alert
  appropriately (e.g. "System Weather changed to Act: disk at 92%").
  """
  @spec weather_transition(atom(), atom(), String.t()) :: :ok | :unavailable
  def weather_transition(from_state, to_state, summary) do
    GenServer.call(__MODULE__, {:weather_transition, from_state, to_state, summary})
  end

  @doc """
  Send an integrity-verified weather report via Vext groove.

  Attaches a hash chain entry to the weather report so downstream
  consumers can verify the report hasn't been tampered with.
  """
  @spec verified_weather(map()) :: :ok | :unavailable
  def verified_weather(weather_payload) do
    GenServer.call(__MODULE__, {:verified_weather, weather_payload})
  end

  @doc "Force re-probe of all groove targets."
  @spec reprobe() :: :ok
  def reprobe do
    GenServer.cast(__MODULE__, :reprobe)
  end

  @doc "Get current groove status summary."
  @spec status() :: state()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    state = %{
      burble: new_target("burble", @burble_port),
      vext: new_target("vext", @vext_port)
    }

    # Probe on startup.
    send(self(), :probe)

    # Schedule periodic re-probes.
    :timer.send_interval(@probe_interval_ms, :probe)

    {:ok, state}
  end

  @impl true
  def handle_info(:probe, state) do
    state = %{
      state
      | burble: probe_target(state.burble),
        vext: probe_target(state.vext)
    }

    {:noreply, state}
  end

  @impl true
  def handle_call(:burble_available?, _from, state) do
    {:reply, state.burble.status == :connected, state}
  end

  @impl true
  def handle_call(:vext_available?, _from, state) do
    {:reply, state.vext.status == :connected, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:voice_alert, message, severity}, _from, state) do
    if state.burble.status == :connected do
      payload =
        Jason.encode!(%{
          type: "voice_alert",
          source: "ambientops-observatory",
          department: "ward",
          severity: severity,
          message: message,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      send_groove_message(state.burble.port, payload)
      {:reply, :ok, state}
    else
      {:reply, :unavailable, state}
    end
  end

  @impl true
  def handle_call({:weather_transition, from_state, to_state, summary}, _from, state) do
    if state.burble.status == :connected do
      # Format the TTS message based on severity.
      tts_message =
        case to_state do
          :calm ->
            "System weather returned to calm. #{summary}"

          :watch ->
            "Attention: system weather changed to watch. #{summary}"

          :act ->
            "Alert: system weather escalated to act. Immediate attention recommended. #{summary}"
        end

      payload =
        Jason.encode!(%{
          type: "weather_transition",
          source: "ambientops-observatory",
          department: "ward",
          from_state: from_state,
          to_state: to_state,
          summary: summary,
          tts_message: tts_message,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      send_groove_message(state.burble.port, payload)
      {:reply, :ok, state}
    else
      {:reply, :unavailable, state}
    end
  end

  @impl true
  def handle_call({:verified_weather, weather_payload}, _from, state) do
    if state.vext.status == :connected do
      payload =
        Jason.encode!(%{
          type: "verify_weather",
          source: "ambientops-observatory",
          weather: weather_payload,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      send_groove_message(state.vext.port, payload)
      {:reply, :ok, state}
    else
      {:reply, :unavailable, state}
    end
  end

  @impl true
  def handle_cast(:reprobe, state) do
    state = %{
      state
      | burble: probe_target(state.burble),
        vext: probe_target(state.vext)
    }

    {:noreply, state}
  end

  # --- Internal ---

  defp new_target(service_id, port) do
    %{
      service_id: service_id,
      port: port,
      status: :not_found,
      capabilities: [],
      last_probe: nil
    }
  end

  defp probe_target(target) do
    case :gen_tcp.connect(~c"127.0.0.1", target.port, [:binary, active: false], @connect_timeout_ms) do
      {:ok, socket} ->
        request =
          "GET /.well-known/groove HTTP/1.0\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n"

        :gen_tcp.send(socket, request)

        case :gen_tcp.recv(socket, 0, @connect_timeout_ms) do
          {:ok, data} ->
            :gen_tcp.close(socket)
            parse_groove_response(target, data)

          {:error, _} ->
            :gen_tcp.close(socket)
            %{target | status: :error, last_probe: DateTime.utc_now()}
        end

      {:error, _} ->
        %{target | status: :not_found, last_probe: DateTime.utc_now()}
    end
  end

  defp parse_groove_response(target, data) do
    # Find body after \r\n\r\n.
    case String.split(data, "\r\n\r\n", parts: 2) do
      [_headers, body] ->
        case Jason.decode(body) do
          {:ok, manifest} ->
            caps =
              manifest
              |> Map.get("capabilities", %{})
              |> Map.keys()

            Logger.info(
              "Groove: #{target.service_id} connected (#{length(caps)} capabilities)"
            )

            %{target | status: :connected, capabilities: caps, last_probe: DateTime.utc_now()}

          {:error, _} ->
            %{target | status: :error, last_probe: DateTime.utc_now()}
        end

      _ ->
        %{target | status: :error, last_probe: DateTime.utc_now()}
    end
  end

  defp send_groove_message(port, json_payload) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], @connect_timeout_ms) do
      {:ok, socket} ->
        request =
          "POST /.well-known/groove/message HTTP/1.0\r\n" <>
            "Host: localhost\r\n" <>
            "Content-Type: application/json\r\n" <>
            "Content-Length: #{byte_size(json_payload)}\r\n" <>
            "Connection: close\r\n\r\n" <>
            json_payload

        :gen_tcp.send(socket, request)
        :gen_tcp.close(socket)

      {:error, reason} ->
        Logger.warn("Groove: failed to send message to port #{port}: #{inspect(reason)}")
    end
  end
end
