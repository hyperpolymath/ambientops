// UrlParser_test.res - Tests for URL parsing functionality

// Simple test framework
let assertEqual = (name: string, actual: 'a, expected: 'a) => {
  if actual === expected {
    DenoBindings.consoleLog(`PASS: ${name}`)
    true
  } else {
    DenoBindings.consoleError(`FAIL: ${name}`)
    DenoBindings.consoleError(`  Expected: ${%raw(`String(expected)`)}`)
    DenoBindings.consoleError(`  Actual: ${%raw(`String(actual)`)}`)
    false
  }
}

let assertTrue = (name: string, condition: bool) => {
  assertEqual(name, condition, true)
}

let assertFalse = (name: string, condition: bool) => {
  assertEqual(name, condition, false)
}

let assertSome = (name: string, opt: option<'a>) => {
  switch opt {
  | Some(_) => {
      DenoBindings.consoleLog(`PASS: ${name}`)
      true
    }
  | None => {
      DenoBindings.consoleError(`FAIL: ${name} - Expected Some, got None`)
      false
    }
  }
}

let assertNone = (name: string, opt: option<'a>) => {
  switch opt {
  | None => {
      DenoBindings.consoleLog(`PASS: ${name}`)
      true
    }
  | Some(_) => {
      DenoBindings.consoleError(`FAIL: ${name} - Expected None, got Some`)
      false
    }
  }
}

let runTests = () => {
  DenoBindings.consoleLog("\n=== URL Parser Tests ===\n")

  let passed = ref(0)
  let failed = ref(0)

  // Test parseUrl - valid HTTP URL
  let result1 = UrlParserImpl.parseUrl("https://example.com/path?query=value#hash")
  if assertSome("parseUrl - valid HTTP URL", result1) {
    passed := passed.contents + 1
    switch result1 {
    | Some(url) => {
        if assertEqual("parseUrl - protocol", url.protocol, "https:") {
          passed := passed.contents + 1
        } else {
          failed := failed.contents + 1
        }
        if assertEqual("parseUrl - hostname", url.hostname, "example.com") {
          passed := passed.contents + 1
        } else {
          failed := failed.contents + 1
        }
        if assertEqual("parseUrl - pathname", url.pathname, "/path") {
          passed := passed.contents + 1
        } else {
          failed := failed.contents + 1
        }
      }
    | None => ()
    }
  } else {
    failed := failed.contents + 1
  }

  // Test parseUrl - invalid URL
  let result2 = UrlParserImpl.parseUrl("not-a-valid-url")
  if assertNone("parseUrl - invalid URL returns None", result2) {
    passed := passed.contents + 1
  } else {
    failed := failed.contents + 1
  }

  // Test isValidUrl
  if assertTrue("isValidUrl - HTTPS URL", UrlParserImpl.isValidUrl("https://example.com")) {
    passed := passed.contents + 1
  } else {
    failed := failed.contents + 1
  }

  if assertTrue("isValidUrl - HTTP URL", UrlParserImpl.isValidUrl("http://example.org")) {
    passed := passed.contents + 1
  } else {
    failed := failed.contents + 1
  }

  if assertFalse("isValidUrl - FTP URL", UrlParserImpl.isValidUrl("ftp://example.com")) {
    passed := passed.contents + 1
  } else {
    failed := failed.contents + 1
  }

  if assertFalse("isValidUrl - invalid URL", UrlParserImpl.isValidUrl("not-a-url")) {
    passed := passed.contents + 1
  } else {
    failed := failed.contents + 1
  }

  // Test normalizeUrl
  let normalized = UrlParserImpl.normalizeUrl("https://example.com/path/")
  if assertEqual("normalizeUrl - removes trailing slash", normalized, "https://example.com/path") {
    passed := passed.contents + 1
  } else {
    failed := failed.contents + 1
  }

  // Print summary
  DenoBindings.consoleLog(`\n=== Results ===`)
  DenoBindings.consoleLog(`Passed: ${Int.toString(passed.contents)}`)
  DenoBindings.consoleLog(`Failed: ${Int.toString(failed.contents)}`)

  if failed.contents > 0 {
    DenoBindings.exit(1)
  }
}

let _ = runTests()
