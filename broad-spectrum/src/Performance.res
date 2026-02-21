// Performance.res - Performance metrics collection
// Re-exports from HtmlParserImpl (pure ReScript implementation)

@genType
type resourceTiming = HtmlParserImpl.resourceTiming

@genType
type performanceMetrics = HtmlParserImpl.performanceMetrics

@genType
type performanceResult = {
  metrics: performanceMetrics,
  suggestions: array<string>,
  warnings: array<string>,
}

@genType
let analyze = async (html: string, url: string): performanceResult => {
  let metrics = await HtmlParserImpl.analyzePerformance(html, url)

  let suggestions: array<string> = []
  let warnings: array<string> = []

  // Generate suggestions based on metrics
  if metrics.totalPageSize > 3_000_000 {
    Array.push(suggestions, "Page size exceeds 3MB. Consider optimizing images and assets.")->ignore
  }

  if metrics.resourceCount > 100 {
    Array.push(suggestions, `High number of resources (${Int.toString(metrics.resourceCount)}). Consider bundling assets.`)->ignore
  }

  switch metrics.largestContentfulPaint {
  | Some(lcp) => {
      if lcp > 2500.0 {
        Array.push(warnings, `LCP is ${Float.toString(lcp)}ms (should be < 2.5s). Optimize largest content elements.`)->ignore
      }
    }
  | None => ()
  }

  switch metrics.firstContentfulPaint {
  | Some(fcp) => {
      if fcp > 1800.0 {
        Array.push(warnings, `FCP is ${Float.toString(fcp)}ms (should be < 1.8s). Improve initial render time.`)->ignore
      }
    }
  | None => ()
  }

  switch metrics.cumulativeLayoutShift {
  | Some(cls) => {
      if cls > 0.1 {
        Array.push(warnings, `CLS is ${Float.toString(cls)} (should be < 0.1). Reduce layout shifts.`)->ignore
      }
    }
  | None => ()
  }

  {
    metrics,
    suggestions,
    warnings,
  }
}

@genType
let calculateScore = (metrics: performanceMetrics): float => {
  let score = ref(100.0)

  // Deduct based on page load time
  if metrics.loadComplete > 3000.0 {
    score := score.contents -. 20.0
  } else if metrics.loadComplete > 2000.0 {
    score := score.contents -. 10.0
  } else if metrics.loadComplete > 1000.0 {
    score := score.contents -. 5.0
  }

  // Deduct based on page size
  if metrics.totalPageSize > 5_000_000 {
    score := score.contents -. 20.0
  } else if metrics.totalPageSize > 3_000_000 {
    score := score.contents -. 10.0
  } else if metrics.totalPageSize > 1_000_000 {
    score := score.contents -. 5.0
  }

  // Deduct based on LCP
  switch metrics.largestContentfulPaint {
  | Some(lcp) => {
      if lcp > 4000.0 {
        score := score.contents -. 20.0
      } else if lcp > 2500.0 {
        score := score.contents -. 10.0
      }
    }
  | None => ()
  }

  // Deduct based on CLS
  switch metrics.cumulativeLayoutShift {
  | Some(cls) => {
      if cls > 0.25 {
        score := score.contents -. 15.0
      } else if cls > 0.1 {
        score := score.contents -. 7.0
      }
    }
  | None => ()
  }

  if score.contents < 0.0 {
    0.0
  } else {
    score.contents
  }
}

@genType
let getResourcesByType = (metrics: performanceMetrics): Dict.t<array<resourceTiming>> => {
  let grouped = Dict.make()

  metrics.resources->Array.forEach(resource => {
    let existing = Dict.get(grouped, resource.resourceType)->Option.getOr([])
    Array.push(existing, resource)->ignore
    Dict.set(grouped, resource.resourceType, existing)
  })

  grouped
}

@genType
let getTotalSizeByType = (metrics: performanceMetrics): Dict.t<int> => {
  let sizes = Dict.make()

  metrics.resources->Array.forEach(resource => {
    let existing = Dict.get(sizes, resource.resourceType)->Option.getOr(0)
    Dict.set(sizes, resource.resourceType, existing + resource.size)
  })

  sizes
}

@genType
let formatBytes = (bytes: int): string => {
  let kb = Float.fromInt(bytes) /. 1024.0
  let mb = kb /. 1024.0

  if mb >= 1.0 {
    `${Float.toFixed(mb, ~digits=2)}MB`
  } else if kb >= 1.0 {
    `${Float.toFixed(kb, ~digits=2)}KB`
  } else {
    `${Int.toString(bytes)}B`
  }
}
