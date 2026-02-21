// AccessibilityImpl.res - Pure ReScript accessibility checking
// Replaces bindings/a11y.ts

@genType
type wcagLevel = A | AA | AAA

@genType
type accessibilityIssue = {
  rule: string,
  level: wcagLevel,
  message: string,
  element: option<string>,
  selector: option<string>,
  impact: string,
}

@genType
type accessibilityResult = {
  score: float,
  violations: array<accessibilityIssue>,
  warnings: array<accessibilityIssue>,
  passes: int,
  incomplete: int,
  wcagLevel: wcagLevel,
}

// Helper to count regex matches
let countMatches = (html: string, pattern: Js.Re.t): int => {
  switch Js.String2.match_(html, pattern) {
  | Some(matches) => Array.length(matches)
  | None => 0
  }
}

// Helper to check if pattern exists
let hasPattern = (html: string, pattern: Js.Re.t): bool => {
  Js.Re.test_(pattern, html)
}

@genType
let checkAccessibility = async (html: string, _url: string): accessibilityResult => {
  let violations: array<accessibilityIssue> = []
  let warnings: array<accessibilityIssue> = []
  let passes = ref(0)

  // Check for alt text on images
  let imgRe = %re("/<img[^>]*>/gi")
  let imgMatches = Js.String2.match_(html, imgRe)
  switch imgMatches {
  | Some(matches) => {
      matches->Array.forEach(imgTag => {
        if !String.includes(imgTag, "alt=") {
          Array.push(violations, {
            rule: "image-alt",
            level: A,
            message: "Image missing alt attribute",
            element: Some(String.slice(imgTag, ~start=0, ~end=100)),
            selector: None,
            impact: "critical",
          })->ignore
        } else {
          passes := passes.contents + 1
        }
      })
    }
  | None => ()
  }

  // Check for lang attribute
  let langRe = %re("/<html[^>]*lang=/i")
  if !hasPattern(html, langRe) {
    Array.push(violations, {
      rule: "html-has-lang",
      level: A,
      message: "HTML element must have a lang attribute",
      element: None,
      selector: None,
      impact: "serious",
    })->ignore
  } else {
    passes := passes.contents + 1
  }

  // Check for page title
  let titleRe = %re("/<title[^>]*>/i")
  if !hasPattern(html, titleRe) {
    Array.push(violations, {
      rule: "document-title",
      level: A,
      message: "Document must have a title element",
      element: None,
      selector: None,
      impact: "serious",
    })->ignore
  } else {
    passes := passes.contents + 1
  }

  // Check for viewport meta tag
  let viewportRe = %re("/<meta[^>]*name=[\"']viewport[\"'][^>]*>/i")
  if !hasPattern(html, viewportRe) {
    Array.push(warnings, {
      rule: "meta-viewport",
      level: AA,
      message: "Viewport meta tag missing for mobile responsiveness",
      element: None,
      selector: None,
      impact: "moderate",
    })->ignore
  } else {
    passes := passes.contents + 1
  }

  // Check for proper heading hierarchy
  let h1Re = %re("/<h1[^>]*>/gi")
  let h1Count = countMatches(html, h1Re)
  if h1Count === 0 {
    Array.push(violations, {
      rule: "page-has-heading-one",
      level: AA,
      message: "Page must have at least one h1 heading",
      element: None,
      selector: None,
      impact: "moderate",
    })->ignore
  } else if h1Count > 1 {
    Array.push(warnings, {
      rule: "page-has-heading-one",
      level: AA,
      message: "Page should have only one h1 heading",
      element: None,
      selector: None,
      impact: "minor",
    })->ignore
  } else {
    passes := passes.contents + 1
  }

  // Check for form labels
  let inputRe = %re("/<input[^>]*type=[\"'](?!hidden)[^\"']*[\"'][^>]*>/gi")
  let inputMatches = Js.String2.match_(html, inputRe)
  switch inputMatches {
  | Some(matches) => {
      matches->Array.forEach(inputTag => {
        let idRe = %re("/id=[\"']([^\"']+)[\"']/")
        let idMatch = Js.Re.exec_(idRe, inputTag)
        switch idMatch {
        | Some(result) => {
            let captures = Js.Re.captures(result)
            switch captures->Array.get(1) {
            | Some(capture) => {
                let id = Js.Nullable.toOption(capture)
                switch id {
                | Some(idVal) => {
                    let labelFor = `for="${idVal}"`
                    let hasLabel = String.includes(html, labelFor)
                    let hasAriaLabel = String.includes(inputTag, "aria-label=")
                    if !hasLabel && !hasAriaLabel {
                      Array.push(violations, {
                        rule: "label",
                        level: A,
                        message: `Form input with id="${idVal}" is missing a label`,
                        element: Some(String.slice(inputTag, ~start=0, ~end=100)),
                        selector: None,
                        impact: "critical",
                      })->ignore
                    } else {
                      passes := passes.contents + 1
                    }
                  }
                | None => ()
                }
              }
            | None => ()
            }
          }
        | None => ()
        }
      })
    }
  | None => ()
  }

  // Check for color contrast (simplified)
  let hasColorStyles = String.includes(html, "color:") || String.includes(html, "background")
  if hasColorStyles {
    Array.push(warnings, {
      rule: "color-contrast",
      level: AA,
      message: "Manual check required: Ensure text has sufficient color contrast",
      element: None,
      selector: None,
      impact: "serious",
    })->ignore
  }

  // Check for link text
  let linkRe = %re("/<a[^>]*href=[\"'][^\"']+[\"'][^>]*>([^<]*)<\/a>/gi")
  let linkMatches = Js.String2.match_(html, linkRe)
  switch linkMatches {
  | Some(matches) => {
      matches->Array.forEach(linkTag => {
        // Extract text between tags
        let text = linkTag
          ->Js.String2.replaceByRe(%re("/<[^>]+>/g"), "")
          ->String.trim
        if String.length(text) < 2 {
          Array.push(violations, {
            rule: "link-name",
            level: A,
            message: "Links must have discernible text",
            element: Some(String.slice(linkTag, ~start=0, ~end=100)),
            selector: None,
            impact: "serious",
          })->ignore
        } else {
          passes := passes.contents + 1
        }
      })
    }
  | None => ()
  }

  // Calculate score
  let criticalCount = violations->Array.filter(v => v.impact === "critical")->Array.length
  let seriousCount = violations->Array.filter(v => v.impact === "serious")->Array.length

  let score = Float.fromInt(100) -.
    Float.fromInt(criticalCount) *. 10.0 -.
    Float.fromInt(seriousCount) *. 5.0 -.
    Float.fromInt(Array.length(warnings)) *. 2.0

  let finalScore = if score < 0.0 { 0.0 } else { score }

  {
    score: finalScore,
    violations,
    warnings,
    passes: passes.contents,
    incomplete: 0,
    wcagLevel: AA,
  }
}

@genType
let levelToString = (level: wcagLevel): string => {
  switch level {
  | A => "A"
  | AA => "AA"
  | AAA => "AAA"
  }
}

@genType
let levelFromString = (str: string): option<wcagLevel> => {
  switch String.toUpperCase(str) {
  | "A" => Some(A)
  | "AA" => Some(AA)
  | "AAA" => Some(AAA)
  | _ => None
  }
}
