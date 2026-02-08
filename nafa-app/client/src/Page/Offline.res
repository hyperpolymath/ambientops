// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

open Domain

/// Model for offline manager page
type model = {
  connectivity: connectivityStatus,
  prefs: offlinePrefs,
  stats: storageStats,
  syncing: bool,
  lastError: option<string>,
}

/// Messages for offline manager
type msg =
  | ConnectivityChanged(connectivityStatus)
  | ToggleOfflineMode
  | ToggleAutoSync
  | ToggleSyncOnWifiOnly
  | SetMaxCacheAge(int)
  | TogglePrefetch
  | TriggerSync
  | SyncStarted
  | SyncCompleted(storageStats)
  | SyncFailed(string)
  | ClearCache
  | CacheCleared

/// Initialize offline manager
let init = (): model => {
  connectivity: Online,
  prefs: defaultOfflinePrefs,
  stats: {
    journeysCached: 3,
    annotationsCached: 12,
    pendingUploads: 0,
    lastSyncAt: Some(Date.now() -. 3600000.0), // 1 hour ago
    storageBytesUsed: 256000,
  },
  syncing: false,
  lastError: None,
}

/// Update function
let update = (msg: msg, model: model): model => {
  switch msg {
  | ConnectivityChanged(status) => {...model, connectivity: status}
  | ToggleOfflineMode =>
    let newPrefs = {...model.prefs, enableOfflineMode: !model.prefs.enableOfflineMode}
    {...model, prefs: newPrefs}
  | ToggleAutoSync =>
    let newPrefs = {...model.prefs, autoSync: !model.prefs.autoSync}
    {...model, prefs: newPrefs}
  | ToggleSyncOnWifiOnly =>
    let newPrefs = {...model.prefs, syncOnWifiOnly: !model.prefs.syncOnWifiOnly}
    {...model, prefs: newPrefs}
  | SetMaxCacheAge(days) =>
    let newPrefs = {...model.prefs, maxCacheAgeDays: days}
    {...model, prefs: newPrefs}
  | TogglePrefetch =>
    let newPrefs = {...model.prefs, prefetchUpcomingJourneys: !model.prefs.prefetchUpcomingJourneys}
    {...model, prefs: newPrefs}
  | TriggerSync => {...model, syncing: true, lastError: None}
  | SyncStarted => {...model, syncing: true}
  | SyncCompleted(stats) => {...model, syncing: false, stats}
  | SyncFailed(err) => {...model, syncing: false, lastError: Some(err)}
  | ClearCache => model
  | CacheCleared =>
    let emptyStats = {
      journeysCached: 0,
      annotationsCached: 0,
      pendingUploads: 0,
      lastSyncAt: None,
      storageBytesUsed: 0,
    }
    {...model, stats: emptyStats}
  }
}

/// Format bytes to human readable
let formatBytes = (bytes: int): string => {
  if bytes < 1024 {
    Int.toString(bytes) ++ " B"
  } else if bytes < 1024 * 1024 {
    Float.toFixedWithPrecision(Float.fromInt(bytes) /. 1024.0, ~digits=1) ++ " KB"
  } else {
    Float.toFixedWithPrecision(Float.fromInt(bytes) /. (1024.0 *. 1024.0), ~digits=1) ++ " MB"
  }
}

/// Format timestamp to relative time
let formatRelativeTime = (timestamp: float): string => {
  let now = Date.now()
  let diffMs = now -. timestamp
  let diffMins = diffMs /. 60000.0

  if diffMins < 1.0 {
    "just now"
  } else if diffMins < 60.0 {
    Float.toFixed(diffMins) ++ " min ago"
  } else if diffMins < 1440.0 {
    Float.toFixed(diffMins /. 60.0) ++ " hours ago"
  } else {
    Float.toFixed(diffMins /. 1440.0) ++ " days ago"
  }
}

/// Render toggle state
let toggleState = (on: bool): string => on ? "[X]" : "[ ]"

/// Render connectivity indicator
let connectivityIndicator = (status: connectivityStatus): string => {
  switch status {
  | Online => "● Online"
  | Offline => "○ Offline"
  | Connecting => "◐ Connecting..."
  | Unstable => "◑ Unstable"
  }
}

/// Render the offline manager view
let view = (model: model): string => {
  let lastSyncStr = switch model.stats.lastSyncAt {
  | Some(ts) => formatRelativeTime(ts)
  | None => "Never"
  }

  let errorStr = switch model.lastError {
  | Some(err) => `\n  ⚠ Error: ${err}\n`
  | None => ""
  }

  let syncButton = model.syncing ? "[ Syncing... ]" : "[ Sync Now ]"

  let pendingWarning =
    model.stats.pendingUploads > 0
      ? `\n  ⚠ ${Int.toString(model.stats.pendingUploads)} annotations waiting to upload`
      : ""

  `
════════════════════════════════════════════════════════════════
  OFFLINE MODE & SYNC
════════════════════════════════════════════════════════════════

Status: ${connectivityIndicator(model.connectivity)}
${connectivityDescription(model.connectivity)}
${errorStr}
────────────────────────────────────────────────────────────────
  CACHED DATA
────────────────────────────────────────────────────────────────

  Journeys cached:     ${Int.toString(model.stats.journeysCached)}
  Annotations cached:  ${Int.toString(model.stats.annotationsCached)}
  Storage used:        ${formatBytes(model.stats.storageBytesUsed)}
  Last synced:         ${lastSyncStr}
${pendingWarning}

────────────────────────────────────────────────────────────────
  SETTINGS
────────────────────────────────────────────────────────────────

${toggleState(model.prefs.enableOfflineMode)} Enable Offline Mode [O]
    Save journeys for use without internet

${toggleState(model.prefs.autoSync)} Auto-Sync [A]
    Automatically sync when online

${toggleState(model.prefs.syncOnWifiOnly)} WiFi-Only Sync [W]
    Only sync on WiFi to save mobile data

${toggleState(model.prefs.prefetchUpcomingJourneys)} Prefetch Journeys [P]
    Download upcoming journeys in advance

Cache Duration: ${Int.toString(model.prefs.maxCacheAgeDays)} days
    [+/-] Adjust how long to keep cached data

────────────────────────────────────────────────────────────────
  ACTIONS
────────────────────────────────────────────────────────────────

  [S] ${syncButton}  |  [C] Clear Cache  |  [B] Back

════════════════════════════════════════════════════════════════
`
}

/// Demo showing offline mode in action
let demoOffline = (): string => {
  // Start online
  let m0 = init()

  // Go offline
  let m1 = update(ConnectivityChanged(Offline), m0)

  // Show offline state
  view(m1)
}

/// Demo showing sync in progress
let demoSyncing = (): string => {
  let m0 = init()

  // Add pending uploads
  let m1 = {
    ...m0,
    stats: {...m0.stats, pendingUploads: 3},
  }

  // Start sync
  let m2 = update(TriggerSync, m1)

  view(m2)
}
