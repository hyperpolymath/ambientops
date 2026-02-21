// UrlParserImpl.res - Pure ReScript URL parsing implementation
// Replaces bindings/ada.ts

@genType
type parsedUrl = {
  href: string,
  protocol: string,
  hostname: string,
  pathname: string,
  search: string,
  hash: string,
  origin: string,
}

@genType
type urlType = Internal | External | Relative | Invalid

// URL parsing using native URL API
@genType
let parseUrl = (urlString: string): option<parsedUrl> => {
  try {
    let url = DenoBindings.makeUrl(urlString)
    Some({
      href: url.href,
      protocol: url.protocol,
      hostname: url.hostname,
      pathname: url.pathname,
      search: url.search,
      hash: url.hash,
      origin: url.origin,
    })
  } catch {
  | _ => None
  }
}

@genType
let isValidUrl = (urlString: string): bool => {
  try {
    let url = DenoBindings.makeUrl(urlString)
    url.protocol === "http:" || url.protocol === "https:"
  } catch {
  | _ => false
  }
}

@genType
let normalizeUrl = (urlString: string): string => {
  try {
    let url = DenoBindings.makeUrl(urlString)

    // Remove trailing slash from pathname (except for root)
    let pathname = if String.length(url.pathname) > 1 && String.endsWith(url.pathname, "/") {
      String.slice(url.pathname, ~start=0, ~end=-1)
    } else {
      url.pathname
    }

    // Sort query parameters
    let searchParams = DenoBindings.makeSearchParams(url.search)
    let entries = DenoBindings.searchParamsEntries(searchParams)
    let entriesArray: array<(string, string)> = DenoBindings.arrayFrom(entries)
    let sortedEntries = Array.toSorted(entriesArray, (a, b) => {
      let (keyA, _) = a
      let (keyB, _) = b
      String.localeCompare(keyA, keyB)
    })

    let search = if Array.length(sortedEntries) > 0 {
      let params = sortedEntries->Array.map(((k, v)) => `${k}=${v}`)->Array.join("&")
      `?${params}`
    } else {
      ""
    }

    url.origin ++ pathname ++ search
  } catch {
  | _ => urlString
  }
}

@genType
let parse = (url: string): option<parsedUrl> => {
  parseUrl(url)
}

@genType
let isValid = (url: string): bool => {
  isValidUrl(url)
}

@genType
let normalize = (url: string): string => {
  normalizeUrl(url)
}

@genType
let getUrlType = (url: string, baseUrl: string): urlType => {
  switch parse(url) {
  | None => Invalid
  | Some(parsed) => {
      switch parse(baseUrl) {
      | None => Invalid
      | Some(baseParsed) => {
          if parsed.hostname === baseParsed.hostname {
            Internal
          } else if parsed.protocol === "http:" || parsed.protocol === "https:" {
            External
          } else {
            Invalid
          }
        }
      }
    }
  }
}

@genType
let makeAbsolute = (url: string, baseUrl: string): option<string> => {
  if String.startsWith(url, "http://") || String.startsWith(url, "https://") {
    Some(url)
  } else {
    switch parse(baseUrl) {
    | None => None
    | Some(base) => {
        let absoluteUrl = if String.startsWith(url, "/") {
          base.origin ++ url
        } else if String.startsWith(url, "#") {
          base.origin ++ base.pathname ++ url
        } else if String.startsWith(url, "?") {
          base.origin ++ base.pathname ++ url
        } else {
          let basePath = base.pathname
          let lastSlash = String.lastIndexOf(basePath, "/")
          let dir = String.substring(basePath, ~start=0, ~end=lastSlash + 1)
          base.origin ++ dir ++ url
        }
        Some(absoluteUrl)
      }
    }
  }
}

@genType
let isSameDomain = (url1: string, url2: string): bool => {
  switch (parse(url1), parse(url2)) {
  | (Some(parsed1), Some(parsed2)) => parsed1.hostname === parsed2.hostname
  | _ => false
  }
}

// HTML link extraction
@genType
let extractLinks = (html: string, baseUrl: string): array<string> => {
  let links: array<string> = []
  let seen: Dict.t<bool> = Dict.make()

  // Extract href attributes using regex
  let hrefRe = %re("/href=[\"']([^\"']+)[\"']/gi")
  let hrefMatches = Js.String2.match_(html, hrefRe)
  switch hrefMatches {
  | Some(matches) => {
      matches->Array.forEach(match_ => {
        // Extract the URL from the match
        let url = match_
          ->String.replace("href=\"", "")
          ->String.replace("href='", "")
          ->String.replaceAll("\"", "")
          ->String.replaceAll("'", "")
          ->String.trim

        if (
          url !== "" &&
          !String.startsWith(url, "javascript:") &&
          !String.startsWith(url, "mailto:") &&
          !String.startsWith(url, "tel:") &&
          !String.startsWith(url, "#") &&
          Dict.get(seen, url)->Option.isNone
        ) {
          // Make URL absolute and add to list
          switch makeAbsolute(url, baseUrl) {
          | Some(absUrl) =>
            if isValid(absUrl) {
              Array.push(links, absUrl)->ignore
              Dict.set(seen, url, true)
            }
          | None => ()
          }
        }
      })
    }
  | None => ()
  }

  // Extract src attributes
  let srcRe = %re("/src=[\"']([^\"']+)[\"']/gi")
  let srcMatches = Js.String2.match_(html, srcRe)
  switch srcMatches {
  | Some(matches) => {
      matches->Array.forEach(match_ => {
        let url = match_
          ->String.replace("src=\"", "")
          ->String.replace("src='", "")
          ->String.replaceAll("\"", "")
          ->String.replaceAll("'", "")
          ->String.trim

        if url !== "" && Dict.get(seen, url)->Option.isNone {
          switch makeAbsolute(url, baseUrl) {
          | Some(absUrl) =>
            if isValid(absUrl) {
              Array.push(links, absUrl)->ignore
              Dict.set(seen, url, true)
            }
          | None => ()
          }
        }
      })
    }
  | None => ()
  }

  links
}
