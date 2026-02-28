# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Mix.Tasks.Har.ConvertTest do
  @moduledoc """
  Tests for the mix har.convert task.

  Verifies that the task can convert between supported IaC formats,
  handles missing files, respects --output flags, and displays help
  text when invoked with --help or no arguments.
  """

  use ExUnit.Case, async: false

  alias HAR.ControlPlane.HealthChecker

  @project_root Path.expand("../../..", __DIR__)
  @example_ansible Path.join(@project_root, "examples/ansible/webserver.yml")
  @example_salt Path.join(@project_root, "examples/salt/webserver.sls")
  @example_terraform Path.join(@project_root, "examples/terraform/webserver.tf")

  setup do
    # Ensure application dependencies are started for parsing
    Application.ensure_all_started(:yaml_elixir)

    # Register all backends from the routing table as healthy
    routes = HAR.ControlPlane.RoutingTable.get_routes()

    for route <- routes, backend <- route.backends do
      HealthChecker.register_backend(backend)
      HealthChecker.set_health(backend, :healthy)
    end

    Process.sleep(50)

    # Use a temporary directory for output files
    tmp_dir = Path.join(System.tmp_dir!(), "har_convert_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  # ------------------------------------------------------------------
  # Help and no-argument cases
  # ------------------------------------------------------------------

  describe "help and no-args" do
    test "displays help when --help flag is given" do
      # --help triggers an exit(:normal) so we catch the exit
      assert catch_exit(Mix.Tasks.Har.Convert.run(["--help"])) == :normal
    end

    test "displays help when no arguments given" do
      assert catch_exit(Mix.Tasks.Har.Convert.run([])) == :normal
    end

    test "displays help when --to is missing" do
      assert catch_exit(Mix.Tasks.Har.Convert.run([@example_ansible])) == :normal
    end
  end

  # ------------------------------------------------------------------
  # File not found
  # ------------------------------------------------------------------

  describe "file not found" do
    test "raises Mix.Error for non-existent file" do
      assert_raise Mix.Error, ~r/File not found/, fn ->
        Mix.Tasks.Har.Convert.run(["nonexistent_file.yml", "--to", "salt"])
      end
    end
  end

  # ------------------------------------------------------------------
  # Successful conversions (stdout output)
  # ------------------------------------------------------------------

  describe "successful conversions" do
    test "converts Ansible example to Salt" do
      # Capture IO to verify the task prints output
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_ansible, "--to", "salt"])
        end)

      assert output =~ "Successfully converted"
    end

    test "converts Ansible example to Terraform" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_ansible, "--to", "terraform"])
        end)

      assert output =~ "Successfully converted"
    end

    test "converts Salt example to Ansible" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_salt, "--to", "ansible"])
        end)

      assert output =~ "Successfully converted"
    end

    test "accepts explicit --from format" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_ansible, "--from", "ansible", "--to", "salt"])
        end)

      assert output =~ "Successfully converted"
    end

    test "verbose mode prints extra information" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([
            @example_ansible,
            "--to",
            "salt",
            "--verbose"
          ])
        end)

      assert output =~ "Converting"
      assert output =~ "Source format:"
      assert output =~ "Target format:"
    end
  end

  # ------------------------------------------------------------------
  # Output to file
  # ------------------------------------------------------------------

  describe "output to file" do
    test "writes output to specified file", %{tmp_dir: tmp_dir} do
      output_path = Path.join(tmp_dir, "output.sls")

      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Har.Convert.run([
          @example_ansible,
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
  end

  # ------------------------------------------------------------------
  # Format auto-detection
  # ------------------------------------------------------------------

  describe "format auto-detection" do
    test "auto-detects Ansible from .yml extension" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_ansible, "--to", "salt"])
        end)

      assert output =~ "Successfully converted"
    end

    test "auto-detects Salt from .sls extension" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_salt, "--to", "ansible"])
        end)

      assert output =~ "Successfully converted"
    end

    test "auto-detects Terraform from .tf extension" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.Har.Convert.run([@example_terraform, "--to", "ansible"])
        end)

      assert output =~ "Successfully converted"
    end
  end
end
