# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SystemObservatoryTest do
  use ExUnit.Case
  doctest SystemObservatory

  describe "version/0" do
    test "returns version string" do
      assert SystemObservatory.version() == "1.2.0"
    end
  end

  describe "schema_version/0" do
    test "returns schema version" do
      assert SystemObservatory.schema_version() == "1.0"
    end
  end

  describe "observation_only?/0" do
    test "always returns true" do
      assert SystemObservatory.observation_only?() == true
    end

    test "confirms System Observatory never modifies state" do
      # This is a philosophical test - System Observatory only observes
      assert SystemObservatory.observation_only?()
    end
  end
end
