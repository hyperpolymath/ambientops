// UrlParser.res - URL parsing and validation
// Re-exports from UrlParserImpl (pure ReScript implementation)

@genType
type parsedUrl = UrlParserImpl.parsedUrl

@genType
type urlType = UrlParserImpl.urlType

@genType
let parse = UrlParserImpl.parse

@genType
let isValid = UrlParserImpl.isValid

@genType
let normalize = UrlParserImpl.normalize

@genType
let getUrlType = UrlParserImpl.getUrlType

@genType
let makeAbsolute = UrlParserImpl.makeAbsolute

@genType
let isSameDomain = UrlParserImpl.isSameDomain

@genType
let extractLinks = UrlParserImpl.extractLinks
