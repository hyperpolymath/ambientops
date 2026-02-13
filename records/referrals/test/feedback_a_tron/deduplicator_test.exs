# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.DeduplicatorTest do
  use ExUnit.Case, async: false

  alias FeedbackATron.Deduplicator

  setup do
    # GenServer is already started by the application supervision tree.
    # Clean state between tests.
    Deduplicator.clear()
    :ok
  end

  test "new submission is not flagged as duplicate" do
    result = Deduplicator.check(%{title: "Bug in login page", body: "Login fails on Chrome"})
    assert match?({:ok, :unique}, result)
  end

  test "recording and checking identical submission detects duplicate" do
    submission = %{title: "Bug in login page", body: "Login fails on Chrome"}
    Deduplicator.record(submission, :github, :success)
    _ = Deduplicator.stats()  # sync barrier — ensure cast is processed
    result = Deduplicator.check(submission)
    assert match?({:duplicate, _}, result)
  end

  test "different submissions are not detected as duplicates" do
    Deduplicator.record(%{title: "Bug A", body: "Description A"}, :github, :success)
    _ = Deduplicator.stats()  # sync barrier
    result = Deduplicator.check(%{title: "Completely Unrelated Issue", body: "Totally different problem"})
    refute match?({:duplicate, _}, result)
  end

  test "stats returns a map with submission counts" do
    stats = Deduplicator.stats()
    assert is_map(stats)
    assert Map.has_key?(stats, :total_submissions)
    assert Map.has_key?(stats, :unique_hashes)
  end

  test "clear resets deduplication state" do
    Deduplicator.record(%{title: "Test Bug", body: "Test body"}, :github, :success)
    _ = Deduplicator.stats()  # sync barrier
    Deduplicator.clear()
    result = Deduplicator.check(%{title: "Test Bug", body: "Test body"})
    assert match?({:ok, :unique}, result)
  end
end
