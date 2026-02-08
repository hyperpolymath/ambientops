// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

open Domain

/// Model for sensory annotation page
type model = {
  locationId: string,
  locationName: string,
  noise: sensoryLevel,
  light: sensoryLevel,
  crowd: sensoryLevel,
  notes: string,
  submitting: bool,
  submitted: bool,
  error: option<string>,
}

/// Messages for annotation page
type msg =
  | SetNoise(sensoryLevel)
  | SetLight(sensoryLevel)
  | SetCrowd(sensoryLevel)
  | SetNotes(string)
  | Submit
  | SubmitSuccess(sensoryAnnotation)
  | SubmitError(string)
  | Reset

/// Initialize annotation form
let init = (locationId: string, locationName: string): model => {
  locationId,
  locationName,
  noise: 5,
  light: 5,
  crowd: 5,
  notes: "",
  submitting: false,
  submitted: false,
  error: None,
}

/// Clamp sensory level to valid range
let clampLevel = (level: int): sensoryLevel => {
  if level < 0 {
    0
  } else if level > 10 {
    10
  } else {
    level
  }
}

/// Update function
let update = (msg: msg, model: model): model => {
  switch msg {
  | SetNoise(level) => {...model, noise: clampLevel(level)}
  | SetLight(level) => {...model, light: clampLevel(level)}
  | SetCrowd(level) => {...model, crowd: clampLevel(level)}
  | SetNotes(notes) => {...model, notes}
  | Submit => {...model, submitting: true, error: None}
  | SubmitSuccess(_) => {...model, submitting: false, submitted: true}
  | SubmitError(err) => {...model, submitting: false, error: Some(err)}
  | Reset =>
    init(model.locationId, model.locationName)
  }
}

/// Create annotation from model
let toAnnotation = (model: model): sensoryAnnotation => {
  id: "ann-" ++ model.locationId ++ "-" ++ Float.toString(Date.now()),
  locationId: model.locationId,
  locationName: model.locationName,
  noise: model.noise,
  light: model.light,
  crowd: model.crowd,
  notes: if model.notes == "" {
    None
  } else {
    Some(model.notes)
  },
  timestamp: Date.now(),
}

/// Render slider visualization
let renderSlider = (label: string, value: sensoryLevel, emoji: string): string => {
  let filled = String.repeat("●", value)
  let empty = String.repeat("○", 10 - value)
  let desc = sensoryLevelDescription(value)
  `${emoji} ${label}: [${filled}${empty}] ${Int.toString(value)}/10 (${desc})`
}

/// Render the annotation form
let view = (model: model): string => {
  if model.submitted {
    `
════════════════════════════════════════
✅ ANNOTATION SAVED
════════════════════════════════════════

Thank you for contributing sensory data for:
📍 ${model.locationName}

Your annotation helps other neurodiverse travelers
prepare for their journeys.

════════════════════════════════════════
Commands: [R]eset to add another | [B]ack to journey
════════════════════════════════════════
`
  } else if model.submitting {
    "Saving annotation..."
  } else {
    let errorMsg = switch model.error {
    | Some(err) => `\n❌ Error: ${err}\n`
    | None => ""
    }

    `
════════════════════════════════════════
📝 SENSORY ANNOTATION
════════════════════════════════════════
Location: ${model.locationName}
${errorMsg}
Rate the sensory environment at this location:

${renderSlider("Noise Level", model.noise, "🔊")}
  (0 = Silent, 10 = Very Loud)

${renderSlider("Light Level", model.light, "💡")}
  (0 = Very Dark, 10 = Very Bright)

${renderSlider("Crowd Level", model.crowd, "👥")}
  (0 = Empty, 10 = Very Crowded)

📝 Notes (optional):
┌────────────────────────────────────────┐
│ ${model.notes == "" ? "(Add any helpful details for other travelers)" : model.notes}
└────────────────────────────────────────┘

════════════════════════════════════════
Commands:
  [N]+/- Noise | [L]+/- Light | [C]+/- Crowd
  [T] Add notes | [S]ubmit | [B]ack
════════════════════════════════════════
`
  }
}

/// Demo: Show how annotation flow works
let demoFlow = (): string => {
  // Initialize
  let m0 = init("city-center-station", "City Center Station")

  // User adjusts levels
  let m1 = update(SetNoise(7), m0)
  let m2 = update(SetLight(5), m1)
  let m3 = update(SetCrowd(8), m2)
  let m4 = update(SetNotes("Very busy during morning rush, quieter after 9am"), m3)

  // Show form state
  let formView = view(m4)

  // Submit
  let m5 = update(Submit, m4)
  let annotation = toAnnotation(m5)
  let m6 = update(SubmitSuccess(annotation), m5)

  // Show success state
  let successView = view(m6)

  `
=== SENSORY ANNOTATION FLOW DEMO ===

STEP 1: User opens annotation form
${formView}

STEP 2: User submits annotation
${successView}

=== END DEMO ===
`
}
