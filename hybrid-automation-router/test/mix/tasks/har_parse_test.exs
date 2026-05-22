# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Mix.Tasks.Har.ParseTest do
  @moduledoc """
  Tests for the mix har.parse task.

  Verifies that the task can parse IaC files into HAR semantic graph
  representation, handles missing files, supports JSON and inspect output
  modes, and respects the --output flag.
  """

  use ExUnit.Case, async: false

  @project_root Path.expand("../../..", __DIR__)
  @example_ansible Path.join(@project_root, "examples/ansible/webserver.yml")
  @example_salt Path.join(@project_root, "examples/salt/webserver.sls")
  @example_terraform Path.join(@project_root, "examples/terraform/webserver.tf")

  setup do
    # Ensure application dependencies are started for parsing
    Application.ensure_all_started(:yaml_elixir)

    # Use a temporary directory for output files
    tmp_dir = Path.join(System.tmp_dir!(), "har_parse_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  # ------------------------------------------------------------------
  # Help and no-argument cases
  # ------------------------------------------------------------------

  describe "help and no-args" do
    test "displays help when --help flag is given" do
      assert catch_exit(Mix.Tasks.Har.Parse.run(["--help"])) == :normal
    end

    test "displays help when no arguments given" do
      assert catch_exit(Mix.Tasks.Har.Parse.run([])) == :normal
    end
  end

  # ------------------------------------------------------------------
  # File not found
  # ------------------------------------------------------------------

  describe "file not found" do
    test "raises Mix.Error for non-existent file" do
      assert_raise Mix.Error, ~r/File not found/, fn ->
        Mix.Tasks.Har.Parse.run(["nonexistent_file.yml"])
      end
    end
  end

  # ------------------------------------------------------------------
  # Successful parses (default JSON output)
  # ------------------------------------------------------------------

  describe "successful parses - JSON output" do
    test "parses Ansible example and outputs JSON" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_ansible])
        end)

      assert output =~ "Successfully parsed"
      # Default output is JSON - should contain graph structure
      assert output =~ "vertices"
    end

    test "parses Salt example" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_salt])
        end)

      assert output =~ "Successfully parsed"
    end

    test "parses Terraform example" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_terraform])
        end)

      assert output =~ "Successfully parsed"
    end

    test "explicit --format flag is respected" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_ansible, "--format", "ansible"])
        end)

      assert output =~ "Successfully parsed"
    end

    test "JSON output is valid JSON" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_ansible])
        end)

      # Extract the JSON portion (between --- Semantic Graph --- and "Successfully parsed")
      json_part =
        output
        |> String.split("--- Semantic Graph ---")
        |> List.last()
        |> String.split("Successfully parsed")
        |> List.first()
        |> String.trim()

      assert {:ok, decoded} = Jason.decode(json_part)
      assert is_map(decoded)
      assert Map.has_key?(decoded, "vertices")
      assert Map.has_key?(decoded, "edges")
      assert Map.has_key?(decoded, "metadata")
    end
  end

  # ------------------------------------------------------------------
  # Inspect output mode
  # ------------------------------------------------------------------

  describe "inspect output mode" do
    test "parses with --inspect flag outputs Elixir format" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_ansible, "--inspect"])
        end)

      assert output =~ "Successfully parsed"
      # Inspect format shows Elixir struct notation
      assert output =~ "%HAR.Semantic.Graph{"
    end
  end

  # ------------------------------------------------------------------
  # Output to file
  # ------------------------------------------------------------------

  describe "output to file" do
    test "writes JSON output to specified file", %{tmp_dir: tmp_dir} do
      output_path = Path.join(tmp_dir, "graph.json")

      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Har.Parse.run([
          @example_ansible,
          "--output",
          output_path
        ])
      end)

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert {:ok, _} = Jason.decode(content)
    end

    test "writes inspect output to specified file", %{tmp_dir: tmp_dir} do
      output_path = Path.join(tmp_dir, "graph.txt")

      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Har.Parse.run([
          @example_ansible,
          "--output",
          output_path,
          "--inspect"
        ])
      end)

      assert File.exists?(output_path)
      content = File.read!(output_path)
      assert content =~ "%HAR.Semantic.Graph{"
    end
  end

  # ------------------------------------------------------------------
  # Format auto-detection
  # ------------------------------------------------------------------

  describe "format auto-detection" do
    test "auto-detects Ansible from .yml extension" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_ansible])
        end)

      assert output =~ "Successfully parsed"
      assert output =~ "ansible"
    end

    test "auto-detects Salt from .sls extension" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_salt])
        end)

      assert output =~ "Successfully parsed"
      assert output =~ "salt"
    end

    test "auto-detects Terraform from .tf extension" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Parse.run([@example_terraform])
        end)

      assert output =~ "Successfully parsed"
      assert output =~ "terraform"
    end
  end
end
