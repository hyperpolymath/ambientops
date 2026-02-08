// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

open Domain

/// Model for journey view page
type model = {
  journey: option<journey>,
  loading: bool,
  error: option<string>,
  activeSegmentId: option<string>,
}

/// Messages for journey view
type msg =
  | LoadJourney(string)
  | JourneyLoaded(journey)
  | JourneyError(string)
  | SelectSegment(string)
  | DeselectSegment
  | StartJourney
  | PauseJourney
  | CompleteJourney

/// Initialize the journey view
let init = (journeyId: string): model => {
  journey: None,
  loading: true,
  error: None,
  activeSegmentId: None,
}

/// Sample journey data for MVP demo
let sampleJourney: journey = {
  id: "journey-001",
  title: "Morning Commute to Central Library",
  status: Planning,
  estimatedMinutes: 35,
  segments: [
    {
      id: "seg-1",
      transportMode: Walk,
      fromLocation: "Home",
      toLocation: "Oak Street Bus Stop",
      durationMinutes: 5,
      sensoryWarning: None,
      sensoryLevels: Some({noise: 3, light: 5, crowd: 2}),
    },
    {
      id: "seg-2",
      transportMode: Bus,
      fromLocation: "Oak Street Bus Stop",
      toLocation: "City Center Station",
      durationMinutes: 15,
      sensoryWarning: Some("Rush hour: expect moderate crowding"),
      sensoryLevels: Some({noise: 6, light: 4, crowd: 7}),
    },
    {
      id: "seg-3",
      transportMode: Walk,
      fromLocation: "City Center Station",
      toLocation: "Central Library",
      durationMinutes: 8,
      sensoryWarning: Some("Construction noise on Main Street"),
      sensoryLevels: Some({noise: 8, light: 6, crowd: 5}),
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
      notes: Some("Very busy during morning rush, quieter after 9am"),
      timestamp: 1703692800000.0,
    },
  ],
}

/// Update function
let update = (msg: msg, model: model): model => {
  switch msg {
  | LoadJourney(_id) => {...model, loading: true, error: None}
  | JourneyLoaded(journey) => {...model, journey: Some(journey), loading: false}
  | JourneyError(err) => {...model, error: Some(err), loading: false}
  | SelectSegment(id) => {...model, activeSegmentId: Some(id)}
  | DeselectSegment => {...model, activeSegmentId: None}
  | StartJourney =>
    switch model.journey {
    | Some(j) => {...model, journey: Some({...j, status: Active})}
    | None => model
    }
  | PauseJourney =>
    switch model.journey {
    | Some(j) => {...model, journey: Some({...j, status: Paused})}
    | None => model
    }
  | CompleteJourney =>
    switch model.journey {
    | Some(j) => {...model, journey: Some({...j, status: Completed})}
    | None => model
    }
  }
}

/// Render sensory level indicator
let renderSensoryLevel = (label: string, level: sensoryLevel): string => {
  let bars = String.repeat("█", level) ++ String.repeat("░", 10 - level)
  `${label}: ${bars} (${Int.toString(level)}/10 - ${sensoryLevelDescription(level)})`
}

/// Render a journey segment
let renderSegment = (segment: journeySegment, isActive: bool): string => {
  let activeMarker = isActive ? " ◀ CURRENT" : ""
  let emoji = transportModeToEmoji(segment.transportMode)
  let mode = transportModeToString(segment.transportMode)

  let warning = switch segment.sensoryWarning {
  | Some(w) => `\n    ⚠️  ${w}`
  | None => ""
  }

  let sensory = switch segment.sensoryLevels {
  | Some(levels) =>
    `\n    Sensory Levels:
      ${renderSensoryLevel("Noise", levels.noise)}
      ${renderSensoryLevel("Light", levels.light)}
      ${renderSensoryLevel("Crowd", levels.crowd)}`
  | None => ""
  }

  `
  ${emoji} ${mode}${activeMarker}
  ────────────────────────────────
  From: ${segment.fromLocation}
  To:   ${segment.toLocation}
  Duration: ${Int.toString(segment.durationMinutes)} minutes${warning}${sensory}
  `
}

/// Render journey status
let renderStatus = (status: journeyStatus): string => {
  switch status {
  | Planning => "📋 Planning"
  | Active => "🚀 Active"
  | Paused => "⏸️  Paused"
  | Completed => "✅ Completed"
  }
}

/// Render the full journey view
let view = (model: model): string => {
  switch model {
  | {loading: true} => "Loading journey..."
  | {error: Some(err)} => `Error: ${err}`
  | {journey: None} => "No journey found"
  | {journey: Some(journey), activeSegmentId} =>
    let segments =
      journey.segments
      ->Array.map(seg => {
        let isActive = activeSegmentId == Some(seg.id)
        renderSegment(seg, isActive)
      })
      ->Array.join("\n")

    let annotations =
      if Array.length(journey.sensoryAnnotations) > 0 {
        let annList =
          journey.sensoryAnnotations
          ->Array.map(ann => {
            let notes = switch ann.notes {
            | Some(n) => `\n    Notes: ${n}`
            | None => ""
            }
            `  📍 ${ann.locationName}
      Noise: ${Int.toString(ann.noise)}/10 | Light: ${Int.toString(ann.light)}/10 | Crowd: ${Int.toString(ann.crowd)}/10${notes}`
          })
          ->Array.join("\n\n")
        `

📝 SENSORY ANNOTATIONS
════════════════════════════════════════
${annList}
`
      } else {
        ""
      }

    `
════════════════════════════════════════
🗺️  JOURNEY: ${journey.title}
════════════════════════════════════════
Status: ${renderStatus(journey.status)}
Estimated Time: ${Int.toString(journey.estimatedMinutes)} minutes

ROUTE SEGMENTS:
${segments}
${annotations}
════════════════════════════════════════
Commands: [S]tart | [P]ause | [C]omplete | [A]nnotate location
════════════════════════════════════════
`
  }
}
