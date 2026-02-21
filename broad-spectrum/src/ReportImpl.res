// ReportImpl.res - Pure ReScript report formatting
// Replaces bindings/report.ts

// HTML character escaping
let escapeHtml = (text: string): string => {
  text
    ->String.replaceAll("&", "&amp;")
    ->String.replaceAll("<", "&lt;")
    ->String.replaceAll(">", "&gt;")
    ->String.replaceAll("\"", "&quot;")
    ->String.replaceAll("'", "&#039;")
}

// Format bytes to human readable
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

// Calculate performance score
let calculatePerformanceScore = (metrics: HtmlParserImpl.performanceMetrics): float => {
  let score = ref(100.0)
  if metrics.loadComplete > 3000.0 {
    score := score.contents -. 20.0
  } else if metrics.loadComplete > 2000.0 {
    score := score.contents -. 10.0
  }
  if metrics.totalPageSize > 3000000 {
    score := score.contents -. 10.0
  }
  if score.contents < 0.0 { 0.0 } else { score.contents }
}

// Get score CSS class
let getScoreClass = (score: float): string => {
  if score >= 90.0 { "score-excellent" }
  else if score >= 70.0 { "score-good" }
  else if score >= 50.0 { "score-fair" }
  else { "score-poor" }
}

@genType
let formatAsJSON = (report: 'a): string => {
  DenoBindings.stringify(report, Js.Null.empty, 2)
}

@genType
let formatAsHTML = async (report: 'a): string => {
  // Type assertions for report fields
  let url: string = %raw(`report.url`)
  let timestamp: string = %raw(`report.timestamp`)
  let executionTime: float = %raw(`report.executionTime`)
  let overallScore: float = %raw(`report.overallScore`)

  let html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Website Audit Report - ${escapeHtml(url)}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      line-height: 1.6;
      color: #333;
      background: #f5f5f5;
      padding: 20px;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
      background: white;
      padding: 40px;
      border-radius: 8px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    h1 { color: #2c3e50; margin-bottom: 10px; }
    h2 { color: #34495e; margin-top: 30px; margin-bottom: 15px; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
    .meta { color: #7f8c8d; margin-bottom: 30px; }
    .score {
      font-size: 48px;
      font-weight: bold;
      text-align: center;
      padding: 30px;
      margin: 20px 0;
      border-radius: 8px;
    }
    .score-excellent { background: #d4edda; color: #155724; }
    .score-good { background: #d1ecf1; color: #0c5460; }
    .score-fair { background: #fff3cd; color: #856404; }
    .score-poor { background: #f8d7da; color: #721c24; }
    .metric { display: flex; justify-content: space-between; padding: 10px; border-bottom: 1px solid #eee; }
    .metric-label { font-weight: 500; }
    .metric-value { color: #555; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Website Audit Report</h1>
    <div class="meta">
      <div><strong>URL:</strong> ${escapeHtml(url)}</div>
      <div><strong>Generated:</strong> ${DenoBindings.Date.toLocaleString(DenoBindings.Date.make(Float.fromString(timestamp)->Option.getOr(0.0)))}</div>
      <div><strong>Execution Time:</strong> ${Float.toFixed(executionTime /. 1000.0, ~digits=2)}s</div>
    </div>
    <div class="score ${getScoreClass(overallScore)}">
      Overall Score: ${Float.toFixed(overallScore, ~digits=1)}/100
    </div>
  </div>
</body>
</html>`

  html
}

@genType
let formatAsMarkdown = (report: 'a): string => {
  let url: string = %raw(`report.url`)
  let timestamp: string = %raw(`report.timestamp`)
  let executionTime: float = %raw(`report.executionTime`)
  let overallScore: float = %raw(`report.overallScore`)

  let lines: array<string> = []

  Array.push(lines, "# Website Audit Report\n")->ignore
  Array.push(lines, `**URL:** ${url}`)->ignore
  Array.push(lines, `**Generated:** ${DenoBindings.Date.toLocaleString(DenoBindings.Date.make(Float.fromString(timestamp)->Option.getOr(0.0)))}`)->ignore
  Array.push(lines, `**Execution Time:** ${Float.toFixed(executionTime /. 1000.0, ~digits=2)}s`)->ignore
  Array.push(lines, `**Overall Score:** ${Float.toFixed(overallScore, ~digits=1)}/100\n`)->ignore

  Array.join(lines, "\n")
}
