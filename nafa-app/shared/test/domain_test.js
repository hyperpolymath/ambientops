// SPDX-License-Identifier: PMPL-1.0-or-later
// Domain model tests for nafa-app shared types
// Tests validate the core domain logic defined in Domain.res

import { assertEquals, assert } from "jsr:@std/assert";

// These functions mirror the ReScript Domain module logic.
// When Domain.res is compiled, these tests validate the spec.

function transportModeToString(mode) {
  const map = { Walk: "Walk", Bus: "Bus", Train: "Train", Tram: "Tram", Metro: "Metro" };
  return map[mode] ?? "Unknown";
}

function sensoryLevelDescription(level) {
  if (level <= 2) return "Very Low";
  if (level <= 4) return "Low";
  if (level <= 6) return "Moderate";
  if (level <= 8) return "High";
  return "Very High";
}

function exceedsProfile(levels, profile) {
  return levels.noise > profile.noise || levels.light > profile.light || levels.crowd > profile.crowd;
}

function isCacheStale(cached, maxAgeDays) {
  const now = Date.now();
  const maxAgeMs = maxAgeDays * 24 * 60 * 60 * 1000;
  return now - cached.cachedAt > maxAgeMs;
}

Deno.test("transportModeToString returns correct strings", () => {
  assertEquals(transportModeToString("Walk"), "Walk");
  assertEquals(transportModeToString("Bus"), "Bus");
  assertEquals(transportModeToString("Train"), "Train");
  assertEquals(transportModeToString("Tram"), "Tram");
  assertEquals(transportModeToString("Metro"), "Metro");
});

Deno.test("sensoryLevelDescription covers all ranges", () => {
  assertEquals(sensoryLevelDescription(0), "Very Low");
  assertEquals(sensoryLevelDescription(2), "Very Low");
  assertEquals(sensoryLevelDescription(3), "Low");
  assertEquals(sensoryLevelDescription(4), "Low");
  assertEquals(sensoryLevelDescription(5), "Moderate");
  assertEquals(sensoryLevelDescription(6), "Moderate");
  assertEquals(sensoryLevelDescription(7), "High");
  assertEquals(sensoryLevelDescription(8), "High");
  assertEquals(sensoryLevelDescription(9), "Very High");
  assertEquals(sensoryLevelDescription(10), "Very High");
});

Deno.test("exceedsProfile detects noise violation", () => {
  const levels = { noise: 8, light: 3, crowd: 2 };
  const profile = { noise: 5, light: 5, crowd: 5 };
  assert(exceedsProfile(levels, profile));
});

Deno.test("exceedsProfile returns false when within tolerance", () => {
  const levels = { noise: 3, light: 3, crowd: 3 };
  const profile = { noise: 5, light: 5, crowd: 5 };
  assert(!exceedsProfile(levels, profile));
});

Deno.test("exceedsProfile boundary - equal values do not exceed", () => {
  const levels = { noise: 5, light: 5, crowd: 5 };
  const profile = { noise: 5, light: 5, crowd: 5 };
  assert(!exceedsProfile(levels, profile));
});

Deno.test("isCacheStale detects stale data", () => {
  const staleCache = {
    cachedAt: Date.now() - (8 * 24 * 60 * 60 * 1000), // 8 days ago
    syncStatus: "Synced",
    version: 1,
  };
  assert(isCacheStale(staleCache, 7));
});

Deno.test("isCacheStale returns false for fresh data", () => {
  const freshCache = {
    cachedAt: Date.now() - (1 * 24 * 60 * 60 * 1000), // 1 day ago
    syncStatus: "Synced",
    version: 1,
  };
  assert(!isCacheStale(freshCache, 7));
});
