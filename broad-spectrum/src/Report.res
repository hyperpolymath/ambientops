// Report.res - Report generation in multiple formats
// Uses ReportImpl (pure ReScript implementation)

@genType
type auditReport = {
  url: string,
  timestamp: string,
  linkCheck: option<LinkChecker.linkCheckResult>,
  accessibility: option<Accessibility.accessibilityResult>,
  performance: option<Performance.performanceResult>,
  seo: option<SEO.seoResult>,
  overallScore: float,
  executionTime: float,
}

@genType
let calculateOverallScore = (
  linkCheck: option<LinkChecker.linkCheckResult>,
  accessibility: option<Accessibility.accessibilityResult>,
  performance: option<Performance.performanceResult>,
  seo: option<SEO.seoResult>,
): float => {
  let totalScore = ref(0.0)
  let totalWeight = ref(0.0)

  // Link checking: 20% weight
  switch linkCheck {
  | Some(result) => {
      let brokenPercent = if result.totalLinks > 0 {
        Float.fromInt(result.brokenLinks) /. Float.fromInt(result.totalLinks) *. 100.0
      } else {
        0.0
      }
      let linkScore = 100.0 -. brokenPercent
      totalScore := totalScore.contents +. linkScore *. 0.2
      totalWeight := totalWeight.contents +. 0.2
    }
  | None => ()
  }

  // Accessibility: 30% weight
  switch accessibility {
  | Some(result) => {
      totalScore := totalScore.contents +. result.score *. 0.3
      totalWeight := totalWeight.contents +. 0.3
    }
  | None => ()
  }

  // Performance: 30% weight
  switch performance {
  | Some(result) => {
      let perfScore = Performance.calculateScore(result.metrics)
      totalScore := totalScore.contents +. perfScore *. 0.3
      totalWeight := totalWeight.contents +. 0.3
    }
  | None => ()
  }

  // SEO: 20% weight
  switch seo {
  | Some(result) => {
      totalScore := totalScore.contents +. result.score *. 0.2
      totalWeight := totalWeight.contents +. 0.2
    }
  | None => ()
  }

  if totalWeight.contents > 0.0 {
    totalScore.contents /. totalWeight.contents
  } else {
    0.0
  }
}

@genType
let create = (
  url: string,
  linkCheck: option<LinkChecker.linkCheckResult>,
  accessibility: option<Accessibility.accessibilityResult>,
  performance: option<Performance.performanceResult>,
  seo: option<SEO.seoResult>,
  executionTime: float,
): auditReport => {
  let overallScore = calculateOverallScore(linkCheck, accessibility, performance, seo)

  {
    url,
    timestamp: DenoBindings.Date.now()->Float.toString,
    linkCheck,
    accessibility,
    performance,
    seo,
    overallScore,
    executionTime,
  }
}

