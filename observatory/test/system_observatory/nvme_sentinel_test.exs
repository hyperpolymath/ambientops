# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.NvmeSentinelTest do
  use ExUnit.Case, async: false

  alias SystemObservatory.NvmeSentinel

  describe "weather_category/0" do
    test "returns calm when no devices monitored" do
      # Start sentinel with polling disabled (no real hardware needed)
      start_supervised!({NvmeSentinel, enabled: false, devices: []})

      category = NvmeSentinel.weather_category()

      assert category["state"] == "calm"
      assert category["summary"] =~ "No NVMe"
    end
  end

  describe "health_snapshot/0" do
    test "returns empty map when no devices polled" do
      start_supervised!({NvmeSentinel, enabled: false, devices: []})

      assert %{} = NvmeSentinel.health_snapshot()
    end
  end

  describe "SMART JSON parsing" do
    test "extracts temperature from smartctl JSON" do
      # Simulate smartctl JSON output
      json = Jason.encode!(%{
        "temperature" => %{"current" => 42},
        "nvme_smart_health_information_log" => %{
          "available_spare" => 100,
          "media_errors" => 0,
          "unsafe_shutdowns" => 5
        }
      })

      # Write to a temp script that echoes this JSON
      tmp_dir = System.tmp_dir!()
      script_path = Path.join(tmp_dir, "fake_smartctl_#{:rand.uniform(100_000)}.sh")

      File.write!(script_path, """
      #!/bin/sh
      echo '#{json}'
      """)

      File.chmod!(script_path, 0o755)

      assert {:ok, 42} = NvmeSentinel.read_smart_attribute(script_path, "/dev/fake", "temperature")
      assert {:ok, 100} = NvmeSentinel.read_smart_attribute(script_path, "/dev/fake", "available_spare")
      assert {:ok, 0} = NvmeSentinel.read_smart_attribute(script_path, "/dev/fake", "media_errors")
      assert {:ok, 5} = NvmeSentinel.read_smart_attribute(script_path, "/dev/fake", "unsafe_shutdowns")

      File.rm!(script_path)
    end

    test "returns error for missing attributes" do
      json = Jason.encode!(%{"temperature" => %{}})
      tmp_dir = System.tmp_dir!()
      script_path = Path.join(tmp_dir, "fake_smartctl_empty_#{:rand.uniform(100_000)}.sh")

      File.write!(script_path, """
      #!/bin/sh
      echo '#{json}'
      """)

      File.chmod!(script_path, 0o755)

      assert {:error, :attribute_not_found} =
               NvmeSentinel.read_smart_attribute(script_path, "/dev/fake", "available_spare")

      File.rm!(script_path)
    end
  end
end
