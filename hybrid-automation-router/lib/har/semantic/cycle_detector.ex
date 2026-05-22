# SPDX-License-Identifier: MPL-2.0
#
# HAR.Semantic.CycleDetector — cycle detection for the semantic graph IR.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.Semantic.CycleDetector do
  @moduledoc """
  Detects cycles in the semantic graph IR using depth-first search.

  Circular dependencies in infrastructure operations cause infinite loops
  during transformation and deployment. For example:

      Service A depends on Service B (A needs B's port to bind)
      Service B depends on Service C (B needs C's database connection)
      Service C depends on Service A (C needs A's API endpoint)

  This creates a deadlock: no service can start because each waits on
  another. The router MUST detect and reject such cycles before attempting
  to generate a deployment plan.

  ## Algorithm: Three-Colour DFS

  This module uses depth-first search with three-colour vertex marking,
  a classic graph algorithm from Cormen et al. (CLRS, Chapter 22):

  - **White** (`:white`) — Vertex has not been visited yet.
  - **Grey** (`:grey`) — Vertex is in the current DFS path (i.e., we have
    entered it but not yet finished exploring all its descendants).
  - **Black** (`:black`) — Vertex is fully explored (all descendants visited
    and marked black).

  A cycle exists if and only if we encounter a **back edge** — an edge from
  a grey vertex to another grey vertex. When this happens, the grey vertices
  on the DFS stack between the two endpoints form the cycle.

  ## Complexity

  The algorithm is **O(V + E)** where:
  - V = number of vertices (operations in the semantic graph)
  - E = number of edges (dependencies between operations)

  Each vertex is visited exactly once (white → grey → black), and each edge
  is examined exactly once during the neighbour scan. This makes the detector
  suitable for large infrastructure graphs with thousands of operations.

  ## Relationship to Graph.validate/1

  The `HAR.Semantic.Graph` module already has a `validate_acyclic/1` function
  that uses Kahn's algorithm (topological sort) to detect cycles. This module
  provides a complementary approach with two advantages:

  1. **Cycle path extraction**: Kahn's algorithm detects THAT a cycle exists
     but doesn't tell you WHICH vertices are in the cycle. This module returns
     the exact cycle path, which is essential for error messages.
  2. **Composability**: This module can be used independently of `Graph.validate/1`,
     e.g., for incremental cycle checks when adding a single edge.

  ## Adaptation to HAR Types

  This module is adapted to work with HAR's specific graph types:
  - **Vertices**: `HAR.Semantic.Operation` structs with `.id` field
  - **Edges**: `HAR.Semantic.Dependency` structs with `.from` and `.to` fields

  The accessor functions (`vertex_id/1`, `edge_source/1`, `edge_target/1`)
  abstract over these types, so the algorithm works even if the struct
  definitions change.

  ## Usage

      iex> graph = Graph.new(vertices: [op_a, op_b, op_c], edges: [dep_ab, dep_bc])
      iex> CycleDetector.check(graph)
      :acyclic

      iex> graph_with_cycle = Graph.add_dependency(graph, Dependency.new("c", "a", :requires))
      iex> CycleDetector.check(graph_with_cycle)
      {:cyclic, ["a", "b", "c", "a"]}
  """

  alias HAR.Semantic.Graph

  @typedoc """
  A cycle is represented as a list of vertex IDs (operation IDs) forming
  the cycle path. The first and last elements are the same vertex,
  showing where the cycle closes. For example, `["a", "b", "c", "a"]`
  means A → B → C → A.
  """
  @type cycle :: list(String.t())

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Check a semantic graph for cycles.

  Performs a full DFS traversal of the graph, visiting every vertex exactly
  once. If any back edge is found (indicating a cycle), the traversal
  stops immediately and returns the cycle path.

  ## Parameters

    - `graph` — A `%HAR.Semantic.Graph{}` struct containing vertices
      (operations) and edges (dependencies).

  ## Returns

    - `:acyclic` — The graph is a DAG (directed acyclic graph). Safe to
      generate a deployment plan from this graph.
    - `{:cyclic, cycle_path}` — A cycle was found. `cycle_path` is a list
      of operation IDs forming the cycle, e.g., `["a", "b", "c", "a"]`.
      Only the FIRST cycle found is returned — there may be others.

  ## Examples

      iex> acyclic_graph = Graph.new(vertices: ops, edges: deps)
      iex> CycleDetector.check(acyclic_graph)
      :acyclic

      iex> cyclic_graph = Graph.new(vertices: ops, edges: cyclic_deps)
      iex> CycleDetector.check(cyclic_graph)
      {:cyclic, ["service_a", "service_b", "service_c", "service_a"]}

  ## Complexity

  O(V + E) time, O(V) space for the colour map.
  """
  @spec check(Graph.t()) :: :acyclic | {:cyclic, cycle()}
  def check(%Graph{} = graph) do
    vertices = graph.vertices
    edges = graph.edges

    # Build an adjacency map for O(1) neighbour lookup during DFS.
    # Without this, finding neighbours would require scanning the full
    # edge list for each vertex (O(E) per vertex → O(V*E) total).
    adjacency = build_adjacency_map(edges)

    # Initialise all vertices as :white (unvisited).
    # The colour map is a plain Elixir map keyed by vertex ID (string).
    initial_colours = Map.new(vertices, fn v -> {vertex_id(v), :white} end)

    # Iterate over all vertices. For each unvisited (white) vertex,
    # start a DFS. This handles disconnected components — a graph may
    # have multiple connected components, each needing independent
    # cycle checking.
    result =
      Enum.reduce_while(vertices, {initial_colours, nil}, fn vertex, {colours, _} ->
        vid = vertex_id(vertex)

        case Map.get(colours, vid) do
          :white ->
            # Unvisited vertex — start DFS from here.
            case dfs(vid, adjacency, colours, [vid]) do
              {:cycle, cycle_path, _} ->
                {:halt, {colours, {:cyclic, cycle_path}}}

              {:ok, updated_colours} ->
                {:cont, {updated_colours, nil}}
            end

          _ ->
            # Already visited (grey or black) — skip.
            # Grey shouldn't appear here (would indicate a bug in the DFS),
            # but black is expected for vertices already fully explored in
            # a previous DFS from a different start vertex.
            {:cont, {colours, nil}}
        end
      end)

    case result do
      {_, {:cyclic, path}} -> {:cyclic, path}
      {_, nil} -> :acyclic
    end
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  # Depth-first search with three-colour marking and cycle detection.
  #
  # Parameters:
  #   - vertex: Current vertex ID being explored
  #   - adjacency: Adjacency map (vertex_id → list of neighbour IDs)
  #   - colours: Map of vertex_id → :white | :grey | :black
  #   - path: Current DFS path (list of vertex IDs, newest first)
  #
  # Returns:
  #   - {:ok, updated_colours} — No cycle found from this vertex
  #   - {:cycle, cycle_path, colours} — Back edge found, cycle detected
  #
  # The path list is maintained in reverse order (current vertex at head)
  # for O(1) cons operations. It's reversed when a cycle is detected to
  # produce a human-readable cycle path.
  defp dfs(vertex, adjacency, colours, path) do
    # Mark current vertex as grey (in current DFS path).
    colours = Map.put(colours, vertex, :grey)

    # Get all neighbours (outgoing edges from this vertex).
    neighbours = Map.get(adjacency, vertex, [])

    # Explore each neighbour. Use reduce_while to short-circuit on
    # the first cycle found (no need to explore remaining neighbours
    # once a cycle is detected).
    result =
      Enum.reduce_while(neighbours, {:ok, colours}, fn neighbour, {:ok, cols} ->
        case Map.get(cols, neighbour, :black) do
          :grey ->
            # BACK EDGE FOUND — this neighbour is already in the current
            # DFS path (grey), so we've found a cycle.
            #
            # Build the cycle path: reverse the current path (which has
            # the newest vertex at the head) and append the neighbour
            # (which closes the cycle).
            cycle_path = Enum.reverse([neighbour | path])
            {:halt, {:cycle, cycle_path, cols}}

          :white ->
            # Unvisited neighbour — recurse deeper into the DFS.
            case dfs(neighbour, adjacency, cols, [neighbour | path]) do
              {:cycle, _, _} = cycle -> {:halt, cycle}
              {:ok, updated} -> {:cont, {:ok, updated}}
            end

          :black ->
            # Already fully explored — no cycle possible through this
            # vertex. This is a cross edge or forward edge, both safe.
            {:cont, {:ok, cols}}
        end
      end)

    case result do
      {:ok, colours_after} ->
        # All neighbours explored without finding a cycle.
        # Mark this vertex as black (fully explored).
        {:ok, Map.put(colours_after, vertex, :black)}

      {:cycle, _, _} = cycle ->
        # Propagate the cycle detection upward without modifying colours.
        cycle
    end
  end

  # Build an adjacency map from the list of Dependency structs.
  #
  # Converts the edge list into a map of {source_id => [target_id, ...]}
  # for O(1) neighbour lookup during DFS. Without this pre-processing,
  # finding neighbours would require scanning the full edge list for
  # each vertex.
  #
  # The Dependency struct has `.from` and `.to` fields representing
  # the source and target of a dependency edge. In HAR's dependency
  # model, `.from` depends on `.to` (i.e., .from requires .to to
  # complete first). The adjacency map follows the DEPENDENCY direction:
  # from → to, meaning "from depends on to".
  defp build_adjacency_map(edges) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      source = edge_source(edge)
      target = edge_target(edge)
      Map.update(acc, source, [target], &[target | &1])
    end)
  end

  # Extract the unique identifier from a vertex (Operation struct).
  #
  # Operations use the `.id` field as their unique identifier (a UUID
  # string generated by `Operation.new/3`). The fallback to `.name` and
  # `inspect/1` handles edge cases where the graph contains non-standard
  # vertex types (e.g., during testing with plain maps).
  defp vertex_id(vertex) when is_map(vertex) do
    Map.get(vertex, :id) || Map.get(vertex, :name) || inspect(vertex)
  end

  defp vertex_id(vertex), do: to_string(vertex)

  # Extract the source vertex ID from a Dependency struct.
  #
  # HAR's Dependency struct uses `.from` for the source. The tuple
  # fallback handles the case where edges are represented as simple
  # `{source, target}` tuples (e.g., in unit tests).
  defp edge_source(%{from: from}), do: from
  defp edge_source(%{source: source}), do: source
  defp edge_source({source, _target}), do: source

  # Extract the target vertex ID from a Dependency struct.
  #
  # HAR's Dependency struct uses `.to` for the target. The tuple
  # fallback handles the case where edges are represented as simple
  # `{source, target}` tuples (e.g., in unit tests).
  defp edge_target(%{to: to}), do: to
  defp edge_target(%{target: target}), do: target
  defp edge_target({_source, target}), do: target
end
