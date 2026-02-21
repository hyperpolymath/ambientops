// SeoParserImpl.res - Pure ReScript SEO analysis
// Replaces bindings/seoParser.ts

@genType
type metaTag = {
  name: string,
  content: string,
}

@genType
type seoData = {
  title: option<string>,
  description: option<string>,
  keywords: option<string>,
  canonical: option<string>,
  ogTags: Dict.t<string>,
  twitterTags: Dict.t<string>,
  metaTags: array<metaTag>,
  headings: Dict.t<array<string>>,
  images: int,
  imagesWithAlt: int,
  links: int,
  internalLinks: int,
  externalLinks: int,
  wordCount: int,
  lang: option<string>,
  viewport: option<string>,
  robots: option<string>,
  structuredData: bool,
}

// Helper to extract single regex match group
let extractMatch = (html: string, pattern: Js.Re.t): option<string> => {
  let result = Js.Re.exec_(pattern, html)
  switch result {
  | Some(match_) => {
      let captures = Js.Re.captures(match_)
      switch captures->Array.get(1) {
      | Some(capture) => Js.Nullable.toOption(capture)->Option.map(String.trim)
      | None => None
      }
    }
  | None => None
  }
}

// Helper to count regex matches
let countMatches = (html: string, pattern: Js.Re.t): int => {
  switch Js.String2.match_(html, pattern) {
  | Some(matches) => Array.length(matches)
  | None => 0
  }
}

@genType
let analyzeSEO = async (html: string, url: string): seoData => {
  let metaTags: array<metaTag> = []
  let ogTags: Dict.t<string> = Dict.make()
  let twitterTags: Dict.t<string> = Dict.make()
  let headings: Dict.t<array<string>> = Dict.make()

  // Initialize headings
  Dict.set(headings, "h1", [])
  Dict.set(headings, "h2", [])
  Dict.set(headings, "h3", [])
  Dict.set(headings, "h4", [])
  Dict.set(headings, "h5", [])
  Dict.set(headings, "h6", [])

  // Extract title
  let titleRe = %re("/<title[^>]*>([^<]+)<\/title>/i")
  let title = extractMatch(html, titleRe)

  // Extract meta description
  let descRe = %re("/<meta[^>]*name=[\"']description[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>/i")
  let description = extractMatch(html, descRe)

  // Extract keywords
  let keywordsRe = %re("/<meta[^>]*name=[\"']keywords[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>/i")
  let keywords = extractMatch(html, keywordsRe)

  // Extract canonical URL
  let canonicalRe = %re("/<link[^>]*rel=[\"']canonical[\"'][^>]*href=[\"']([^\"']+)[\"'][^>]*>/i")
  let canonical = extractMatch(html, canonicalRe)

  // Extract viewport
  let viewportRe = %re("/<meta[^>]*name=[\"']viewport[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>/i")
  let viewport = extractMatch(html, viewportRe)

  // Extract robots
  let robotsRe = %re("/<meta[^>]*name=[\"']robots[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>/i")
  let robots = extractMatch(html, robotsRe)

  // Extract lang
  let langRe = %re("/<html[^>]*lang=[\"']([^\"']+)[\"'][^>]*>/i")
  let lang = extractMatch(html, langRe)

  // Extract headings
  for level in 1 to 6 {
    let tag = `h${Int.toString(level)}`
    let re = Js.Re.fromStringWithFlags(`<${tag}[^>]*>([^<]+)</${tag}>`, ~flags="gi")
    let matches = Js.String2.match_(html, re)
    let headingTexts: array<string> = switch matches {
    | Some(arr) => arr->Array.filterMap(match_ => {
        let text = match_
          ->Js.String2.replaceByRe(%re("/<[^>]+>/g"), "")
          ->String.trim
        if text !== "" { Some(text) } else { None }
      })
    | None => []
    }
    Dict.set(headings, tag, headingTexts)
  }

  // Count images and alt text
  let imgRe = %re("/<img[^>]*>/gi")
  let imgMatches = Js.String2.match_(html, imgRe)
  let images = ref(0)
  let imagesWithAlt = ref(0)
  switch imgMatches {
  | Some(matches) => {
      matches->Array.forEach(imgTag => {
        images := images.contents + 1
        if String.includes(imgTag, "alt=") {
          imagesWithAlt := imagesWithAlt.contents + 1
        }
      })
    }
  | None => ()
  }

  // Count links
  let linkRe = %re("/<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>/gi")
  let linkMatches = Js.String2.match_(html, linkRe)
  let links = ref(0)
  let internalLinks = ref(0)
  let externalLinks = ref(0)

  // Get hostname from URL
  let hostname = switch UrlParserImpl.parseUrl(url) {
  | Some(parsed) => parsed.hostname
  | None => ""
  }

  switch linkMatches {
  | Some(matches) => {
      matches->Array.forEach(linkTag => {
        links := links.contents + 1
        // Extract href
        let hrefRe = %re("/href=[\"']([^\"']+)[\"']/i")
        let href = extractMatch(linkTag, hrefRe)
        switch href {
        | Some(hrefUrl) => {
            if String.startsWith(hrefUrl, "http") {
              switch UrlParserImpl.parseUrl(hrefUrl) {
              | Some(parsed) => {
                  if parsed.hostname === hostname {
                    internalLinks := internalLinks.contents + 1
                  } else {
                    externalLinks := externalLinks.contents + 1
                  }
                }
              | None => ()
              }
            } else {
              internalLinks := internalLinks.contents + 1
            }
          }
        | None => ()
        }
      })
    }
  | None => ()
  }

  // Count words in body
  let bodyRe = %re("/<body[^>]*>([\s\S]*)<\/body>/i")
  let bodyMatch = extractMatch(html, bodyRe)
  let bodyText = switch bodyMatch {
  | Some(body) => body
  | None => html
  }
  let textContent = bodyText
    ->Js.String2.replaceByRe(%re("/<[^>]+>/g"), " ")
    ->Js.String2.replaceByRe(%re("/\s+/g"), " ")
    ->String.trim
  let words = textContent->String.split(" ")->Array.filter(word => String.length(word) > 0)
  let wordCount = Array.length(words)

  // Check for structured data
  let structuredData = String.includes(html, "application/ld+json") ||
    String.includes(html, "schema.org")

  {
    title,
    description,
    keywords,
    canonical,
    ogTags,
    twitterTags,
    metaTags,
    headings,
    images: images.contents,
    imagesWithAlt: imagesWithAlt.contents,
    links: links.contents,
    internalLinks: internalLinks.contents,
    externalLinks: externalLinks.contents,
    wordCount,
    lang,
    viewport,
    robots,
    structuredData,
  }
}
