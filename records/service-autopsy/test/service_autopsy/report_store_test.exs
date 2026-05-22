# SPDX-License-Identifier: MPL-2.0

defmodule ServiceAutopsy.ReportStoreTest do
  use ExUnit.Case, async: true

  alias ServiceAutopsy.ReportStore

  setup do
    # Start a fresh store for each test
    start_supervised!(ReportStore)
    :ok
  end

  test "stores and retrieves reports" do
    report = %{
      "envelope_id" => "test-001",
      "subject" => %{"name" => "sshd.service"}
    }

    ReportStore.store(report)

    assert [^report] = ReportStore.all()
  end

  test "recent/1 returns most recent N reports" do
    for i <- 1..5 do
      ReportStore.store(%{"envelope_id" => "test-#{i}"})
    end

    # Give casts time to process
    :timer.sleep(50)

    recent = ReportStore.recent(3)
    assert length(recent) == 3
    # Most recent first
    assert hd(recent)["envelope_id"] == "test-5"
  end

  test "get/1 finds report by envelope_id" do
    report = %{"envelope_id" => "findme-001", "data" => "test"}
    ReportStore.store(report)
    :timer.sleep(50)

    assert %{"envelope_id" => "findme-001"} = ReportStore.get("findme-001")
    assert nil == ReportStore.get("nonexistent")
  end

  test "for_unit/1 filters by unit name" do
    ReportStore.store(%{"envelope_id" => "a", "subject" => %{"name" => "sshd.service"}})
    ReportStore.store(%{"envelope_id" => "b", "subject" => %{"name" => "nginx.service"}})
    ReportStore.store(%{"envelope_id" => "c", "subject" => %{"name" => "sshd.service"}})
    :timer.sleep(50)

    ssh_reports = ReportStore.for_unit("sshd.service")
    assert length(ssh_reports) == 2
  end

  test "clear/0 removes all reports" do
    ReportStore.store(%{"envelope_id" => "x"})
    :timer.sleep(50)
    assert :ok = ReportStore.clear()
    assert [] = ReportStore.all()
  end
end
