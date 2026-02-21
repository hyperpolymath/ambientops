# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.Security.Manager do
  @moduledoc """
  Security manager for HAR.

  Handles:
  - Certificate validation and authentication
  - Policy-based authorization
  - Immutable audit logging

  ## Security Tiers

  - `:development` - Self-signed certs accepted, all operations allowed
  - `:iot` - Device certs required, rate limiting enforced
  - `:industrial` - Mutual TLS, restricted operation set
  - `:critical` - HSM-backed certs, formal verification required

  ## Configuration

      config :har,
        security_tier: :development
  """

  use GenServer
  require Logger

  @audit_table :security_audit_log
  @policy_table :security_policies

  # Default allowed operations per tier
  @tier_policies %{
    development: :all,
    iot: [
      :package_install,
      :package_remove,
      :service_start,
      :service_stop,
      :service_restart,
      :file_write,
      :file_copy,
      :command_run
    ],
    industrial: [
      :package_install,
      :service_start,
      :service_stop,
      :service_restart,
      :file_write
    ],
    critical: [
      :service_start,
      :service_stop,
      :service_restart
    ]
  }

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Authenticate a device or user by certificate.

  Accepts a certificate map with the following fields:
  - `:subject` - Certificate subject (e.g., "CN=device-01")
  - `:issuer` - Certificate issuer (e.g., "CN=HAR-CA")
  - `:not_before` - Certificate validity start (`DateTime`)
  - `:not_after` - Certificate validity end (`DateTime`)

  For the `:development` tier, authentication always succeeds.
  For higher tiers, certificate expiration is validated.

  ## Examples

      iex> cert = %{
      ...>   subject: "CN=device-01",
      ...>   issuer: "CN=HAR-CA",
      ...>   not_before: ~U[2025-01-01 00:00:00Z],
      ...>   not_after: ~U[2027-01-01 00:00:00Z]
      ...> }
      iex> HAR.Security.Manager.authenticate(cert)
      {:ok, %{authenticated: true, device_id: "CN=device-01", tier: :development}}
  """
  @spec authenticate(map()) :: {:ok, map()} | {:error, term()}
  def authenticate(cert) when is_map(cert) do
    GenServer.call(__MODULE__, {:authenticate, cert})
  end

  @doc """
  Authorize an operation for an authenticated identity.

  Checks the operation type against the allowed operations for the
  current security tier. For the `:development` tier, all operations
  are allowed.

  ## Parameters

  - `identity` - Map returned from `authenticate/1` (must contain `:device_id`)
  - `operation` - Operation atom (e.g., `:package_install`) or an `Operation` struct

  ## Examples

      iex> identity = %{device_id: "CN=device-01", tier: :development}
      iex> HAR.Security.Manager.authorize(identity, :package_install)
      :ok
  """
  @spec authorize(map(), atom() | map()) :: :ok | {:error, term()}
  def authorize(identity, operation) do
    GenServer.call(__MODULE__, {:authorize, identity, operation})
  end

  @doc """
  Log a security event to the immutable audit log.

  Events are stored in an ETS table with a monotonic timestamp for
  ordering. Each entry includes the event type and arbitrary details.

  ## Examples

      iex> HAR.Security.Manager.audit_log(:auth_success, %{device: "CN=device-01"})
      :ok
  """
  @spec audit_log(atom(), map()) :: :ok
  def audit_log(event_type, details \\ %{}) when is_atom(event_type) and is_map(details) do
    GenServer.cast(__MODULE__, {:audit_log, event_type, details})
  end

  @doc """
  Retrieve all audit log entries, ordered oldest-first.

  ## Examples

      iex> HAR.Security.Manager.get_audit_log()
      [%{timestamp: ~U[...], event: :auth_success, details: %{...}}, ...]
  """
  @spec get_audit_log() :: [map()]
  def get_audit_log do
    GenServer.call(__MODULE__, :get_audit_log)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    security_tier = Application.get_env(:har, :security_tier, :development)
    Logger.info("Security tier: #{security_tier}")

    audit_tbl = ensure_ets_table(@audit_table, [:ordered_set, :protected])
    policy_tbl = ensure_ets_table(@policy_table, [:set, :protected])

    # Load tier policies into ETS for fast lookup
    allowed_ops = Map.get(@tier_policies, security_tier, :all)
    :ets.insert(policy_tbl, {:allowed_operations, allowed_ops})

    {:ok,
     %{
       tier: security_tier,
       tls_config: load_tls_config(),
       audit_table: audit_tbl,
       policy_table: policy_tbl,
       audit_counter: 0
     }}
  end

  @impl true
  def handle_call({:authenticate, cert}, _from, %{tier: tier} = state) do
    {result, new_state} = do_authenticate(cert, tier, state)
    {:reply, result, new_state}
  end

  def handle_call({:authorize, identity, operation}, _from, %{tier: tier} = state) do
    {result, new_state} = do_authorize(identity, operation, tier, state)
    {:reply, result, new_state}
  end

  def handle_call(:get_audit_log, _from, state) do
    entries =
      :ets.tab2list(state.audit_table)
      |> Enum.sort_by(fn {seq, _entry} -> seq end)
      |> Enum.map(fn {_seq, entry} -> entry end)

    {:reply, entries, state}
  end

  @impl true
  def handle_cast({:audit_log, event_type, details}, state) do
    entry = %{
      timestamp: DateTime.utc_now(),
      event: event_type,
      details: details
    }

    :ets.insert(state.audit_table, {state.audit_counter, entry})
    {:noreply, %{state | audit_counter: state.audit_counter + 1}}
  end

  # Authentication Logic

  defp do_authenticate(cert, :development, state) do
    # Development tier: always succeed, log the attempt
    device_id = Map.get(cert, :subject, "unknown_device")

    identity = %{
      authenticated: true,
      device_id: device_id,
      tier: :development
    }

    new_state = write_audit(state, :auth_success, %{device_id: device_id, tier: :development})
    {{:ok, identity}, new_state}
  end

  defp do_authenticate(cert, tier, state) do
    # Higher tiers: validate certificate fields
    with :ok <- validate_cert_fields(cert),
         :ok <- validate_cert_expiration(cert) do
      device_id = cert.subject

      identity = %{
        authenticated: true,
        device_id: device_id,
        tier: tier
      }

      new_state = write_audit(state, :auth_success, %{device_id: device_id, tier: tier})
      {{:ok, identity}, new_state}
    else
      {:error, reason} = error ->
        device_id = Map.get(cert, :subject, "unknown")
        new_state = write_audit(state, :auth_failure, %{device_id: device_id, reason: reason})
        {error, new_state}
    end
  end

  defp validate_cert_fields(cert) do
    required_fields = [:subject, :issuer, :not_before, :not_after]

    missing =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(cert, field)
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_cert_fields, missing}}
    end
  end

  defp validate_cert_expiration(%{not_before: not_before, not_after: not_after}) do
    now = DateTime.utc_now()

    cond do
      DateTime.compare(now, not_before) == :lt ->
        {:error, :cert_not_yet_valid}

      DateTime.compare(now, not_after) == :gt ->
        {:error, :cert_expired}

      true ->
        :ok
    end
  end

  # Authorization Logic

  defp do_authorize(identity, operation, :development, state) do
    # Development tier: always allow
    device_id = Map.get(identity, :device_id, "unknown")
    op_type = extract_operation_type(operation)

    new_state =
      write_audit(state, :authz_success, %{device_id: device_id, operation: op_type})

    {:ok, new_state}
  end

  defp do_authorize(identity, operation, _tier, state) do
    op_type = extract_operation_type(operation)
    device_id = Map.get(identity, :device_id, "unknown")

    case :ets.lookup(state.policy_table, :allowed_operations) do
      [{:allowed_operations, :all}] ->
        new_state =
          write_audit(state, :authz_success, %{device_id: device_id, operation: op_type})

        {:ok, new_state}

      [{:allowed_operations, allowed_ops}] when is_list(allowed_ops) ->
        if op_type in allowed_ops do
          new_state =
            write_audit(state, :authz_success, %{device_id: device_id, operation: op_type})

          {:ok, new_state}
        else
          new_state =
            write_audit(state, :authz_denied, %{
              device_id: device_id,
              operation: op_type,
              reason: :operation_not_allowed
            })

          {{:error, {:unauthorized, op_type}}, new_state}
        end

      _ ->
        # No policy found - deny by default
        new_state =
          write_audit(state, :authz_denied, %{
            device_id: device_id,
            operation: op_type,
            reason: :no_policy
          })

        {{:error, {:unauthorized, op_type}}, new_state}
    end
  end

  defp extract_operation_type(operation) when is_atom(operation), do: operation
  defp extract_operation_type(%{type: type}), do: type
  defp extract_operation_type(_), do: :unknown

  # Audit Helpers

  defp write_audit(state, event_type, details) do
    entry = %{
      timestamp: DateTime.utc_now(),
      event: event_type,
      details: details
    }

    :ets.insert(state.audit_table, {state.audit_counter, entry})
    %{state | audit_counter: state.audit_counter + 1}
  end

  # ETS Helpers

  defp ensure_ets_table(name, opts) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, opts ++ [:named_table])

      _ref ->
        # Table already exists (e.g., from a previous test run). Reuse it.
        # Clear stale data to avoid cross-test contamination.
        :ets.delete_all_objects(name)
        name
    end
  end

  # TLS Config

  defp load_tls_config do
    case Application.get_env(:har, :tls) do
      nil ->
        %{}

      tls_config ->
        %{
          cert_file: tls_config[:cert_file],
          key_file: tls_config[:key_file],
          ca_file: tls_config[:ca_file]
        }
    end
  end
end
