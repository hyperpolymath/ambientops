// SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 hyperpolymath

/**
 * NAFA MVP Server - Minimal HTTP server for the MVP demo
 *
 * This server provides:
 * - Static file serving for the client
 * - API endpoints for journey and annotation data
 */

const PORT = 8080;

// Sample journey data (matches ReScript domain types)
const sampleJourney = {
  id: "journey-001",
  title: "Morning Commute to Central Library",
  status: "Planning",
  estimatedMinutes: 35,
  segments: [
    {
      id: "seg-1",
      transportMode: "Walk",
      fromLocation: "Home",
      toLocation: "Oak Street Bus Stop",
      durationMinutes: 5,
      sensoryWarning: null,
      sensoryLevels: { noise: 3, light: 5, crowd: 2 },
    },
    {
      id: "seg-2",
      transportMode: "Bus",
      fromLocation: "Oak Street Bus Stop",
      toLocation: "City Center Station",
      durationMinutes: 15,
      sensoryWarning: "Rush hour: expect moderate crowding",
      sensoryLevels: { noise: 6, light: 4, crowd: 7 },
    },
    {
      id: "seg-3",
      transportMode: "Walk",
      fromLocation: "City Center Station",
      toLocation: "Central Library",
      durationMinutes: 8,
      sensoryWarning: "Construction noise on Main Street",
      sensoryLevels: { noise: 8, light: 6, crowd: 5 },
    },
  ],
  sensoryAnnotations: [],
};

// In-memory storage for annotations (MVP only)
const annotations = new Map();

// Request handler
async function handler(request) {
  const url = new URL(request.url);
  const path = url.pathname;

  // CORS headers for development
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };

  // Handle preflight
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // API routes
  if (path.startsWith("/api/")) {
    const headers = { ...corsHeaders, "Content-Type": "application/json" };

    // GET /api/journey/:id
    if (path.match(/^\/api\/journey\/[\w-]+$/) && request.method === "GET") {
      const journeyId = path.split("/").pop();
      if (journeyId === "journey-001") {
        const journey = {
          ...sampleJourney,
          sensoryAnnotations: Array.from(annotations.values()),
        };
        return new Response(JSON.stringify(journey), { headers });
      }
      return new Response(JSON.stringify({ error: "Journey not found" }), {
        status: 404,
        headers,
      });
    }

    // POST /api/annotation
    if (path === "/api/annotation" && request.method === "POST") {
      try {
        const body = await request.json();
        const annotation = {
          id: `ann-${Date.now()}`,
          locationId: body.locationId,
          locationName: body.locationName,
          noise: body.noise,
          light: body.light,
          crowd: body.crowd,
          notes: body.notes || null,
          timestamp: Date.now(),
        };
        annotations.set(annotation.id, annotation);
        return new Response(JSON.stringify(annotation), {
          status: 201,
          headers,
        });
      } catch {
        return new Response(JSON.stringify({ error: "Invalid request body" }), {
          status: 400,
          headers,
        });
      }
    }

    // GET /api/annotations
    if (path === "/api/annotations" && request.method === "GET") {
      return new Response(JSON.stringify(Array.from(annotations.values())), {
        headers,
      });
    }

    return new Response(JSON.stringify({ error: "Not found" }), {
      status: 404,
      headers,
    });
  }

  // Serve index page with demo info
  if (path === "/" || path === "/index.html") {
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NAFA MVP</title>
  <style>
    body {
      font-family: 'Courier New', monospace;
      background: #1a1a2e;
      color: #eee;
      padding: 2rem;
      max-width: 800px;
      margin: 0 auto;
    }
    pre {
      background: #16213e;
      padding: 1rem;
      border-radius: 8px;
      overflow-x: auto;
    }
    a { color: #4cc9f0; }
    h1 { color: #f72585; }
    .endpoint {
      background: #0f3460;
      padding: 0.5rem 1rem;
      margin: 0.5rem 0;
      border-radius: 4px;
    }
    .method { color: #7209b7; font-weight: bold; }
  </style>
</head>
<body>
  <h1>NAFA MVP Server</h1>
  <p>Neurodiverse App for Adventurers - Journey Planning + Sensory Annotations</p>

  <h2>API Endpoints</h2>
  <div class="endpoint">
    <span class="method">GET</span> /api/journey/journey-001 - Get sample journey
  </div>
  <div class="endpoint">
    <span class="method">GET</span> /api/annotations - List all annotations
  </div>
  <div class="endpoint">
    <span class="method">POST</span> /api/annotation - Create new annotation
  </div>

  <h2>Try It</h2>
  <pre>
# Get the sample journey
curl http://localhost:${PORT}/api/journey/journey-001

# Add a sensory annotation
curl -X POST http://localhost:${PORT}/api/annotation \\
  -H "Content-Type: application/json" \\
  -d '{"locationId":"city-center","locationName":"City Center Station","noise":7,"light":5,"crowd":8,"notes":"Busy during rush hour"}'

# List annotations
curl http://localhost:${PORT}/api/annotations
  </pre>

  <h2>Run CLI Demo</h2>
  <pre>deno task demo</pre>
</body>
</html>`;
    return new Response(html, {
      headers: { ...corsHeaders, "Content-Type": "text/html" },
    });
  }

  return new Response("Not Found", { status: 404, headers: corsHeaders });
}

// Start server
console.log(`
╔══════════════════════════════════════════════════════════════╗
║  NAFA MVP Server                                             ║
║  Listening on http://localhost:${PORT}                          ║
╚══════════════════════════════════════════════════════════════╝
`);

Deno.serve({ port: PORT }, handler);
