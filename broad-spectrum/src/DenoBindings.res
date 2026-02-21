// DenoBindings.res - Direct bindings to Deno and Web APIs
// This module provides ReScript bindings without TypeScript intermediaries

// Deno global object bindings
@scope("Deno") @val external args: array<string> = "args"
@scope("Deno") @val external exit: int => unit = "exit"
@scope("Deno") @val external readTextFile: string => promise<string> = "readTextFile"

// Deno.stat for file existence checks
type fileInfo
@scope("Deno") @val external stat: string => promise<fileInfo> = "stat"

// Console bindings
@scope("console") @val external consoleLog: string => unit = "log"
@scope("console") @val external consoleError: string => unit = "error"

// Fetch API bindings
type requestInit = {
  method: string,
  headers: Dict.t<string>,
  signal: option<{..}>,
}

type response = {
  status: int,
  statusText: string,
  ok: bool,
  redirected: bool,
  url: string,
}

@val external fetch: (string, requestInit) => promise<response> = "fetch"

// Response methods
@send external text: response => promise<string> = "text"
@send external responseHeaders: response => {..} = "headers"

// Headers iteration
@send external headersForEach: ({..}, (string, string) => unit) => unit = "forEach"

// AbortController
type abortController = {signal: {..}}
@new external makeAbortController: unit => abortController = "AbortController"
@send external abort: abortController => unit = "abort"

// Timer functions
@val external setTimeout: (unit => unit, int) => float = "setTimeout"
@val external clearTimeout: float => unit = "clearTimeout"

// Performance API
@scope("performance") @val external now: unit => float = "now"

// URL API bindings
type url = {
  href: string,
  protocol: string,
  hostname: string,
  pathname: string,
  search: string,
  hash: string,
  origin: string,
}

@new external makeUrl: string => url = "URL"
@new external makeUrlWithBase: (string, string) => url = "URL"

// URLSearchParams
type urlSearchParams
@new external makeSearchParams: string => urlSearchParams = "URLSearchParams"
@send external searchParamsEntries: urlSearchParams => {..} = "entries"
@send external searchParamsToString: urlSearchParams => string = "toString"

// RegExp bindings for HTML parsing
@val external regExpMatchAll: (string, Js.Re.t) => Js.Array2.array_like<Js.Re.result> = "matchAll"

// Date API
module Date = {
  @scope("Date") @val external now: unit => float = "now"
  @new external make: float => {..} = "Date"
  @send external toLocaleString: {..} => string = "toLocaleString"
}

// JSON utilities
@scope("JSON") @val external stringify: ('a, Js.Null.t<'b>, int) => string = "stringify"
@scope("JSON") @val external parse: string => 'a = "parse"

// Array.from for iterator conversion
@scope("Array") @val external arrayFrom: {..} => array<'a> = "from"