@genType
let formatConsole = (report: auditReport): string => {
  let lines: array<string> = []

  // Header
  Array.push(lines, "\n" ++ String.repeat("=", 80))->ignore
  Array.push(lines, "WEBSITE AUDIT REPORT")->ignore
  Array.push(lines, String.repeat("=", 80))->ignore
  Array.push(lines, `URL: ${report.url}`)->ignore
  Array.push(lines, `Timestamp: ${report.timestamp}`)->ignore
  Array.push(lines, `Execution Time: ${Float.toFixed(report.executionTime /. 1000.0, ~digits=2)}s`)->ignore
  Array.push(lines, `Overall Score: ${Float.toFixed(report.overallScore, ~digits=1)}/100`)->ignore
  Array.push(lines, String.repeat("=", 80) ++ "\n")->ignore

  // Link Check Results
  switch report.linkCheck {
  | Some(result) => {
      Array.push(lines, "LINK CHECK")->ignore
      Array.push(lines, String.repeat("-", 80))->ignore
      Array.push(lines, `Total Links: ${Int.toString(result.totalLinks)}`)->ignore
      Array.push(lines, `Broken Links: ${Int.toString(result.brokenLinks)}`)->ignore
      Array.push(lines, `External Links: ${Int.toString(result.externalLinks)}`)->ignore
      Array.push(lines, `Redirects: ${Int.toString(result.redirects)}`)->ignore
      Array.push(lines, `Average Response Time: ${Float.toFixed(result.averageResponseTime, ~digits=0)}ms`)->ignore

      if result.brokenLinks > 0 {
        Array.push(lines, "\nBroken Links:")->ignore
        result.checkedLinks
          ->Array.filter(link => link.broken)
          ->Array.forEach(link => {
            let error = link.errorMessage->Option.getOr("Unknown error")
            Array.push(lines, `  - ${link.url} [${error}]`)->ignore
          })
      }
      Array.push(lines, "")->ignore
    }
  | None => ()
  }

  // Accessibility Results
  switch report.accessibility {
  | Some(result) => {
      Array.push(lines, "ACCESSIBILITY (WCAG " ++ Accessibility.levelToString(result.wcagLevel) ++ ")")->ignore
      Array.push(lines, String.repeat("-", 80))->ignore
      Array.push(lines, `Score: ${Float.toFixed(result.score, ~digits=1)}/100`)->ignore
      Array.push(lines, `Violations: ${Int.toString(Array.length(result.violations))}`)->ignore
      Array.push(lines, `Warnings: ${Int.toString(Array.length(result.warnings))}`)->ignore
      Array.push(lines, `Passes: ${Int.toString(result.passes)}`)->ignore

      if Array.length(result.violations) > 0 {
        Array.push(lines, "\nTop Violations:")->ignore
        result.violations
          ->Array.slice(~start=0, ~end=5)
          ->Array.forEach(violation => {
            Array.push(lines, `  - [${violation.impact}] ${violation.rule}: ${violation.message}`)->ignore
          })
      }
      Array.push(lines, "")->ignore
    }
  | None => ()
  }

  // Performance Results
  switch report.performance {
  | Some(result) => {
      let score = Performance.calculateScore(result.metrics)
      Array.push(lines, "PERFORMANCE")->ignore
      Array.push(lines, String.repeat("-", 80))->ignore
      Array.push(lines, `Score: ${Float.toFixed(score, ~digits=1)}/100`)->ignore
      Array.push(lines, `Page Size: ${Performance.formatBytes(result.metrics.totalPageSize)}`)->ignore
      Array.push(lines, `Resources: ${Int.toString(result.metrics.resourceCount)}`)->ignore
      Array.push(lines, `Load Time: ${Float.toFixed(result.metrics.loadComplete, ~digits=0)}ms`)->ignore

      switch result.metrics.largestContentfulPaint {
      | Some(lcp) => Array.push(lines, `LCP: ${Float.toFixed(lcp, ~digits=0)}ms`)->ignore
      | None => ()
      }

      switch result.metrics.firstContentfulPaint {
      | Some(fcp) => Array.push(lines, `FCP: ${Float.toFixed(fcp, ~digits=0)}ms`)->ignore
      | None => ()
      }

      if Array.length(result.warnings) > 0 {
        Array.push(lines, "\nWarnings:")->ignore
        result.warnings->Array.forEach(warning => {
          Array.push(lines, `  - ${warning}`)->ignore
        })
      }
      Array.push(lines, "")->ignore
    }
  | None => ()
  }

  // SEO Results
  switch report.seo {
  | Some(result) => {
      Array.push(lines, "SEO")->ignore
      Array.push(lines, String.repeat("-", 80))->ignore
      Array.push(lines, `Score: ${Float.toFixed(result.score, ~digits=1)}/100`)->ignore

      switch result.data.title {
      | Some(title) => Array.push(lines, `Title: ${title}`)->ignore
      | None => Array.push(lines, "Title: (missing)")->ignore
      }

      switch result.data.description {
      | Some(desc) => {
          let truncated = if String.length(desc) > 100 {
            String.substring(desc, ~start=0, ~end=100) ++ "..."
          } else {
            desc
          }
          Array.push(lines, `Description: ${truncated}`)->ignore
        }
      | None => Array.push(lines, "Description: (missing)")->ignore
      }

      Array.push(lines, `Word Count: ${Int.toString(result.data.wordCount)}`)->ignore

      let errorCount = SEO.filterIssuesBySeverity(result.issues, "error")->Array.length
      let warningCount = SEO.filterIssuesBySeverity(result.issues, "warning")->Array.length

      if errorCount > 0 || warningCount > 0 {
        Array.push(lines, `Issues: ${Int.toString(errorCount)} errors, ${Int.toString(warningCount)} warnings`)->ignore
      }

      if errorCount > 0 {
        Array.push(lines, "\nCritical Issues:")->ignore
        result.issues
          ->Array.filter(issue => issue.severity === "error")
          ->Array.forEach(issue => {
            Array.push(lines, `  - ${issue.message}`)->ignore
          })
      }
      Array.push(lines, "")->ignore
    }
  | None => ()
  }

  Array.push(lines, String.repeat("=", 80))->ignore

  Array.join(lines, "\n")
}

@genType
let format = async (report: auditReport, format: Config.reportFormat): string => {
  switch format {
  | Console => formatConsole(report)
  | JSON => ReportImpl.formatAsJSON(report)
  | HTML => await ReportImpl.formatAsHTML(report)
  | Markdown => ReportImpl.formatAsMarkdown(report)
  }
}
