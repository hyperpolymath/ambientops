// SPDX-License-Identifier: MIT OR PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

open Domain

/// Model for accessibility settings page
type model = {
  prefs: accessibilityPrefs,
  saved: bool,
  previewMode: bool,
}

/// Messages for accessibility settings
type msg =
  | SetTextSize(textSize)
  | SetContrastMode(contrastMode)
  | SetMotionPreference(motionPreference)
  | SetScreenReaderVerbosity(screenReaderVerbosity)
  | SetHapticFeedback(hapticPreference)
  | ToggleReduceTransparency
  | ToggleBoldText
  | ToggleMonoAudio
  | TogglePreview
  | Save
  | Reset

/// Initialize with default or loaded preferences
let init = (prefs: option<accessibilityPrefs>): model => {
  prefs: switch prefs {
  | Some(p) => p
  | None => defaultAccessibilityPrefs
  },
  saved: false,
  previewMode: false,
}

/// Update function
let update = (msg: msg, model: model): model => {
  let updatePrefs = (f: accessibilityPrefs => accessibilityPrefs) => {
    {...model, prefs: f(model.prefs), saved: false}
  }

  switch msg {
  | SetTextSize(size) => updatePrefs(p => {...p, textSize: size})
  | SetContrastMode(mode) => updatePrefs(p => {...p, contrastMode: mode})
  | SetMotionPreference(pref) => updatePrefs(p => {...p, motionPreference: pref})
  | SetScreenReaderVerbosity(v) => updatePrefs(p => {...p, screenReaderVerbosity: v})
  | SetHapticFeedback(h) => updatePrefs(p => {...p, hapticFeedback: h})
  | ToggleReduceTransparency =>
    updatePrefs(p => {...p, reduceTransparency: !p.reduceTransparency})
  | ToggleBoldText => updatePrefs(p => {...p, boldText: !p.boldText})
  | ToggleMonoAudio => updatePrefs(p => {...p, monoAudio: !p.monoAudio})
  | TogglePreview => {...model, previewMode: !model.previewMode}
  | Save => {...model, saved: true}
  | Reset => {...model, prefs: defaultAccessibilityPrefs, saved: false}
  }
}

/// Render text size option
let textSizeLabel = (size: textSize): string => {
  switch size {
  | Small => "Small (85%)"
  | Medium => "Medium (100%)"
  | Large => "Large (125%)"
  | ExtraLarge => "Extra Large (150%)"
  }
}

/// Render contrast mode option
let contrastModeLabel = (mode: contrastMode): string => {
  switch mode {
  | Standard => "Standard"
  | HighContrast => "High Contrast"
  | DarkHighContrast => "Dark High Contrast"
  }
}

/// Render motion preference option
let motionPrefLabel = (pref: motionPreference): string => {
  switch pref {
  | Full => "Full animations"
  | Reduced => "Reduced motion"
  | None => "No animations"
  }
}

/// Render screen reader verbosity option
let verbosityLabel = (v: screenReaderVerbosity): string => {
  switch v {
  | Minimal => "Minimal - essential info only"
  | Standard => "Standard - balanced detail"
  | Verbose => "Verbose - full descriptions"
  }
}

/// Render haptic preference option
let hapticLabel = (h: hapticPreference): string => {
  switch h {
  | Off => "Off"
  | Subtle => "Subtle"
  | Standard => "Standard"
  | Strong => "Strong"
  }
}

/// Render toggle state
let toggleState = (on: bool): string => on ? "[X]" : "[ ]"

/// Render the accessibility settings view
let view = (model: model): string => {
  let savedIndicator = model.saved ? " (Saved)" : " (Unsaved changes)"

  `
════════════════════════════════════════════════════════════════
  ACCESSIBILITY SETTINGS${savedIndicator}
════════════════════════════════════════════════════════════════

Make NAFA work better for you. All changes apply immediately
when Preview Mode is enabled.

Preview Mode: ${toggleState(model.previewMode)} ${model.previewMode ? "Changes visible now" : "Press [P] to preview"}

────────────────────────────────────────────────────────────────
  VISION
────────────────────────────────────────────────────────────────

Text Size: ${textSizeLabel(model.prefs.textSize)}
  [1] Small  [2] Medium  [3] Large  [4] Extra Large

Contrast: ${contrastModeLabel(model.prefs.contrastMode)}
  [C] Standard  [H] High Contrast  [D] Dark High Contrast

${toggleState(model.prefs.boldText)} Bold Text - Make all text bolder [B]
${toggleState(model.prefs.reduceTransparency)} Reduce Transparency - Solid backgrounds [T]

────────────────────────────────────────────────────────────────
  MOTION & HAPTICS
────────────────────────────────────────────────────────────────

Motion: ${motionPrefLabel(model.prefs.motionPreference)}
  [M] Full  [R] Reduced  [N] None

Haptic Feedback: ${hapticLabel(model.prefs.hapticFeedback)}
  [0] Off  [1] Subtle  [2] Standard  [3] Strong

────────────────────────────────────────────────────────────────
  AUDIO & SCREEN READER
────────────────────────────────────────────────────────────────

Screen Reader Verbosity: ${verbosityLabel(model.prefs.screenReaderVerbosity)}
  [V] Minimal  [S] Standard  [F] Verbose (Full)

${toggleState(model.prefs.monoAudio)} Mono Audio - Combine stereo to single channel [A]

────────────────────────────────────────────────────────────────
  ACTIONS
────────────────────────────────────────────────────────────────
[Enter] Save Settings  |  [Esc] Cancel  |  [X] Reset to Defaults
════════════════════════════════════════════════════════════════
`
}

/// Demo showing accessibility features
let demoAccessibility = (): string => {
  // Start with defaults
  let m0 = init(None)

  // User customizes for low vision + reduced motion
  let m1 = update(SetTextSize(Large), m0)
  let m2 = update(SetContrastMode(HighContrast), m1)
  let m3 = update(SetMotionPreference(Reduced), m2)
  let m4 = update(ToggleBoldText, m3)
  let m5 = update(Save, m4)

  view(m5)
}
