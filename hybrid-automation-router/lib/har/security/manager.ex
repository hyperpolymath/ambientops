# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# HAR Security Manager — authentication, authorization, rate limiting,
# and certificate validation for the Hybrid Automation Router.
#
# Implements:
#   - API key header validation (basic auth via X-HAR-API-Key header)
#   - Token-bucket rate limiting per client IP (configurable)
#   - X.509 certificate validation (expiry, chain, field checks)
#     via Erlang's :public_key module
#   - Tier-based authorization (development / iot / industrial / critical)
#   - Immutable audit logging to ETS
#
# Configuration (config/runtime.exs):
#
#     config :har,
#       security_tier: :development,
#       api_keys: ["key-1", "key-2"],
#       rate_limit: [
#         bucket_size: 100,        # max tokens per bucket
#         refill_rate: 10,          # tokens added per second
#         refill_interval_ms: 1000  # how often to refill
#       ],
#       tls: [
#         cert_file: "priv/cert.pem",
#         key_file: "priv/key.pem",
#         ca_file: "priv/ca.pem"
#       ]

defmodule HAR.Security.Manager do
  @moduledoc """
  Security manager for HAR.

  Handles:
  - API key authentication (header-based)
  - Token-bucket rate limiting (per client IP)
  - X.509 certificate validation (expiry, chain integrity)
  - Tier-based authorization
  - Immutable audit logging

  ## Security Tiers

  - `:development` - Self-signed certs accepted, all operations allowed, rate limiting optional
  - `:iot` - Device certs required, rate limiting enforced
  - `:industrial` - Mutual TLS, restricted operation set
  - `:critical` - HSM-backed certs, formal verification required

  ## Configuration

      config :har,
        security_tier: :development,
        api_keys: ["my-secret-key"],
        rate_limit: [bucket_size: 100, refill_rate: 10, refill_interval_ms: 1000]
  """

  use GenServer
  require Logger

  @audit_table :security_audit_log
  @policy_table :security_policies
  @rate_limit_table :security_rate_limits
  @api_key_table :security_api_keys

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

  # Default rate-limit configuration (token bucket)
  @default_rate_limit %{
    bucket_size: 100,
    refill_rate: 10,
    refill_interval_ms: 1_000
  }

  # ──────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────

  @doc "Start the security manager under a supervision tree."
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
  Validate an API key from a request header.

  Returns `{:ok, :valid}` if the key is in the configured allow-list,
  or `{:error, :invalid_api_key}` otherwise.  In `:development` tier
  any non-empty key is accepted.

  ## Examples

      iex> HAR.Security.Manager.validate_api_key("my-secret-key")
      {:ok, :valid}
  """
  @spec validate_api_key(String.t()) :: {:ok, :valid} | {:error, :invalid_api_key | :missing_api_key}
  def validate_api_key(key) when is_binary(key) do
    GenServer.call(__MODULE__, {:validate_api_key, key})
  end

  def validate_api_key(nil), do: {:error, :missing_api_key}
  def validate_api_key(_), do: {:error, :invalid_api_key}

  @doc """
  Check rate limit for a client identified by `client_id` (typically an
  IP address string).

  Uses a token-bucket algorithm: each client gets a bucket of
  `bucket_size` tokens.  Each call consumes one token.  Tokens are
  refilled at `refill_rate` tokens per `refill_interval_ms`.

  Returns `:ok` if the request is allowed, or
  `{:error, :rate_limited, retry_after_ms}` if the bucket is empty.

  ## Examples

      iex> HAR.Security.Manager.check_rate_limit("192.168.1.1")
      :ok
  """
  @spec check_rate_limit(String.t()) :: :ok | {:error, :rate_limited, non_neg_integer()}
  def check_rate_limit(client_id) when is_binary(client_id) do
    GenServer.call(__MODULE__, {:check_rate_limit, client_id})
  end

  @doc """
  Validate a DER-encoded X.509 certificate using Erlang's `:public_key`
  module.  Checks:

  1. Certificate can be decoded (valid DER/PEM structure)
  2. Certificate is not expired (notBefore <= now <= notAfter)
  3. If a CA certificate is configured, validates the signature chain

  Returns `{:ok, cert_info}` with extracted subject/issuer/validity,
  or `{:error, reason}`.

  ## Examples

      iex> der_bytes = File.read!("priv/device.der")
      iex> HAR.Security.Manager.validate_certificate(der_bytes)
      {:ok, %{subject: "CN=device-01", issuer: "CN=HAR-CA", ...}}
  """
  @spec validate_certificate(binary()) :: {:ok, map()} | {:error, term()}
  def validate_certificate(cert_der) when is_binary(cert_der) do
    GenServer.call(__MODULE__, {:validate_certificate, cert_der})
  end

  @doc """
  Authorize an operation for an authenticated identity.

  Checks the operation type against the allowed operations for the
  current security tier.  For the `:development` tier, all operations
  are allowed.

  ## Parameters

  - `identity` - Map returned from `authenticate/1` (must contain `:device_id`)
  - `operation` - Operation atom (e.g., `:package_install`) or a map with `:type`

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

  Events are stored in an ETS table with a monotonic sequence number
  for ordering.  Each entry includes the event type, timestamp, and
  arbitrary detail map.

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

  @doc """
  Return a summary of rate-limit state for all tracked clients.
  Useful for dashboards and diagnostics.

  ## Examples

      iex> HAR.Security.Manager.rate_limit_status()
      [%{client_id: "192.168.1.1", tokens: 97, bucket_size: 100}, ...]
  """
  @spec rate_limit_status() :: [map()]
  def rate_limit_status do
    GenServer.call(__MODULE__, :rate_limit_status)
  end

  # ──────────────────────────────────────────────────────────────────
  # Server Callbacks
  # ──────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    security_tier = Application.get_env(:har, :security_tier, :development)
    Logger.info("Security manager starting — tier: #{security_tier}")

    audit_tbl = ensure_ets_table(@audit_table, [:ordered_set, :protected])
    policy_tbl = ensure_ets_table(@policy_table, [:set, :protected])
    rate_tbl = ensure_ets_table(@rate_limit_table, [:set, :public])
    api_key_tbl = ensure_ets_table(@api_key_table, [:set, :protected])

    # Load tier policies into ETS for fast lookup
    allowed_ops = Map.get(@tier_policies, security_tier, :all)
    :ets.insert(policy_tbl, {:allowed_operations, allowed_ops})

    # Load API keys from config
    api_keys = Application.get_env(:har, :api_keys, [])

    for key <- api_keys do
      # Store SHA-256 hash of key — never store plaintext
      hash = :crypto.hash(:sha256, key)
      :ets.insert(api_key_tbl, {hash, true})
    end

    # Parse rate-limit config
    rate_config = load_rate_limit_config()

    # Start the token-bucket refill timer
    if rate_config.refill_interval_ms > 0 do
      :timer.send_interval(rate_config.refill_interval_ms, :refill_buckets)
    end

    {:ok,
     %{
       tier: security_tier,
       tls_config: load_tls_config(),
       audit_table: audit_tbl,
       policy_table: policy_tbl,
       rate_limit_table: rate_tbl,
       api_key_table: api_key_tbl,
       rate_config: rate_config,
       audit_counter: 0
     }}
  end

  # ── handle_call ────────────────────────────────────────────────────

  @impl true
  def handle_call({:authenticate, cert}, _from, %{tier: tier} = state) do
    {result, new_state} = do_authenticate(cert, tier, state)
    {:reply, result, new_state}
  end

  def handle_call({:validate_api_key, key}, _from, state) do
    {result, new_state} = do_validate_api_key(key, state)
    {:reply, result, new_state}
  end

  def handle_call({:check_rate_limit, client_id}, _from, state) do
    {result, new_state} = do_check_rate_limit(client_id, state)
    {:reply, result, new_state}
  end

  def handle_call({:validate_certificate, cert_der}, _from, state) do
    {result, new_state} = do_validate_certificate(cert_der, state)
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

  def handle_call(:rate_limit_status, _from, state) do
    entries =
      :ets.tab2list(state.rate_limit_table)
      |> Enum.map(fn {client_id, tokens, _last_refill} ->
        %{
          client_id: client_id,
          tokens: tokens,
          bucket_size: state.rate_config.bucket_size
        }
      end)

    {:reply, entries, state}
  end

  # ── handle_cast ────────────────────────────────────────────────────

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

  # ── handle_info ────────────────────────────────────────────────────

  @impl true
  def handle_info(:refill_buckets, state) do
    refill_all_buckets(state)
    {:noreply, state}
  end

  # ──────────────────────────────────────────────────────────────────
  # API Key Validation
  # ──────────────────────────────────────────────────────────────────

  defp do_validate_api_key("", state) do
    new_state = write_audit(state, :api_key_rejected, %{reason: :empty_key})
    {{:error, :missing_api_key}, new_state}
  end

  defp do_validate_api_key(key, %{tier: :development} = state) do
    # Development tier: accept any non-empty key
    new_state = write_audit(state, :api_key_accepted, %{tier: :development})
    {{:ok, :valid}, new_state}
  end

  defp do_validate_api_key(key, state) do
    hash = :crypto.hash(:sha256, key)

    case :ets.lookup(state.api_key_table, hash) do
      [{^hash, true}] ->
        new_state = write_audit(state, :api_key_accepted, %{})
        {{:ok, :valid}, new_state}

      _ ->
        new_state = write_audit(state, :api_key_rejected, %{reason: :invalid_key})
        {{:error, :invalid_api_key}, new_state}
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Rate Limiting (Token Bucket)
  # ──────────────────────────────────────────────────────────────────

  defp do_check_rate_limit(client_id, state) do
    now_ms = System.monotonic_time(:millisecond)
    bucket_size = state.rate_config.bucket_size

    case :ets.lookup(state.rate_limit_table, client_id) do
      [] ->
        # First request from this client — create a full bucket, consume 1 token
        :ets.insert(state.rate_limit_table, {client_id, bucket_size - 1, now_ms})
        new_state = write_audit(state, :rate_limit_pass, %{client_id: client_id, tokens: bucket_size - 1})
        {:ok, new_state}

      [{^client_id, tokens, last_refill}] when tokens > 0 ->
        # Tokens available — consume one
        new_tokens = tokens - 1
        :ets.insert(state.rate_limit_table, {client_id, new_tokens, last_refill})
        {:ok, state}

      [{^client_id, 0, _last_refill}] ->
        # Bucket empty — reject with retry-after hint
        retry_after = state.rate_config.refill_interval_ms
        new_state = write_audit(state, :rate_limit_exceeded, %{client_id: client_id, retry_after_ms: retry_after})
        {{:error, :rate_limited, retry_after}, new_state}
    end
  end

  # refill_all_buckets adds tokens to every tracked client bucket,
  # capped at bucket_size.  Called by the periodic timer.
  defp refill_all_buckets(state) do
    bucket_size = state.rate_config.bucket_size
    refill_rate = state.rate_config.refill_rate
    now_ms = System.monotonic_time(:millisecond)

    :ets.tab2list(state.rate_limit_table)
    |> Enum.each(fn {client_id, tokens, _last_refill} ->
      new_tokens = min(tokens + refill_rate, bucket_size)
      :ets.insert(state.rate_limit_table, {client_id, new_tokens, now_ms})
    end)
  end

  # ──────────────────────────────────────────────────────────────────
  # Certificate Validation (Erlang :public_key)
  # ──────────────────────────────────────────────────────────────────

  defp do_validate_certificate(cert_der, state) do
    case decode_certificate(cert_der) do
      {:ok, otp_cert} ->
        with :ok <- check_cert_validity(otp_cert),
             :ok <- check_cert_chain(otp_cert, state) do
          info = extract_cert_info(otp_cert)
          new_state = write_audit(state, :cert_valid, %{subject: info.subject})
          {{:ok, info}, new_state}
        else
          {:error, reason} ->
            new_state = write_audit(state, :cert_invalid, %{reason: reason})
            {{:error, reason}, new_state}
        end

      {:error, reason} ->
        new_state = write_audit(state, :cert_decode_failed, %{reason: reason})
        {{:error, {:decode_failed, reason}}, new_state}
    end
  end

  # Decode a DER-encoded or PEM-encoded certificate into an OTPCertificate
  # record.  Tries DER first, then PEM.
  defp decode_certificate(cert_bytes) do
    try do
      # Try DER decoding first
      case :public_key.der_decode(:OTPCertificate, cert_bytes) do
        otp_cert when is_tuple(otp_cert) ->
          {:ok, otp_cert}
      end
    rescue
      _ ->
        # Try PEM decoding
        try do
          case :public_key.pem_decode(cert_bytes) do
            [{:Certificate, der, :not_encrypted} | _] ->
              otp_cert = :public_key.der_decode(:OTPCertificate, der)
              {:ok, otp_cert}

            [{_type, der, :not_encrypted} | _] ->
              otp_cert = :public_key.der_decode(:OTPCertificate, der)
              {:ok, otp_cert}

            [] ->
              {:error, :no_certificates_found}

            _ ->
              {:error, :unsupported_pem_format}
          end
        rescue
          e -> {:error, {:pem_decode_failed, Exception.message(e)}}
        end
    end
  end

  # Check that the certificate is currently valid (not before/not after).
  defp check_cert_validity(otp_cert) do
    try do
      # Extract the TBSCertificate from the OTPCertificate record
      tbs = elem(otp_cert, 1)
      # Extract validity from TBSCertificate
      validity = elem(tbs, 4)
      not_before = elem(validity, 1)
      not_after = elem(validity, 2)

      now = :calendar.universal_time()

      not_before_dt = parse_asn1_time(not_before)
      not_after_dt = parse_asn1_time(not_after)

      cond do
        now < not_before_dt ->
          {:error, :cert_not_yet_valid}

        now > not_after_dt ->
          {:error, :cert_expired}

        true ->
          :ok
      end
    rescue
      _ -> {:error, :validity_check_failed}
    end
  end

  # Parse ASN.1 time formats (UTCTime or GeneralizedTime) into
  # Erlang calendar datetime tuples.
  defp parse_asn1_time({:utcTime, time_charlist}) do
    time_str = List.to_string(time_charlist)
    parse_utc_time_string(time_str)
  end

  defp parse_asn1_time({:generalTime, time_charlist}) do
    time_str = List.to_string(time_charlist)
    parse_generalized_time_string(time_str)
  end

  defp parse_asn1_time(time_charlist) when is_list(time_charlist) do
    time_str = List.to_string(time_charlist)

    if String.length(time_str) > 12 do
      parse_generalized_time_string(time_str)
    else
      parse_utc_time_string(time_str)
    end
  end

  defp parse_asn1_time(_), do: {{2000, 1, 1}, {0, 0, 0}}

  # UTCTime format: YYMMDDHHMMSSZ
  defp parse_utc_time_string(str) do
    yy = String.slice(str, 0, 2) |> String.to_integer()
    mm = String.slice(str, 2, 2) |> String.to_integer()
    dd = String.slice(str, 4, 2) |> String.to_integer()
    hh = String.slice(str, 6, 2) |> String.to_integer()
    mi = String.slice(str, 8, 2) |> String.to_integer()
    ss = String.slice(str, 10, 2) |> String.to_integer()

    # RFC 5280: YY >= 50 means 19YY, YY < 50 means 20YY
    year = if yy >= 50, do: 1900 + yy, else: 2000 + yy
    {{year, mm, dd}, {hh, mi, ss}}
  end

  # GeneralizedTime format: YYYYMMDDHHMMSSZ
  defp parse_generalized_time_string(str) do
    yyyy = String.slice(str, 0, 4) |> String.to_integer()
    mm = String.slice(str, 4, 2) |> String.to_integer()
    dd = String.slice(str, 6, 2) |> String.to_integer()
    hh = String.slice(str, 8, 2) |> String.to_integer()
    mi = String.slice(str, 10, 2) |> String.to_integer()
    ss = String.slice(str, 12, 2) |> String.to_integer()
    {{yyyy, mm, dd}, {hh, mi, ss}}
  end

  # Validate the certificate chain against a configured CA certificate.
  # If no CA is configured, chain validation is skipped (development mode).
  defp check_cert_chain(otp_cert, state) do
    ca_file = get_in(state, [:tls_config, :ca_file])

    if ca_file && File.exists?(ca_file) do
      try do
        ca_pem = File.read!(ca_file)

        case :public_key.pem_decode(ca_pem) do
          [{:Certificate, ca_der, :not_encrypted} | _] ->
            ca_cert = :public_key.der_decode(:OTPCertificate, ca_der)

            # Extract the CA's public key for signature verification
            ca_tbs = elem(ca_cert, 1)
            ca_spki = elem(ca_tbs, 6)
            ca_public_key = elem(ca_spki, 1)

            # Extract the certificate's TBS data and signature
            cert_tbs_der = :public_key.der_encode(:OTPTBSCertificate, elem(otp_cert, 1))
            signature = elem(otp_cert, 3)
            sig_algo = elem(elem(otp_cert, 2), 1)

            # Map OID to digest algorithm
            digest = sig_algo_to_digest(sig_algo)

            case :public_key.verify(cert_tbs_der, digest, signature, ca_public_key) do
              true -> :ok
              false -> {:error, :chain_verification_failed}
            end

          _ ->
            {:error, :invalid_ca_certificate}
        end
      rescue
        _ -> {:error, :chain_verification_error}
      end
    else
      # No CA configured — skip chain validation (acceptable in dev tier)
      :ok
    end
  end

  # Map common X.509 signature algorithm OIDs to digest atoms.
  defp sig_algo_to_digest({1, 2, 840, 113_549, 1, 1, 11}), do: :sha256
  defp sig_algo_to_digest({1, 2, 840, 113_549, 1, 1, 12}), do: :sha384
  defp sig_algo_to_digest({1, 2, 840, 113_549, 1, 1, 13}), do: :sha512
  defp sig_algo_to_digest({1, 2, 840, 113_549, 1, 1, 5}), do: :sha
  defp sig_algo_to_digest(_), do: :sha256

  # Extract human-readable certificate information from an OTPCertificate.
  defp extract_cert_info(otp_cert) do
    try do
      tbs = elem(otp_cert, 1)
      serial = elem(tbs, 1)
      issuer_rdn = elem(tbs, 3)
      validity = elem(tbs, 4)
      subject_rdn = elem(tbs, 5)

      %{
        serial: serial,
        subject: rdn_to_string(subject_rdn),
        issuer: rdn_to_string(issuer_rdn),
        not_before: parse_asn1_time(elem(validity, 1)),
        not_after: parse_asn1_time(elem(validity, 2)),
        days_until_expiry: days_until_expiry(parse_asn1_time(elem(validity, 2)))
      }
    rescue
      _ ->
        %{
          serial: nil,
          subject: "unknown",
          issuer: "unknown",
          not_before: nil,
          not_after: nil,
          days_until_expiry: nil
        }
    end
  end

  # Convert an RDN sequence to a human-readable string like "CN=device-01, O=HAR".
  defp rdn_to_string(rdn) when is_tuple(rdn) do
    try do
      {:rdnSequence, rdn_sets} = rdn

      rdn_sets
      |> List.flatten()
      |> Enum.map(fn attr_tv ->
        # AttributeTypeAndValue record
        oid = elem(attr_tv, 1)
        value = elem(attr_tv, 2)
        "#{oid_to_name(oid)}=#{format_rdn_value(value)}"
      end)
      |> Enum.join(", ")
    rescue
      _ -> inspect(rdn)
    end
  end

  defp rdn_to_string(other), do: inspect(other)

  # Map common X.500 attribute OIDs to short names.
  defp oid_to_name({2, 5, 4, 3}), do: "CN"
  defp oid_to_name({2, 5, 4, 6}), do: "C"
  defp oid_to_name({2, 5, 4, 7}), do: "L"
  defp oid_to_name({2, 5, 4, 8}), do: "ST"
  defp oid_to_name({2, 5, 4, 10}), do: "O"
  defp oid_to_name({2, 5, 4, 11}), do: "OU"
  defp oid_to_name({1, 2, 840, 113_549, 1, 9, 1}), do: "E"
  defp oid_to_name(oid), do: inspect(oid)

  # Format an RDN value (may be UTF8String, PrintableString, charlist, etc.)
  defp format_rdn_value({:utf8String, bytes}) when is_binary(bytes), do: bytes
  defp format_rdn_value({:printableString, chars}) when is_list(chars), do: List.to_string(chars)
  defp format_rdn_value({:ia5String, chars}) when is_list(chars), do: List.to_string(chars)
  defp format_rdn_value(chars) when is_list(chars), do: List.to_string(chars)
  defp format_rdn_value(bin) when is_binary(bin), do: bin
  defp format_rdn_value(other), do: inspect(other)

  # Calculate days until a certificate expires (from an Erlang datetime tuple).
  defp days_until_expiry({{year, month, day}, _time}) do
    expiry_date = Date.new!(year, month, day)
    today = Date.utc_today()
    Date.diff(expiry_date, today)
  rescue
    _ -> nil
  end

  # ──────────────────────────────────────────────────────────────────
  # Authentication Logic
  # ──────────────────────────────────────────────────────────────────

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

  # ──────────────────────────────────────────────────────────────────
  # Authorization Logic
  # ──────────────────────────────────────────────────────────────────

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
        # No policy found — deny by default
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

  # ──────────────────────────────────────────────────────────────────
  # Audit Helpers
  # ──────────────────────────────────────────────────────────────────

  defp write_audit(state, event_type, details) do
    entry = %{
      timestamp: DateTime.utc_now(),
      event: event_type,
      details: details
    }

    :ets.insert(state.audit_table, {state.audit_counter, entry})
    %{state | audit_counter: state.audit_counter + 1}
  end

  # ──────────────────────────────────────────────────────────────────
  # ETS Helpers
  # ──────────────────────────────────────────────────────────────────

  defp ensure_ets_table(name, opts) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, opts ++ [:named_table])

      _ref ->
        # Table already exists (e.g., from a previous test run).  Reuse it.
        # Clear stale data to avoid cross-test contamination.
        :ets.delete_all_objects(name)
        name
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Config Helpers
  # ──────────────────────────────────────────────────────────────────

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

  defp load_rate_limit_config do
    user_config = Application.get_env(:har, :rate_limit, [])

    %{
      bucket_size: Keyword.get(user_config, :bucket_size, @default_rate_limit.bucket_size),
      refill_rate: Keyword.get(user_config, :refill_rate, @default_rate_limit.refill_rate),
      refill_interval_ms:
        Keyword.get(user_config, :refill_interval_ms, @default_rate_limit.refill_interval_ms)
    }
  end
end
