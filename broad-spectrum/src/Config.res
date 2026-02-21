// Config.res - Shared configuration types
// This module breaks circular dependency between Auditor and LinkChecker

@genType
type reportFormat = Console | JSON | HTML | Markdown

@genType
type t = {
  maxDepth: int,
  followExternal: bool,
  timeout: int, // milliseconds
  userAgent: string,
  checkAccessibility: bool,
  checkPerformance: bool,
  checkSEO: bool,
  reportFormat: reportFormat,
  verbose: bool,
  maxConcurrency: int,
  retryAttempts: int,
  retryDelay: int,
}

@genType
let default: t = {
  maxDepth: 3,
  followExternal: false,
  timeout: 30000,
  userAgent: "BroadSpectrum-Auditor/1.0",
  checkAccessibility: true,
  checkPerformance: true,
  checkSEO: true,
  reportFormat: Console,
  verbose: false,
  maxConcurrency: 10,
  retryAttempts: 3,
  retryDelay: 1000,
}

@genType
let make = (
  ~maxDepth=?,
  ~followExternal=?,
  ~timeout=?,
  ~userAgent=?,
  ~checkAccessibility=?,
  ~checkPerformance=?,
  ~checkSEO=?,
  ~reportFormat=?,
  ~verbose=?,
  ~maxConcurrency=?,
  ~retryAttempts=?,
  ~retryDelay=?,
  (),
): t => {
  {
    maxDepth: maxDepth->Option.getOr(default.maxDepth),
    followExternal: followExternal->Option.getOr(default.followExternal),
    timeout: timeout->Option.getOr(default.timeout),
    userAgent: userAgent->Option.getOr(default.userAgent),
    checkAccessibility: checkAccessibility->Option.getOr(default.checkAccessibility),
    checkPerformance: checkPerformance->Option.getOr(default.checkPerformance),
    checkSEO: checkSEO->Option.getOr(default.checkSEO),
    reportFormat: reportFormat->Option.getOr(default.reportFormat),
    verbose: verbose->Option.getOr(default.verbose),
    maxConcurrency: maxConcurrency->Option.getOr(default.maxConcurrency),
    retryAttempts: retryAttempts->Option.getOr(default.retryAttempts),
    retryDelay: retryDelay->Option.getOr(default.retryDelay),
  }
}

@genType
let formatToString = (format: reportFormat): string => {
  switch format {
  | Console => "console"
  | JSON => "json"
  | HTML => "html"
  | Markdown => "markdown"
  }
}

@genType
let formatFromString = (str: string): option<reportFormat> => {
  switch String.toLowerCase(str) {
  | "console" => Some(Console)
  | "json" => Some(JSON)
  | "html" => Some(HTML)
  | "markdown" | "md" => Some(Markdown)
  | _ => None
  }
}
