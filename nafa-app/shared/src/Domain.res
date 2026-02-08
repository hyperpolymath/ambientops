// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

/// Sensory intensity level (0-10 scale)
type sensoryLevel = int

/// User's sensory sensitivity profile
type sensoryProfile = {
  noise: sensoryLevel,
  light: sensoryLevel,
  crowd: sensoryLevel,
}

/// A sensory annotation for a specific location
type sensoryAnnotation = {
  id: string,
  locationId: string,
  locationName: string,
  noise: sensoryLevel,
  light: sensoryLevel,
  crowd: sensoryLevel,
  notes: option<string>,
  timestamp: float,
}

/// Transport mode for a journey segment
type transportMode =
  | Walk
  | Bus
  | Train
  | Tram
  | Metro

/// A single segment of a journey
type journeySegment = {
  id: string,
  transportMode: transportMode,
  fromLocation: string,
  toLocation: string,
  durationMinutes: int,
  sensoryWarning: option<string>,
  sensoryLevels: option<sensoryProfile>,
}

/// Status of a journey
type journeyStatus =
  | Planning
  | Active
  | Paused
  | Completed

/// A complete journey plan
type journey = {
  id: string,
  title: string,
  segments: array<journeySegment>,
  status: journeyStatus,
  estimatedMinutes: int,
  sensoryAnnotations: array<sensoryAnnotation>,
}

/// Convert transport mode to display string
let transportModeToString = (mode: transportMode): string => {
  switch mode {
  | Walk => "Walk"
  | Bus => "Bus"
  | Train => "Train"
  | Tram => "Tram"
  | Metro => "Metro"
  }
}

/// Convert transport mode to emoji for visual clarity
let transportModeToEmoji = (mode: transportMode): string => {
  switch mode {
  | Walk => "🚶"
  | Bus => "🚌"
  | Train => "🚆"
  | Tram => "🚊"
  | Metro => "🚇"
  }
}

/// Get sensory level description
let sensoryLevelDescription = (level: sensoryLevel): string => {
  if level <= 2 {
    "Very Low"
  } else if level <= 4 {
    "Low"
  } else if level <= 6 {
    "Moderate"
  } else if level <= 8 {
    "High"
  } else {
    "Very High"
  }
}

/// Check if sensory levels exceed user's profile tolerance
let exceedsProfile = (levels: sensoryProfile, profile: sensoryProfile): bool => {
  levels.noise > profile.noise || levels.light > profile.light || levels.crowd > profile.crowd
}

// ============================================================================
// ACCESSIBILITY
// ============================================================================

/// Text size preference for readability
type textSize =
  | Small
  | Medium
  | Large
  | ExtraLarge

/// Color contrast mode
type contrastMode =
  | Standard
  | HighContrast
  | DarkHighContrast

/// Motion preference for animations
type motionPreference =
  | Full
  | Reduced
  | None

/// Screen reader verbosity level
type screenReaderVerbosity =
  | Minimal
  | Standard
  | Verbose

/// Haptic feedback preference
type hapticPreference =
  | Off
  | Subtle
  | Standard
  | Strong

/// User accessibility preferences
type accessibilityPrefs = {
  textSize: textSize,
  contrastMode: contrastMode,
  motionPreference: motionPreference,
  screenReaderVerbosity: screenReaderVerbosity,
  hapticFeedback: hapticPreference,
  reduceTransparency: bool,
  boldText: bool,
  monoAudio: bool,
}

/// Default accessibility preferences
let defaultAccessibilityPrefs: accessibilityPrefs = {
  textSize: Medium,
  contrastMode: Standard,
  motionPreference: Full,
  screenReaderVerbosity: Standard,
  hapticFeedback: Standard,
  reduceTransparency: false,
  boldText: false,
  monoAudio: false,
}

/// Get text scale factor from preference
let textScaleFactor = (size: textSize): float => {
  switch size {
  | Small => 0.85
  | Medium => 1.0
  | Large => 1.25
  | ExtraLarge => 1.5
  }
}

/// Get accessible label for transport mode (screen reader friendly)
let transportModeAccessibleLabel = (mode: transportMode): string => {
  switch mode {
  | Walk => "Walking segment"
  | Bus => "Bus journey"
  | Train => "Train journey"
  | Tram => "Tram journey"
  | Metro => "Metro or underground journey"
  }
}

/// Generate screen reader description for a journey segment
let segmentAccessibleDescription = (segment: journeySegment): string => {
  let base = `${transportModeAccessibleLabel(segment.transportMode)} from ${segment.fromLocation} to ${segment.toLocation}, taking approximately ${Int.toString(segment.durationMinutes)} minutes`

  let warning = switch segment.sensoryWarning {
  | Some(w) => `. Warning: ${w}`
  | None => ""
  }

  let sensory = switch segment.sensoryLevels {
  | Some(levels) =>
    `. Sensory conditions: noise level ${sensoryLevelDescription(levels.noise)}, lighting ${sensoryLevelDescription(levels.light)}, crowding ${sensoryLevelDescription(levels.crowd)}`
  | None => ""
  }

  base ++ warning ++ sensory
}

// ============================================================================
// OFFLINE MODE
// ============================================================================

/// Network connectivity status
type connectivityStatus =
  | Online
  | Offline
  | Connecting
  | Unstable

/// Sync state for offline data
type syncStatus =
  | Synced
  | Pending
  | Syncing
  | Conflict
  | Error(string)

/// Cached item with sync metadata
type cached<'a> = {
  data: 'a,
  cachedAt: float,
  syncStatus: syncStatus,
  version: int,
}

/// Offline storage stats
type storageStats = {
  journeysCached: int,
  annotationsCached: int,
  pendingUploads: int,
  lastSyncAt: option<float>,
  storageBytesUsed: int,
}

/// Offline mode preferences
type offlinePrefs = {
  enableOfflineMode: bool,
  autoSync: bool,
  syncOnWifiOnly: bool,
  maxCacheAgeDays: int,
  prefetchUpcomingJourneys: bool,
}

/// Default offline preferences
let defaultOfflinePrefs: offlinePrefs = {
  enableOfflineMode: true,
  autoSync: true,
  syncOnWifiOnly: false,
  maxCacheAgeDays: 7,
  prefetchUpcomingJourneys: true,
}

/// Check if cached data is stale
let isCacheStale = (cached: cached<'a>, maxAgeDays: int): bool => {
  let now = Date.now()
  let maxAgeMs = Float.fromInt(maxAgeDays * 24 * 60 * 60 * 1000)
  now -. cached.cachedAt > maxAgeMs
}

/// Sync status description for UI
let syncStatusDescription = (status: syncStatus): string => {
  switch status {
  | Synced => "Up to date"
  | Pending => "Waiting to sync"
  | Syncing => "Syncing..."
  | Conflict => "Sync conflict - review needed"
  | Error(msg) => "Sync error: " ++ msg
  }
}

/// Connectivity status for UI
let connectivityDescription = (status: connectivityStatus): string => {
  switch status {
  | Online => "Connected"
  | Offline => "Offline - using cached data"
  | Connecting => "Connecting..."
  | Unstable => "Connection unstable"
  }
}

// ============================================================================
// COMBINED USER PROFILE
// ============================================================================

/// Complete user preferences including sensory, accessibility, and offline
type userPreferences = {
  sensoryProfile: sensoryProfile,
  accessibilityPrefs: accessibilityPrefs,
  offlinePrefs: offlinePrefs,
}
