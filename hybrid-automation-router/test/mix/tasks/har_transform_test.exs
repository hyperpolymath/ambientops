# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Mix.Tasks.Har.TransformTest do
  @moduledoc """
  Tests for the mix har.transform task.

  Verifies that the task can load a serialised HAR semantic graph from
  a JSON file and transform it to the specified target IaC format.
  Also tests help text, missing file handling, and the --output flag.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.HealthChecker

  @project_root Path.expand("../../..", __DIR__)

  setup do
    # Ensure application dependencies are started
    Application.ensure_all_started(:yaml_elixir)

    # Register all backends from the routing table as healthy
    routes = HAR.ControlPlane.RoutingTable.get_routes()

    for route <- routes, backend <- route.backends do
      HealthChecker.register_backend(backend)
      HealthChecker.set_health(backend, :healthy)
    end

    Process.sleep(50)

    # Create a temporary directory for test fixtures and output
    tmp_dir = Path.join(System.tmp_dir!(), "har_transform_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    # Generate a valid graph JSON fixture by parsing the Ansible example
    graph_json = create_graph_fixture(tmp_dir)

    %{tmp_dir: tmp_dir, graph_json: graph_json}
  end

  # ------------------------------------------------------------------
  # Help and no-argument cases
  # ------------------------------------------------------------------

  describe "help and no-args" do
    test "displays help when --help flag is given" do
      assert catch_exit(Mix.Tasks.Har.Transform.run(["--help"])) == :normal
    end

    test "displays help when no arguments given" do
      assert catch_exit(Mix.Tasks.Har.Transform.run([])) == :normal
    end

    test "displays help when --to is missing", %{graph_json: graph_json} do
      assert catch_exit(Mix.Tasks.Har.Transform.run([graph_json])) == :normal
    end
  end

  # ------------------------------------------------------------------
  # File not found
  # ------------------------------------------------------------------

  describe "file not found" do
    test "raises Mix.Error for non-existent file" do
      assert_raise Mix.Error, ~r/File not found/, fn ->
        Mix.Tasks.Har.Transform.run(["nonexistent_graph.json", "--to", "salt"])
      end
    end
  end

  # ------------------------------------------------------------------
  # Successful transformations
  # ------------------------------------------------------------------

  describe "successful transformations" do
    test "transforms graph JSON to Salt format", %{graph_json: graph_json} do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Transform.run([graph_json, "--to", "salt"])
        end)

      assert output =~ "Successfully transformed to salt"
    end

    test "transforms graph JSON to Ansible format", %{graph_json: graph_json} do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Transform.run([graph_json, "--to", "ansible"])
        end)

      assert output =~ "Successfully transformed to ansible"
    end

    test "transforms graph JSON to Terraform format", %{graph_json: graph_json} do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Transform.run([graph_json, "--to", "terraform"])
        end)

      assert output =~ "Successfully transformed to terraform"
    end
  end

  # ------------------------------------------------------------------
  # Output to file
  # ------------------------------------------------------------------

  describe "output to file" do
    test "writes Salt output to specified file", %{tmp_dir: tmp_dir, graph_json: graph_json} do
      output_path = Path.join(tmp_dir, "output.sls")

      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Har.Transform.run([
          graph_json,
          "--to",
          "salt",
          "--output",
          output_path
        ])
      end)

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert byte_size(content) > 0
    end

    test "writes Ansible output to specified file", %{tmp_dir: tmp_dir, graph_json: graph_json} do
      output_path = Path.join(tmp_dir, "playbook.yml")

      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Har.Transform.run([
          graph_json,
          "--to",
          "ansible",
          "--output",
          output_path
        ])
      end)

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert byte_size(content) > 0
    end
  end

  # ------------------------------------------------------------------
  # Helper to create a graph JSON fixture from the Ansible example
  # ------------------------------------------------------------------

  defp create_graph_fixture(tmp_dir) do
    ansible_path = Path.join(@project_root, "examples/ansible/webserver.yml")
    content = File.read!(ansible_path)

    {:ok, graph} = HAR.DataPlane.Parser.parse(:ansible, content)

    json_data =
      %{
        vertices:
          Enum.map(graph.vertices, fn op ->
            %{
              id: op.id,
              type: Atom.to_string(op.type),
              params: stringify_keys(op.params),
              target: stringify_keys(op.target),
              metadata: stringify_keys(op.metadata)
            }
          end),
        edges:
          Enum.map(graph.edges, fn dep ->
            %{
              from: dep.from,
              to: dep.to,
              type: Atom.to_string(dep.type),
              metadata: stringify_keys(dep.metadata)
            }
          end),
        metadata: stringify_keys(graph.metadata)
      }
      |> Jason.encode!(pretty: true)

    fixture_path = Path.join(tmp_dir, "graph.json")
    File.write!(fixture_path, json_data)
    fixture_path
  end

  defp stringify_keys(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp stringify_keys(%Date{} = d), do: Date.to_iso8601(d)
  defp stringify_keys(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)

  defp stringify_keys(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> stringify_keys()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp stringify_keys(other), do: other
end
