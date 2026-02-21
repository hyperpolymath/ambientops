# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.Semantic.DependencyTest do
  @moduledoc """
  Tests for the HAR.Semantic.Dependency module.

  Verifies dependency creation, validation, and metadata handling
  for the semantic graph edge representation.
  """

  use ExUnit.Case, async: true

  alias HAR.Semantic.Dependency

  describe "new/4" do
    test "creates a dependency with from, to, and type" do
      dep = Dependency.new("op1", "op2", :requires)

      assert dep.from == "op1"
      assert dep.to == "op2"
      assert dep.type == :requires
      assert dep.metadata == %{}
    end

    test "creates a dependency with sequential type" do
      dep = Dependency.new("step1", "step2", :sequential)

      assert dep.from == "step1"
      assert dep.to == "step2"
      assert dep.type == :sequential
    end

    test "creates a dependency with notifies type" do
      dep = Dependency.new("config", "service", :notifies)

      assert dep.from == "config"
      assert dep.to == "service"
      assert dep.type == :notifies
    end

    test "creates a dependency with watches type" do
      dep = Dependency.new("service", "config", :watches)

      assert dep.from == "service"
      assert dep.to == "config"
      assert dep.type == :watches
    end

    test "creates a dependency with metadata option" do
      metadata = %{reason: "service depends on package", priority: 10}
      dep = Dependency.new("op1", "op2", :requires, metadata: metadata)

      assert dep.metadata == metadata
      assert dep.metadata.reason == "service depends on package"
      assert dep.metadata.priority == 10
    end

    test "creates a dependency with empty metadata by default" do
      dep = Dependency.new("a", "b", :depends_on)
      assert dep.metadata == %{}
    end
  end

  describe "valid?/1" do
    test "returns true for valid dependency (from != to, both binary)" do
      dep = Dependency.new("op1", "op2", :requires)
      assert Dependency.valid?(dep) == true
    end

    test "returns true for different string IDs" do
      dep = Dependency.new("install_nginx", "start_nginx", :sequential)
      assert Dependency.valid?(dep) == true
    end

    test "returns false when from == to (self-referencing)" do
      dep = Dependency.new("op1", "op1", :requires)
      assert Dependency.valid?(dep) == false
    end

    test "returns false for non-binary from ID" do
      dep = %Dependency{from: 123, to: "op2", type: :requires, metadata: %{}}
      assert Dependency.valid?(dep) == false
    end

    test "returns false for non-binary to ID" do
      dep = %Dependency{from: "op1", to: :op2, type: :requires, metadata: %{}}
      assert Dependency.valid?(dep) == false
    end

    test "returns false for nil IDs" do
      dep = %Dependency{from: nil, to: nil, type: :requires, metadata: %{}}
      assert Dependency.valid?(dep) == false
    end

    test "returns false for non-struct input" do
      assert Dependency.valid?(%{from: "a", to: "b"}) == false
    end

    test "returns false for nil input" do
      assert Dependency.valid?(nil) == false
    end
  end
end
