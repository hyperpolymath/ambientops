# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.TransformerDispatchTest do
  @moduledoc """
  Tests for the HAR.DataPlane.Transformer dispatch module.

  Verifies that `transform/2` correctly routes to the format-specific
  transformer for every supported target, handles RoutingPlan input by
  extracting the embedded graph, and returns descriptive errors for
  unsupported targets and missing options.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.Transformer
  alias HAR.ControlPlane.RoutingPlan
  alias HAR.Semantic.{Graph, Operation}

  # All nine supported target formats.
  @supported_targets [
    :ansible,
    :salt,
    :terraform,
    :puppet,
    :chef,
    :kubernetes,
    :docker_compose,
    :cloudformation,
    :pulumi
  ]

  describe "transform/2 - supported targets from Graph" do
    for target <- [
          :ansible,
          :salt,
          :terraform,
          :puppet,
          :chef,
          :kubernetes,
          :docker_compose,
          :cloudformation,
          :pulumi
        ] do
      @tag target: target
      test "transforms graph to #{target} format", %{} do
        graph = build_graph()

        assert {:ok, output} = Transformer.transform(graph, to: unquote(target))
        assert output != nil
      end
    end
  end

  describe "transform/2 - unsupported target" do
    test "returns error tuple for unknown target atom" do
      graph = build_graph()

      assert {:error, {:unsupported_target, :unknown}} =
               Transformer.transform(graph, to: :unknown)
    end
  end

  describe "transform/2 - RoutingPlan input" do
    test "extracts graph from RoutingPlan and transforms" do
      graph = build_graph()

      plan = %RoutingPlan{
        graph: graph,
        decisions: [],
        target: :salt,
        metadata: %{}
      }

      assert {:ok, output} = Transformer.transform(plan, to: :salt)
      assert output != nil
    end
  end

  describe "transform/2 - missing :to option" do
    test "raises KeyError when :to option is absent" do
      graph = build_graph()

      assert_raise KeyError, fn ->
        Transformer.transform(graph, [])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Test Helpers
  # ---------------------------------------------------------------------------

  # Build a minimal semantic graph containing a single package_install
  # operation. This is sufficient for all dispatch-level tests since we
  # are verifying routing, not transformer output fidelity.
  defp build_graph do
    Graph.new(
      vertices: [Operation.new(:package_install, %{package: "nginx"})],
      edges: [],
      metadata: %{source: :test}
    )
  end
end
