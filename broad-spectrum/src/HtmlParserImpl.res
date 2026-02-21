// HtmlParserImpl.res - Pure ReScript HTML parsing and performance analysis
// Replaces bindings/htmlParser.ts

@genType
type resourceTiming = {
  url: string,
  resourceType: string,
  size: int,
  transferSize: int,
  duration: float,
}

@genType
type performanceMetrics = {
  firstContentfulPaint: option<float>,
  largestContentfulPaint: option<float>,
  cumulativeLayoutShift: option<float>,
  firstInputDelay: option<float>,
  timeToInteractive: option<float>,
  domContentLoaded: float,
  loadComplete: float,
  totalPageSize: int,
  totalTransferSize: int,
  resourceCount: int,
  resources: array<resourceTiming>,
  score: float,
}

// Helper to extract matches from regex
let extractMatches = (html: string, pattern: Js.Re.t): array<string> => {
  let matches = Js.String2.match_(html, pattern)
  switch matches {
  | Some(arr) => arr
  | None => []
  }
}

// Helper to extract URL from attribute match
let extractUrlFromMatch = (match_: string, prefix: string): option<string> => {
  let cleaned = match_
    ->String.replace(prefix ++ "\"", "")
    ->String.replace(prefix ++ "'", "")
    ->String.replaceAll("\"", "")
    ->String.replaceAll("'", "")
    ->String.trim

  if cleaned !== "" {
    Some(cleaned)
  } else {
    None
  }
}

@genType
let analyzePerformance = async (html: string, _url: string): performanceMetrics => {
  let resources: array<resourceTiming> = []
  let totalSize = ref(String.length(html))
  let totalTransferSize = ref(String.length(html))

  // Extract script tags
  let scriptRe = %re("/<script[^>]*src=[\"']([^\"']+)[\"'][^>]*>/gi")
  let scriptMatches = extractMatches(html, scriptRe)
  scriptMatches->Array.forEach(match_ => {
    switch extractUrlFromMatch(match_, "src=") {
    | Some(url) => {
        Array.push(resources, {
          url,
          resourceType: "script",
          size: 50000,
          transferSize: 20000,
          duration: 150.0,
        })->ignore
        totalSize := totalSize.contents + 50000
        totalTransferSize := totalTransferSize.contents + 20000
      }
    | None => ()
    }
  })

  // Extract stylesheet links
  let linkRe = %re("/<link[^>]*rel=[\"']stylesheet[\"'][^>]*href=[\"']([^\"']+)[\"'][^>]*>/gi")
  let linkMatches = extractMatches(html, linkRe)
  linkMatches->Array.forEach(match_ => {
    switch extractUrlFromMatch(match_, "href=") {
    | Some(url) => {
        Array.push(resources, {
          url,
          resourceType: "stylesheet",
          size: 30000,
          transferSize: 10000,
          duration: 100.0,
        })->ignore
        totalSize := totalSize.contents + 30000
        totalTransferSize := totalTransferSize.contents + 10000
      }
    | None => ()
    }
  })

  // Extract images
  let imgRe = %re("/<img[^>]*src=[\"']([^\"']+)[\"'][^>]*>/gi")
  let imgMatches = extractMatches(html, imgRe)
  imgMatches->Array.forEach(match_ => {
    switch extractUrlFromMatch(match_, "src=") {
    | Some(url) => {
        Array.push(resources, {
          url,
          resourceType: "image",
          size: 150000,
          transferSize: 150000,
          duration: 200.0,
        })->ignore
        totalSize := totalSize.contents + 150000
        totalTransferSize := totalTransferSize.contents + 150000
      }
    | None => ()
    }
  })

  let resourceCount = Array.length(resources)
  let estimatedLoadTime = 500.0 +. Float.fromInt(resourceCount) *. 50.0 +. Float.fromInt(totalSize.contents) /. 50000.0

  let score = Float.fromInt(100) -. Float.fromInt(totalSize.contents) /. 100000.0
  let finalScore = if score < 0.0 { 0.0 } else { score }

  {
    firstContentfulPaint: Some(800.0 +. Float.fromInt(totalSize.contents) /. 100000.0),
    largestContentfulPaint: Some(1200.0 +. Float.fromInt(totalSize.contents) /. 50000.0),
    cumulativeLayoutShift: Some(0.05 +. Float.fromInt(resourceCount) *. 0.01),
    firstInputDelay: None,
    timeToInteractive: Some(estimatedLoadTime *. 1.5),
    domContentLoaded: estimatedLoadTime *. 0.7,
    loadComplete: estimatedLoadTime,
    totalPageSize: totalSize.contents,
    totalTransferSize: totalTransferSize.contents,
    resourceCount,
    resources,
    score: finalScore,
  }
}

@genType
type parsedHtml = {
  title: option<string>,
  metaTags: array<{name: string, content: string}>,
  headings: Dict.t<array<string>>,
}

@genType
let parseHtml = (html: string): parsedHtml => {
  // Extract title
  let titleRe = %re("/<title[^>]*>([^<]+)<\/title>/i")
  let titleMatch = Js.Re.exec_(titleRe, html)
  let title = switch titleMatch {
  | Some(result) => {
      let captures = Js.Re.captures(result)
      switch captures->Array.get(1) {
      | Some(capture) => Js.Nullable.toOption(capture)->Option.map(String.trim)
      | None => None
      }
    }
  | None => None
  }

  // Extract meta tags
  let metaTags: array<{name: string, content: string}> = []
  let metaRe = %re("/<meta[^>]*name=[\"']([^\"']+)[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>/gi")
  let metaMatches = extractMatches(html, metaRe)
  metaMatches->Array.forEach(_match => {
    // Simple extraction - would need more robust parsing in production
    ()
  })

  // Extract headings
  let headings: Dict.t<array<string>> = Dict.make()
  Dict.set(headings, "h1", [])
  Dict.set(headings, "h2", [])
  Dict.set(headings, "h3", [])
  Dict.set(headings, "h4", [])
  Dict.set(headings, "h5", [])
  Dict.set(headings, "h6", [])

  for level in 1 to 6 {
    let tag = `h${Int.toString(level)}`
    let re = Js.Re.fromStringWithFlags(`<${tag}[^>]*>([^<]+)</${tag}>`, ~flags="gi")
    let matches = extractMatches(html, re)
    let headingTexts = matches->Array.filterMap(match_ => {
      // Extract text between tags
      let startTag = `<${tag}`
      let endTag = `</${tag}>`
      if String.includes(match_, startTag) && String.includes(match_, endTag) {
        let text = match_
          ->Js.String2.replaceByRe(%re("/<[^>]+>/g"), "")
          ->String.trim
        if text !== "" { Some(text) } else { None }
      } else {
        None
      }
    })
    Dict.set(headings, tag, headingTexts)
  }

  {
    title,
    metaTags,
    headings,
  }
}

@genType
let extractLinksFromHtml = (html: string, baseUrl: string): array<string> => {
  UrlParserImpl.extractLinks(html, baseUrl)
}
