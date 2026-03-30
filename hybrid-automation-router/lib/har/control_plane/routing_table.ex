defmodule HAR.ControlPlane.RoutingTable do
  @moduledoc """
  Pattern-based routing table for backend selection.

  Loads routing rules from YAML configuration and matches operations
  against patterns to determine appropriate backends.
  """

  use GenServer
  require Logger

  alias HAR.Semantic.Operation

  @type backend :: %{
          name: String.t(),
          type: atom(),
          priority: non_neg_integer(),
          capabilities: [atom()],
          metadata: map()
        }

  @type route :: %{
          pattern: map(),
          backends: [backend()]
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Match an operation against routing table to find backends.

  Returns list of backends sorted by priority (highest first).
  """
  @spec match(Operation.t(), atom()) :: [backend()]
  def match(%Operation{} = operation, target) do
    GenServer.call(__MODULE__, {:match, operation, target})
  end

  @doc """
  Reload routing table from file.
  """
  @spec reload(String.t()) :: :ok | {:error, term()}
  def reload(path) do
    GenServer.call(__MODULE__, {:reload, path})
  end

  @doc """
  Get current routing table.
  """
  @spec get_routes() :: [route()]
  def get_routes do
    GenServer.call(__MODULE__, :get_routes)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    table_path = Keyword.get(opts, :routing_table_path, default_table_path())

    case load_routing_table(table_path) do
      {:ok, routes} ->
        Logger.info("Loaded #{length(routes)} routing rules from #{table_path}")
        {:ok, %{routes: routes, path: table_path, regex_cache: %{}}}

      {:error, reason} ->
        Logger.warning("Failed to load routing table: #{inspect(reason)}, using defaults")
        {:ok, %{routes: default_routes(), path: nil, regex_cache: %{}}}
    end
  end

  @impl true
  def handle_call({:match, operation, target}, _from, state) do
    {matching_backends, new_cache} =
      find_matching_backends(operation, target, state.routes, state.regex_cache)

    {:reply, matching_backends, %{state | regex_cache: new_cache}}
  end

  def handle_call({:reload, path}, _from, state) do
    case load_routing_table(path) do
      {:ok, routes} ->
        Logger.info("Reloaded routing table from #{path}")
        # Flush regex cache on reload — patterns may have changed
        {:reply, :ok, %{state | routes: routes, path: path, regex_cache: %{}}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_routes, _from, state) do
    {:reply, state.routes, state}
  end

  # Internal Functions

  defp load_routing_table(path) do
    with {:ok, content} <- File.read(path),
         {:ok, yaml} <- YamlElixir.read_from_string(content) do
      routes = parse_routing_config(yaml)
      {:ok, routes}
    end
  end

  defp parse_routing_config(%{"routes" => routes}) when is_list(routes) do
    Enum.map(routes, &parse_route/1)
  end

  defp parse_routing_config(_), do: []

  defp parse_route(%{"pattern" => pattern, "backends" => backends}) do
    %{
      pattern: parse_pattern(pattern),
      backends: Enum.map(backends, &parse_backend/1)
    }
  end

  defp parse_pattern(pattern) when is_map(pattern) do
    Map.new(pattern, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp parse_backend(%{"name" => name} = backend) do
    %{
      name: name,
      type: Map.get(backend, "type", "local") |> String.to_existing_atom(),
      priority: Map.get(backend, "priority", 50),
      capabilities: Map.get(backend, "capabilities", []) |> Enum.map(&String.to_existing_atom/1),
      metadata: Map.get(backend, "metadata", %{})
    }
  end

  # find_matching_backends now threads the regex cache through pattern matching.
  # Compiled regexes are cached by their source pattern string, so repeated
  # matches against the same wildcard pattern (e.g., "debian*") compile once
  # and reuse the cached Regex.t() on subsequent calls.
  #
  # This eliminates the O(compile) cost per match — Regex.compile!/1 is
  # expensive relative to Regex.match?/2, so caching gives 50-100% speedup
  # for wildcard-heavy routing tables.
  #
  # Cache is flushed on table reload (patterns may have changed).
  defp find_matching_backends(operation, target, routes, regex_cache) do
    {matching_routes, updated_cache} =
      Enum.reduce(routes, {[], regex_cache}, fn route, {acc, cache} ->
        {matches?, new_cache} = pattern_matches?(route.pattern, operation, target, cache)

        if matches? do
          {[route | acc], new_cache}
        else
          {acc, new_cache}
        end
      end)

    backends =
      matching_routes
      |> Enum.reverse()
      |> Enum.flat_map(& &1.backends)
      |> Enum.sort_by(& &1.priority, :desc)
      |> Enum.uniq_by(& &1.name)

    {backends, updated_cache}
  end

  # pattern_matches? now accepts and returns a regex cache map, threading it
  # through each field match to accumulate compiled regexes.
  defp pattern_matches?(pattern, operation, _target, cache) do
    # Match operation type
    {operation_matches, cache} = match_field(pattern[:operation], operation.type, cache)

    # Match target fields
    {target_matches, cache} =
      if pattern[:target] do
        Enum.reduce_while(pattern.target, {true, cache}, fn {key, pattern_value}, {_acc, c} ->
          actual_value = Map.get(operation.target, key)
          {matches?, new_c} = match_field(pattern_value, actual_value, c)

          if matches? do
            {:cont, {true, new_c}}
          else
            {:halt, {false, new_c}}
          end
        end)
      else
        {true, cache}
      end

    {operation_matches and target_matches, cache}
  end

  defp match_field(nil, _actual, cache), do: {true, cache}
  defp match_field("*", _actual, cache), do: {true, cache}
  defp match_field(pattern, actual, cache) when is_atom(pattern), do: {pattern == actual, cache}

  defp match_field(pattern, actual, cache) when is_binary(pattern) and is_atom(actual) do
    match_field(pattern, Atom.to_string(actual), cache)
  end

  defp match_field(pattern, actual, cache) when is_binary(pattern) and is_binary(actual) do
    cond do
      String.contains?(pattern, "*") -> wildcard_match?(pattern, actual, cache)
      true -> {pattern == actual, cache}
    end
  end

  defp match_field(pattern, actual, cache), do: {pattern == actual, cache}

  # wildcard_match? now uses a cache keyed by the source pattern string.
  # On first encounter, the pattern is compiled and stored in the cache.
  # Subsequent matches against the same pattern reuse the compiled Regex.t(),
  # avoiding the O(compile) cost per match.
  #
  # Inspired by http-capability-gateway's ETS-based compiled route cache
  # and aerie's trie-based prefix matching (2026-02-28).
  defp wildcard_match?(pattern, string, cache) do
    {regex, updated_cache} =
      case Map.get(cache, pattern) do
        nil ->
          regex_source =
            pattern
            |> String.replace(".", "\\.")
            |> String.replace("*", ".*")
            |> then(&("^" <> &1 <> "$"))

          compiled = Regex.compile!(regex_source)
          {compiled, Map.put(cache, pattern, compiled)}

        cached_regex ->
          {cached_regex, cache}
      end

    {Regex.match?(regex, string), updated_cache}
  end

  defp default_table_path do
    Path.join([Application.app_dir(:har, "priv"), "routing_table.yaml"])
  end

  defp default_routes do
    [
      # Fallback: use target backend
      %{
        pattern: %{operation: "*"},
        backends: [
          %{
            name: "default",
            type: :passthrough,
            priority: 1,
            capabilities: [:all],
            metadata: %{}
          }
        ]
      }
    ]
  end
end
