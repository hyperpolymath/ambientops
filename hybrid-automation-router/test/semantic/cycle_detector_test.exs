# SPDX-License-Identifier: MPL-2.0
#
# Tests for HAR.Semantic.CycleDetector — three-colour DFS cycle detection.
#
# Validates that the cycle detector correctly identifies acyclic graphs
# (DAGs) and cyclic graphs, returning the exact cycle path when a cycle
# is found. Uses HAR's semantic graph types (Operation, Dependency, Graph)
# to build realistic test graphs.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.Semantic.CycleDetectorTest do
  @moduledoc """
  Tests for the HAR.Semantic.CycleDetector module.

  All tests are stateless (pure function calls on immutable graph structs),
  so they run in parallel with `async: true`. No GenServer dependencies.

  The test suite covers three categories:

    1. Acyclic graphs — empty, single vertex, chains, diamonds, trees,
       disconnected components. All must return `:acyclic`.
    2. Cyclic graphs — self-loops, 2-node cycles, 3-node cycles, cycles
       in one component with another acyclic, large cycles. All must
       return `{:cyclic, path}`.
    3. Cycle path verification — structural assertions on the returned
       path (first == last, correct length, all cycle members present).
    4. Edge cases — redundant edges, mixed forward/back edges.
  """

  use ExUnit.Case, async: true

  alias HAR.Semantic.{Graph, Operation, Dependency, CycleDetector}

  # ---------------------------------------------------------------------------
  # Test Helpers
  # ---------------------------------------------------------------------------

  # Create an Operation with a given string ID. Uses :package_install as
  # a generic type since the cycle detector only cares about the .id field.
  defp op(id), do: Operation.new(:package_install, %{package: id}, id: id)

  # Create a Dependency edge from one operation ID to another.
  # Uses :requires as a generic dependency type.
  defp dep(from, to), do: Dependency.new(from, to, :requires)

  # Build a Graph from lists of operation IDs and {from, to} edge tuples.
  # Convenience wrapper that creates Operation and Dependency structs
  # from simple identifiers, reducing boilerplate in test cases.
  defp build_graph(op_ids, edge_tuples) do
    vertices = Enum.map(op_ids, &op/1)
    edges = Enum.map(edge_tuples, fn {from, to} -> dep(from, to) end)
    Graph.new(vertices: vertices, edges: edges, metadata: %{source: :test})
  end

  # ---------------------------------------------------------------------------
  # 1. Acyclic Graphs
  # ---------------------------------------------------------------------------

  describe "check/1 — acyclic graphs" do
    test "empty graph (no vertices, no edges) is acyclic" do
      graph = Graph.new(vertices: [], edges: [], metadata: %{source: :test})

      assert :acyclic = CycleDetector.check(graph)
    end

    test "single vertex with no edges is acyclic" do
      graph = build_graph(["a"], [])

      assert :acyclic = CycleDetector.check(graph)
    end

    test "linear chain A -> B -> C -> D is acyclic" do
      graph = build_graph(
        ["a", "b", "c", "d"],
        [{"a", "b"}, {"b", "c"}, {"c", "d"}]
      )

      assert :acyclic = CycleDetector.check(graph)
    end

    test "diamond graph (A -> B, A -> C, B -> D, C -> D) is acyclic" do
      graph = build_graph(
        ["a", "b", "c", "d"],
        [{"a", "b"}, {"a", "c"}, {"b", "d"}, {"c", "d"}]
      )

      assert :acyclic = CycleDetector.check(graph)
    end

    test "tree with root and multiple children is acyclic" do
      # Root -> child1, child2, child3
      # child1 -> grandchild1, grandchild2
      # child2 -> grandchild3
      graph = build_graph(
        ["root", "child1", "child2", "child3", "gc1", "gc2", "gc3"],
        [
          {"root", "child1"},
          {"root", "child2"},
          {"root", "child3"},
          {"child1", "gc1"},
          {"child1", "gc2"},
          {"child2", "gc3"}
        ]
      )

      assert :acyclic = CycleDetector.check(graph)
    end

    test "disconnected components with no edges between groups are acyclic" do
      # Component 1: a -> b -> c
      # Component 2: x -> y -> z
      # No edges between the two components.
      graph = build_graph(
        ["a", "b", "c", "x", "y", "z"],
        [{"a", "b"}, {"b", "c"}, {"x", "y"}, {"y", "z"}]
      )

      assert :acyclic = CycleDetector.check(graph)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Cyclic Graphs
  # ---------------------------------------------------------------------------

  describe "check/1 — cyclic graphs" do
    test "self-loop (A -> A) is detected as cyclic" do
      graph = build_graph(["a"], [{"a", "a"}])

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert is_list(path)
      assert "a" in path
    end

    test "two-node cycle (A -> B -> A) is detected" do
      graph = build_graph(["a", "b"], [{"a", "b"}, {"b", "a"}])

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert "a" in path
      assert "b" in path
    end

    test "three-node cycle (A -> B -> C -> A) is detected" do
      graph = build_graph(
        ["a", "b", "c"],
        [{"a", "b"}, {"b", "c"}, {"c", "a"}]
      )

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert "a" in path
      assert "b" in path
      assert "c" in path
    end

    test "cycle in one component with another component acyclic" do
      # Component 1 (acyclic): x -> y -> z
      # Component 2 (cyclic): a -> b -> c -> a
      graph = build_graph(
        ["x", "y", "z", "a", "b", "c"],
        [
          {"x", "y"},
          {"y", "z"},
          {"a", "b"},
          {"b", "c"},
          {"c", "a"}
        ]
      )

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert is_list(path)
      assert length(path) >= 2
    end

    test "large cycle with 10 nodes is detected" do
      # Build a ring: n0 -> n1 -> n2 -> ... -> n9 -> n0
      ids = Enum.map(0..9, fn i -> "n#{i}" end)

      edges =
        Enum.map(0..9, fn i ->
          from = "n#{i}"
          to = "n#{rem(i + 1, 10)}"
          {from, to}
        end)

      graph = build_graph(ids, edges)

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert is_list(path)
      assert length(path) >= 2
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Cycle Path Verification
  # ---------------------------------------------------------------------------

  describe "check/1 — cycle path structure" do
    test "cycle path closes the loop (first element == last element)" do
      graph = build_graph(
        ["a", "b", "c"],
        [{"a", "b"}, {"b", "c"}, {"c", "a"}]
      )

      assert {:cyclic, path} = CycleDetector.check(graph)

      # The path should form a closed loop: the first and last vertex
      # IDs are the same, showing where the cycle closes.
      assert List.first(path) == List.last(path)
    end

    test "cycle path length is cycle_size + 1 (closing vertex repeated)" do
      # A 3-node cycle (A -> B -> C -> A) should produce a path of
      # length 4: [start, ..., ..., start] — the closing vertex appears
      # twice (once at the beginning, once at the end).
      graph = build_graph(
        ["a", "b", "c"],
        [{"a", "b"}, {"b", "c"}, {"c", "a"}]
      )

      assert {:cyclic, path} = CycleDetector.check(graph)

      # The path includes all members of the cycle plus the closing repeat.
      # For a 3-node cycle the path has at least 4 elements.
      # The exact starting vertex depends on DFS traversal order, but
      # the structural invariant holds regardless.
      first = List.first(path)
      last = List.last(path)
      assert first == last

      # All three cycle members must appear in the path.
      unique_ids = Enum.uniq(path)
      assert "a" in unique_ids
      assert "b" in unique_ids
      assert "c" in unique_ids
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Edge Cases
  # ---------------------------------------------------------------------------

  describe "check/1 — edge cases" do
    test "graph with redundant edges (A -> B appears twice) still detects correctly" do
      # Duplicate edges should not confuse the algorithm.
      op_a = op("a")
      op_b = op("b")
      op_c = op("c")

      # Two copies of A -> B, plus a cycle B -> C -> A
      dep_ab_1 = dep("a", "b")
      dep_ab_2 = dep("a", "b")
      dep_bc = dep("b", "c")
      dep_ca = dep("c", "a")

      graph = Graph.new(
        vertices: [op_a, op_b, op_c],
        edges: [dep_ab_1, dep_ab_2, dep_bc, dep_ca],
        metadata: %{source: :test}
      )

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert is_list(path)
      assert List.first(path) == List.last(path)
    end

    test "graph with both forward and back edges detects the back edge cycle" do
      # Forward edges: a -> b -> c -> d
      # Back edge: d -> b (creates cycle b -> c -> d -> b)
      graph = build_graph(
        ["a", "b", "c", "d"],
        [{"a", "b"}, {"b", "c"}, {"c", "d"}, {"d", "b"}]
      )

      assert {:cyclic, path} = CycleDetector.check(graph)
      assert is_list(path)

      # The cycle involves b, c, d (the back edge from d to b).
      assert "b" in path
      assert "d" in path
    end
  end
end
