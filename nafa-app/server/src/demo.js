// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

/**
 * NAFA MVP CLI Demo
 *
 * Demonstrates the full MVP including:
 * - Journey planning with sensory-aware segments
 * - Sensory annotation flow
 * - Accessibility settings
 * - Offline mode management
 */

// Domain helpers (matching ReScript types)
const sensoryLevelDescription = (level) => {
  if (level <= 2) return "Very Low";
  if (level <= 4) return "Low";
  if (level <= 6) return "Moderate";
  if (level <= 8) return "High";
  return "Very High";
};

const transportModeEmoji = {
  Walk: "🚶",
  Bus: "🚌",
  Train: "🚆",
  Tram: "🚊",
  Metro: "🚇",
};

const renderSensoryLevel = (label, level) => {
  const filled = "█".repeat(level);
  const empty = "░".repeat(10 - level);
  return `${label}: ${filled}${empty} (${level}/10 - ${sensoryLevelDescription(level)})`;
};

const toggleState = (on) => (on ? "[X]" : "[ ]");

// Sample journey data
const journey = {
  id: "journey-001",
  title: "Morning Commute to Central Library",
  status: "Planning",
  estimatedMinutes: 35,
  segments: [
    {
      id: "seg-1",
      transportMode: "Walk",
      fromLocation: "Home",
      toLocation: "Oak Street Bus Stop",
      durationMinutes: 5,
      sensoryWarning: null,
      sensoryLevels: { noise: 3, light: 5, crowd: 2 },
    },
    {
      id: "seg-2",
      transportMode: "Bus",
      fromLocation: "Oak Street Bus Stop",
      toLocation: "City Center Station",
      durationMinutes: 15,
      sensoryWarning: "Rush hour: expect moderate crowding",
      sensoryLevels: { noise: 6, light: 4, crowd: 7 },
    },
    {
      id: "seg-3",
      transportMode: "Walk",
      fromLocation: "City Center Station",
      toLocation: "Central Library",
      durationMinutes: 8,
      sensoryWarning: "Construction noise on Main Street",
      sensoryLevels: { noise: 8, light: 6, crowd: 5 },
    },
  ],
  sensoryAnnotations: [
    {
      id: "ann-1",
      locationId: "city-center-station",
      locationName: "City Center Station",
      noise: 7,
      light: 5,
      crowd: 8,
      notes: "Very busy during morning rush, quieter after 9am",
      timestamp: Date.now(),
    },
  ],
};

// Accessibility preferences (matching ReScript types)
const accessibilityPrefs = {
  textSize: "Large",
  contrastMode: "HighContrast",
  motionPreference: "Reduced",
  screenReaderVerbosity: "Standard",
  hapticFeedback: "Standard",
  reduceTransparency: false,
  boldText: true,
  monoAudio: false,
};

// Offline mode state (matching ReScript types)
const offlineState = {
  connectivity: "Online",
  prefs: {
    enableOfflineMode: true,
    autoSync: true,
    syncOnWifiOnly: false,
    maxCacheAgeDays: 7,
    prefetchUpcomingJourneys: true,
  },
  stats: {
    journeysCached: 3,
    annotationsCached: 12,
    pendingUploads: 0,
    lastSyncAt: Date.now() - 3600000,
    storageBytesUsed: 256000,
  },
};

// Demo flow
console.log(`
╔══════════════════════════════════════════════════════════════╗
║              NAFA MVP DEMO - Full Feature Set                ║
║     Neurodiverse App for Adventurers                         ║
╚══════════════════════════════════════════════════════════════╝

This demo shows all MVP features:
  1. Journey Plan View - sensory-aware route segments
  2. Sensory Annotation Flow - crowdsourced location data
  3. Accessibility Settings - customizable display & interaction
  4. Offline Mode - works without internet connection

═══════════════════════════════════════════════════════════════

`);

