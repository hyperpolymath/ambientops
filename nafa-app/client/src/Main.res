// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

module JourneyView = Page_JourneyView
module Annotate = Page_Annotate

/// Page state
type page =
  | HomePage
  | JourneyPage(JourneyView.model)
  | AnnotatePage(Annotate.model)
  | NotFoundPage

/// Application model
type model = {
  currentRoute: Route.t,
  page: page,
}

/// Application messages
type msg =
  | Navigate(Route.t)
  | JourneyMsg(JourneyView.msg)
  | AnnotateMsg(Annotate.msg)

/// Initialize app with a route
let init = (path: string): model => {
  let route = Route.fromPath(path)
  let page = switch route {
  | Route.Home => HomePage
  | Route.JourneyList => HomePage
  | Route.JourneyView(id) =>
    let journeyModel = JourneyView.init(id)
    // Load sample journey for MVP demo
    let loadedModel = JourneyView.update(
      JourneyView.JourneyLoaded(JourneyView.sampleJourney),
      journeyModel,
    )
    JourneyPage(loadedModel)
  | Route.Annotate(locationId) =>
    // For MVP, use a sample location name
    let locationName = switch locationId {
    | "city-center-station" => "City Center Station"
    | "oak-street" => "Oak Street Bus Stop"
    | _ => "Unknown Location"
    }
    AnnotatePage(Annotate.init(locationId, locationName))
  | Route.NotFound => NotFoundPage
  }
  {currentRoute: route, page}
}

/// Update function
let update = (msg: msg, model: model): model => {
  switch msg {
  | Navigate(route) => init(Route.toPath(route))
  | JourneyMsg(journeyMsg) =>
    switch model.page {
    | JourneyPage(journeyModel) =>
      let newJourneyModel = JourneyView.update(journeyMsg, journeyModel)
      {...model, page: JourneyPage(newJourneyModel)}
    | _ => model
    }
  | AnnotateMsg(annotateMsg) =>
    switch model.page {
    | AnnotatePage(annotateModel) =>
      let newAnnotateModel = Annotate.update(annotateMsg, annotateModel)
      {...model, page: AnnotatePage(newAnnotateModel)}
    | _ => model
    }
  }
}

/// View function
let view = (model: model): string => {
  let header = `
╔══════════════════════════════════════════════════════════════╗
║  🧭 NAFA - Neurodiverse App for Adventurers                  ║
║     Navigate with calm, confidence, and clarity              ║
╚══════════════════════════════════════════════════════════════╝
`

  let content = switch model.page {
  | HomePage =>
    `
Welcome to NAFA!

Available Routes:
  /journey/journey-001  - View sample journey plan
  /annotate/city-center-station - Add sensory annotation

Navigation: Enter a route path to navigate
`
  | JourneyPage(journeyModel) => JourneyView.view(journeyModel)
  | AnnotatePage(annotateModel) => Annotate.view(annotateModel)
  | NotFoundPage =>
    `
404 - Page Not Found

The requested page does not exist.
Navigate to / to return home.
`
  }

  let footer = `
────────────────────────────────────────────────────────────────
Current Route: ${Route.toPath(model.currentRoute)}
────────────────────────────────────────────────────────────────
`

  header ++ content ++ footer
}

/// Demo runner - shows the full MVP flow
let runDemo = (): string => {
  let output = ref("")
  let log = (s: string) => output := output.contents ++ s ++ "\n"

  log("╔══════════════════════════════════════════════════════════════╗")
  log("║              NAFA MVP DEMO - Journey + Annotations           ║")
  log("╚══════════════════════════════════════════════════════════════╝")
  log("")

  // 1. Show home page
  log("═══ STEP 1: Home Page ═══")
  let homeModel = init("/")
  log(view(homeModel))

  // 2. Navigate to journey
  log("\n═══ STEP 2: Journey Plan View ═══")
  let journeyModel = init("/journey/journey-001")
  log(view(journeyModel))

  // 3. Start the journey
  log("\n═══ STEP 3: Start Journey ═══")
  let startedModel = update(JourneyMsg(JourneyView.StartJourney), journeyModel)
  let selectModel = update(JourneyMsg(JourneyView.SelectSegment("seg-1")), startedModel)
  log(view(selectModel))

  // 4. Navigate to annotation
  log("\n═══ STEP 4: Sensory Annotation Flow ═══")
  let annotateModel = init("/annotate/city-center-station")
  log(view(annotateModel))

  // 5. Fill in annotation
  log("\n═══ STEP 5: Annotation with Data ═══")
  let filledModel = switch annotateModel.page {
  | AnnotatePage(am) =>
    let m1 = Annotate.update(Annotate.SetNoise(7), am)
    let m2 = Annotate.update(Annotate.SetLight(5), m1)
    let m3 = Annotate.update(Annotate.SetCrowd(8), m2)
    let m4 = Annotate.update(Annotate.SetNotes("Busy during rush hour, calmer after 9am"), m3)
    {...annotateModel, page: AnnotatePage(m4)}
  | _ => annotateModel
  }
  log(view(filledModel))

  // 6. Submit annotation
  log("\n═══ STEP 6: Annotation Submitted ═══")
  let submittedModel = switch filledModel.page {
  | AnnotatePage(am) =>
    let m1 = Annotate.update(Annotate.Submit, am)
    let annotation = Annotate.toAnnotation(m1)
    let m2 = Annotate.update(Annotate.SubmitSuccess(annotation), m1)
    {...filledModel, page: AnnotatePage(m2)}
  | _ => filledModel
  }
  log(view(submittedModel))

  log("\n═══ MVP DEMO COMPLETE ═══")
  log("The NAFA MVP demonstrates:")
  log("  1. Journey planning with sensory-aware route segments")
  log("  2. Sensory annotation collection for locations")
  log("  3. TEA (The Elm Architecture) pattern in ReScript")
  log("")

  output.contents
}
