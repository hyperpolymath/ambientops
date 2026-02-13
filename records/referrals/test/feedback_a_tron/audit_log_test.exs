# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.AuditLogTest do
  use ExUnit.Case, async: false

  alias FeedbackATron.AuditLog

  # GenServer is already started by the application supervision tree.

  test "audit log process is alive" do
    pid = Process.whereis(AuditLog)
    assert pid != nil
    assert Process.alive?(pid)
  end

  test "stats returns a map" do
    stats = AuditLog.stats()
    assert is_map(stats)
  end

  test "recent returns a list" do
    result = AuditLog.recent(10)
    assert is_list(result)
  end
end