// Wait function for pacing
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function runDemo() {
  // Step 1: Show Journey Plan
  console.log("📍 STEP 1: Journey Plan View\n");
  console.log("════════════════════════════════════════");
  console.log(`🗺️  JOURNEY: ${journey.title}`);
  console.log("════════════════════════════════════════");
  console.log(`Status: 📋 ${journey.status}`);
  console.log(`Estimated Time: ${journey.estimatedMinutes} minutes\n`);
  console.log("ROUTE SEGMENTS:\n");

  for (const segment of journey.segments) {
    const emoji = transportModeEmoji[segment.transportMode];
    console.log(`  ${emoji} ${segment.transportMode}`);
    console.log("  ────────────────────────────────────");
    console.log(`  From: ${segment.fromLocation}`);
    console.log(`  To:   ${segment.toLocation}`);
    console.log(`  Duration: ${segment.durationMinutes} minutes`);

    if (segment.sensoryWarning) {
      console.log(`    ⚠️  ${segment.sensoryWarning}`);
    }

    if (segment.sensoryLevels) {
      console.log("    Sensory Levels:");
      console.log(`      ${renderSensoryLevel("Noise", segment.sensoryLevels.noise)}`);
      console.log(`      ${renderSensoryLevel("Light", segment.sensoryLevels.light)}`);
      console.log(`      ${renderSensoryLevel("Crowd", segment.sensoryLevels.crowd)}`);
    }
    console.log("");
  }

  await wait(500);

  // Step 2: Show existing annotations
  console.log("\n📝 SENSORY ANNOTATIONS (Community Contributed)");
  console.log("════════════════════════════════════════\n");

  for (const ann of journey.sensoryAnnotations) {
    console.log(`  📍 ${ann.locationName}`);
    console.log(`      Noise: ${ann.noise}/10 | Light: ${ann.light}/10 | Crowd: ${ann.crowd}/10`);
    if (ann.notes) {
      console.log(`      Notes: ${ann.notes}`);
    }
    console.log("");
  }

  await wait(500);

  // Step 3: Show annotation flow
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("📍 STEP 2: Sensory Annotation Flow\n");
  console.log("Demonstrating how users contribute sensory data...\n");

  const annotationForm = {
    locationId: "oak-street-stop",
    locationName: "Oak Street Bus Stop",
    noise: 4,
    light: 6,
    crowd: 3,
    notes: "",
  };

  console.log("════════════════════════════════════════");
  console.log("📝 SENSORY ANNOTATION");
  console.log("════════════════════════════════════════");
  console.log(`Location: ${annotationForm.locationName}\n`);
  console.log("Rate the sensory environment at this location:\n");
  console.log(`🔊 ${renderSensoryLevel("Noise Level", annotationForm.noise)}`);
  console.log("   (0 = Silent, 10 = Very Loud)\n");
  console.log(`💡 ${renderSensoryLevel("Light Level", annotationForm.light)}`);
  console.log("   (0 = Very Dark, 10 = Very Bright)\n");
  console.log(`👥 ${renderSensoryLevel("Crowd Level", annotationForm.crowd)}`);
  console.log("   (0 = Empty, 10 = Very Crowded)\n");

  await wait(500);

  // Simulate user adjusting values
  console.log("\n[User adjusts: Noise +1, adds notes]\n");
  annotationForm.noise = 5;
  annotationForm.notes = "Sheltered stop, moderate traffic noise from street";

  console.log(`🔊 ${renderSensoryLevel("Noise Level", annotationForm.noise)}`);
  console.log(`📝 Notes: ${annotationForm.notes}\n`);

  await wait(500);

  // Submit
  console.log("[User submits annotation]\n");
  console.log("════════════════════════════════════════");
  console.log("✅ ANNOTATION SAVED");
  console.log("════════════════════════════════════════\n");
  console.log(`Thank you for contributing sensory data for:`);
  console.log(`📍 ${annotationForm.locationName}\n`);
  console.log("Your annotation helps other neurodiverse travelers");
  console.log("prepare for their journeys.\n");

  await wait(300);

  // Step 3: Accessibility Settings
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("♿ STEP 3: Accessibility Settings\n");
  console.log("Customize NAFA for your needs...\n");

  console.log("════════════════════════════════════════════════════════════════");
  console.log("  ACCESSIBILITY SETTINGS");
  console.log("════════════════════════════════════════════════════════════════\n");

  console.log("VISION");
  console.log("────────────────────────────────────────");
  console.log(`  Text Size:    ${accessibilityPrefs.textSize} (125%)`);
  console.log(`  Contrast:     ${accessibilityPrefs.contrastMode}`);
  console.log(`  ${toggleState(accessibilityPrefs.boldText)} Bold Text`);
  console.log(`  ${toggleState(accessibilityPrefs.reduceTransparency)} Reduce Transparency\n`);

  console.log("MOTION & HAPTICS");
  console.log("────────────────────────────────────────");
  console.log(`  Motion:       ${accessibilityPrefs.motionPreference}`);
  console.log(`  Haptics:      ${accessibilityPrefs.hapticFeedback}\n`);

  console.log("AUDIO & SCREEN READER");
  console.log("────────────────────────────────────────");
  console.log(`  Verbosity:    ${accessibilityPrefs.screenReaderVerbosity}`);
  console.log(`  ${toggleState(accessibilityPrefs.monoAudio)} Mono Audio\n`);

  await wait(300);

  // Step 4: Offline Mode
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("📴 STEP 4: Offline Mode\n");
  console.log("Access journeys without internet...\n");

  console.log("════════════════════════════════════════════════════════════════");
  console.log("  OFFLINE MODE & SYNC");
  console.log("════════════════════════════════════════════════════════════════\n");

  console.log(`Status: ● ${offlineState.connectivity}\n`);

  console.log("CACHED DATA");
  console.log("────────────────────────────────────────");
  console.log(`  Journeys cached:     ${offlineState.stats.journeysCached}`);
  console.log(`  Annotations cached:  ${offlineState.stats.annotationsCached}`);
  console.log(`  Storage used:        ${(offlineState.stats.storageBytesUsed / 1024).toFixed(1)} KB`);
  console.log(`  Last synced:         1 hour ago\n`);

  console.log("SETTINGS");
  console.log("────────────────────────────────────────");
  console.log(`  ${toggleState(offlineState.prefs.enableOfflineMode)} Enable Offline Mode`);
  console.log(`  ${toggleState(offlineState.prefs.autoSync)} Auto-Sync`);
  console.log(`  ${toggleState(offlineState.prefs.syncOnWifiOnly)} WiFi-Only Sync`);
  console.log(`  ${toggleState(offlineState.prefs.prefetchUpcomingJourneys)} Prefetch Journeys`);
  console.log(`  Cache Duration: ${offlineState.prefs.maxCacheAgeDays} days\n`);

  // Simulate going offline
  console.log("[Simulating offline mode...]\n");
  console.log("Status: ○ Offline - using cached data\n");
  console.log("  ℹ️  Journey data available from cache");
  console.log("  ℹ️  Annotations will sync when back online\n");

  // Summary
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("MVP DEMO COMPLETE");
  console.log("═══════════════════════════════════════════════════════════════\n");
  console.log("The NAFA MVP demonstrates:");
  console.log("  ✓ Journey planning with sensory-aware route segments");
  console.log("  ✓ Sensory annotation collection for locations");
  console.log("  ✓ Accessibility settings for neurodiverse users");
  console.log("  ✓ Offline mode for reliable access anywhere");
  console.log("  ✓ TEA (The Elm Architecture) pattern in ReScript");
  console.log("  ✓ Deno server with REST API\n");
  console.log("Run commands:");
  console.log("  just mvp-demo      - Run this demo");
  console.log("  just mvp-server    - Start the API server");
  console.log("  just mvp-build     - Build ReScript modules\n");
}

runDemo();
