// Fetcher.res - HTTP request handling with retry logic
// Re-exports from FetcherImpl (pure ReScript implementation)

@genType
type httpMethod = FetcherImpl.httpMethod

@genType
type httpResponse = FetcherImpl.httpResponse

@genType
type fetchError = FetcherImpl.fetchError

@genType
let fetch = FetcherImpl.fetch

@genType
let fetchWithMethod = FetcherImpl.fetchWithMethod

@genType
let fetchWithRetry = FetcherImpl.fetchWithRetry

@genType
let isSuccessStatus = FetcherImpl.isSuccessStatus

@genType
let isRedirectStatus = FetcherImpl.isRedirectStatus

@genType
let isClientErrorStatus = FetcherImpl.isClientErrorStatus

@genType
let isServerErrorStatus = FetcherImpl.isServerErrorStatus

@genType
let getContentType = FetcherImpl.getContentType

@genType
let isHtmlContent = FetcherImpl.isHtmlContent
