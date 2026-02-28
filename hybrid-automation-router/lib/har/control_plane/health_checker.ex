defmodule HAR.ControlPlane.HealthChecker do
  @moduledoc """
  Health checker for routing backends.

  Monitors backend health status and provides filtering for routing decisions.
  Supports multiple health check strategies:
  - HTTP health endpoints
  - TCP connectivity
  - Custom health functions
  """

  use GenServer
  require Logger

  alias HAR.ControlPlane.CircuitBreaker

  @type backend :: map()
  @type health_status :: :healthy | :unhealthy | :degraded | :unknown

  @default_check_interval 30_000
  @default_timeout 5_000

  defstruct [
    :check_interval,
    :timeout,
    backend_health: %{},
    registered_backends: %{},
    last_check: nil
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a backend is healthy.
  """
  @spec healthy?(backend()) :: boolean()
  def healthy?(backend) do
    case get_health(backend) do
      :healthy -> true
      :degraded -> true
      _ -> false
    end
  end

  @doc """
  Get the health status of a backend.
  """
  @spec get_health(backend()) :: health_status()
  def get_health(backend) do
    backend_id = backend_identifier(backend)

    try do
      GenServer.call(__MODULE__, {:get_health, backend_id})
    catch
      :exit, _ -> :unknown
    end
  end

  @doc """
  Filter a list of backends to only healthy ones.
  """
  @spec filter_healthy([backend()]) :: [backend()]
  def filter_healthy(backends) when is_list(backends) do
    Enum.filter(backends, &healthy?/1)
  end

  @doc """
  Register a backend for health monitoring.
  """
  @spec register_backend(backend()) :: :ok
  def register_backend(backend) do
    GenServer.cast(__MODULE__, {:register, backend})
  end

  @doc """
  Manually set health status (useful for testing or admin overrides).
  """
  @spec set_health(backend(), health_status()) :: :ok
  def set_health(backend, status) do
    GenServer.cast(__MODULE__, {:set_health, backend_identifier(backend), status})
  end

  @doc """
  Force an immediate health check on a backend.
  """
  @spec check_now(backend()) :: health_status()
  def check_now(backend) do
    GenServer.call(__MODULE__, {:check_now, backend})
  end

  @doc """
  Get health status for all registered backends.
  """
  @spec all_health() :: %{String.t() => health_status()}
  def all_health do
    try do
      GenServer.call(__MODULE__, :all_health)
    catch
      :exit, _ -> %{}
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    state = %__MODULE__{
      check_interval: check_interval,
      timeout: timeout,
      backend_health: %{},
      last_check: DateTime.utc_now()
    }

    # Schedule periodic health checks
    if check_interval > 0 do
      schedule_health_check(check_interval)
    end

    Logger.info("HealthChecker started with #{check_interval}ms interval")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_health, backend_id}, _from, state) do
    status = Map.get(state.backend_health, backend_id, :unknown)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:all_health, _from, state) do
    {:reply, state.backend_health, state}
  end

  @impl true
  def handle_call({:check_now, backend}, _from, state) do
    status = perform_health_check(backend, state.timeout)
    backend_id = backend_identifier(backend)

    new_health = Map.put(state.backend_health, backend_id, status)
    new_state = %{state | backend_health: new_health}

    {:reply, status, new_state}
  end

  @impl true
  def handle_cast({:register, backend}, state) do
    backend_id = backend_identifier(backend)

    # Store the full backend config so periodic health checks can use
    # the configured health_check strategy (HTTP/TCP/function).
    registered = Map.get(state, :registered_backends, %{})
    new_registered = Map.put(registered, backend_id, backend)

    if not Map.has_key?(state.backend_health, backend_id) do
      # Initial status is unknown, will be updated on next check
      new_health = Map.put(state.backend_health, backend_id, :unknown)
      {:noreply, %{state | backend_health: new_health, registered_backends: new_registered}}
    else
      {:noreply, Map.put(state, :registered_backends, new_registered)}
    end
  end

  @impl true
  def handle_cast({:set_health, backend_id, status}, state) do
    new_health = Map.put(state.backend_health, backend_id, status)
    {:noreply, %{state | backend_health: new_health}}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform actual health checks on all registered backends.
    #
    # Each backend is checked using its configured health_check strategy
    # (HTTP, TCP, or custom function). Checks run sequentially to avoid
    # overwhelming backends with concurrent probes. For large backend
    # pools (100+), consider Task.async_stream with max_concurrency.
    #
    # Previous status is preserved as fallback if the check raises an
    # unexpected error, preventing a single flaky backend from crashing
    # the entire health check cycle.
    #
    # Health check results are also fed into the CircuitBreaker so that
    # backend failures detected during periodic probes contribute to the
    # circuit breaker's consecutive failure counter, and successes allow
    # half-open circuits to close.
    new_health =
      Enum.reduce(state.backend_health, %{}, fn {backend_id, old_status}, acc ->
        status =
          case Map.get(state, :registered_backends, %{}) |> Map.get(backend_id) do
            nil ->
              # Backend registered by ID only (no config) — preserve old status
              # or mark as unknown if never checked
              if old_status == :unknown, do: :unknown, else: old_status

            backend ->
              try do
                perform_health_check(backend, state.timeout)
              rescue
                _ ->
                  Logger.warning("Health check failed for #{backend_id}, preserving old status")
                  old_status
              end
          end

        # Feed health check result into the circuit breaker so that periodic
        # probe outcomes (not just routing outcomes) drive circuit state
        # transitions. A backend that fails health checks will eventually
        # trip its circuit open even if no routing requests are flowing.
        notify_circuit_breaker(backend_id, status)

        Map.put(acc, backend_id, status)
      end)

    new_state = %{state | backend_health: new_health, last_check: DateTime.utc_now()}

    # Schedule next check
    schedule_health_check(state.check_interval)

    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp backend_identifier(backend) when is_map(backend) do
    # Create a unique identifier for the backend
    type = Map.get(backend, :type) || Map.get(backend, "type") || "unknown"
    name = Map.get(backend, :name) || Map.get(backend, "name") || ""
    "#{type}:#{name}"
  end

  defp backend_identifier(backend) when is_binary(backend), do: backend
  defp backend_identifier(backend) when is_atom(backend), do: Atom.to_string(backend)

  defp perform_health_check(backend, timeout) do
    # Determine check type based on backend configuration
    case Map.get(backend, :health_check) do
      nil ->
        # Default: assume healthy
        :healthy

      %{type: :http, url: url} ->
        check_http(url, timeout)

      %{type: :tcp, host: host, port: port} ->
        check_tcp(host, port, timeout)

      %{type: :function, fun: fun} when is_function(fun, 0) ->
        check_function(fun)

      _ ->
        :unknown
    end
  end

  defp check_http(url, timeout) do
    # Simple HTTP health check
    # In production, use a proper HTTP client
    try do
      case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, timeout}], []) do
        {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :healthy
        {:ok, {{_, status, _}, _, _}} when status in 500..599 -> :unhealthy
        {:ok, _} -> :degraded
        {:error, _} -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    catch
      _ -> :unhealthy
    end
  end

  defp check_tcp(host, port, timeout) do
    host_charlist =
      if is_binary(host), do: String.to_charlist(host), else: host

    case :gen_tcp.connect(host_charlist, port, [], timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :healthy

      {:error, _} ->
        :unhealthy
    end
  end

  defp check_function(fun) do
    try do
      case fun.() do
        true -> :healthy
        false -> :unhealthy
        :ok -> :healthy
        :healthy -> :healthy
        :unhealthy -> :unhealthy
        :degraded -> :degraded
        _ -> :unknown
      end
    rescue
      _ -> :unhealthy
    end
  end

  # Notify the circuit breaker of a health check outcome for a backend.
  #
  # - :healthy and :degraded are treated as successes (the backend is
  #   responsive, even if degraded — degraded backends should still receive
  #   traffic so they can recover, and circuit breakers are for total failures).
  # - :unhealthy is treated as a failure (the backend is down or returning
  #   errors, contributing to the consecutive failure count).
  # - :unknown is ignored (no data to act on — the backend may not have been
  #   probed yet, so we avoid false positives).
  #
  # The backend_id here uses the HealthChecker's "type:name" format. We extract
  # just the name portion for the circuit breaker, which keys by name only.
  @spec notify_circuit_breaker(String.t(), health_status()) :: :ok
  defp notify_circuit_breaker(backend_id, status) do
    # Extract the backend name from the "type:name" identifier format.
    # If the backend_id doesn't contain a colon, use it as-is.
    backend_name =
      case String.split(backend_id, ":", parts: 2) do
        [_type, name] when name != "" -> name
        _ -> backend_id
      end

    case status do
      :healthy ->
        CircuitBreaker.record_success(backend_name)

      :degraded ->
        # Degraded is still "alive" — treat as success for circuit breaker
        # purposes. The routing pipeline's health filter will still deprioritize
        # degraded backends, but the circuit won't trip.
        CircuitBreaker.record_success(backend_name)

      :unhealthy ->
        CircuitBreaker.record_failure(backend_name)

      :unknown ->
        # No data to act on — don't influence the circuit breaker.
        :ok
    end

    :ok
  end
end
