// SPDX-License-Identifier: PMPL-1.0-or-later
/**
 * Schema validation tests for System Tools Contracts
 */

import { assertEquals, assertExists } from "@std/assert";
import { describe, it } from "@std/testing/bdd";
import { createValidator } from "../lib/validator.js";
import { loadAllSchemas, loadSchema, SCHEMA_FILES } from "../schemas/mod.js";

describe("Schema Loading", () => {
  it("should load all schema files", async () => {
    const schemas = await loadAllSchemas();
    const schemaNames = Object.keys(SCHEMA_FILES);

    for (const name of schemaNames) {
      assertExists(schemas[name], `Schema ${name} should be loaded`);
    }
  });

  it("should have valid JSON Schema structure", async () => {
    const schemaNames = Object.keys(SCHEMA_FILES);

    for (const name of schemaNames) {
      const schema = await loadSchema(name);
      assertExists(schema.$schema, `${name} should have $schema`);
      assertExists(schema.$id, `${name} should have $id`);
      assertExists(schema.title, `${name} should have title`);
      assertExists(schema.type, `${name} should have type`);
    }
  });
});

describe("Evidence Envelope Validation", () => {
  it("should validate a valid envelope", async () => {
    const validator = await createValidator();

    const validEnvelope = {
      version: "1.0.0",
      envelope_id: "550e8400-e29b-41d4-a716-446655440000",
      created_at: "2026-01-02T20:00:00Z",
      source: {
        tool: "big-up",
        host: {
          hostname: "test-machine",
        },
      },
      artifacts: [],
    };

    const result = validator.validateEnvelope(validEnvelope);
    assertEquals(result.valid, true, `Errors: ${JSON.stringify(result.errors)}`);
  });

  it("should reject envelope without required fields", async () => {
    const validator = await createValidator();

    const invalidEnvelope = {
      version: "1.0.0",
      // missing envelope_id, created_at, source, artifacts
    };

    const result = validator.validateEnvelope(invalidEnvelope);
    assertEquals(result.valid, false);
    assertExists(result.errors);
  });

  it("should reject invalid tool name", async () => {
    const validator = await createValidator();

    const invalidEnvelope = {
      version: "1.0.0",
      envelope_id: "550e8400-e29b-41d4-a716-446655440000",
      created_at: "2026-01-02T20:00:00Z",
      source: {
        tool: "invalid-tool",
        host: { hostname: "test" },
      },
      artifacts: [],
    };

    const result = validator.validateEnvelope(invalidEnvelope);
    assertEquals(result.valid, false);
  });
});

describe("Procedure Plan Validation", () => {
  it("should validate a valid plan", async () => {
    const validator = await createValidator();

    const validPlan = {
      version: "1.0.0",
      plan_id: "550e8400-e29b-41d4-a716-446655440001",
      created_at: "2026-01-02T20:00:00Z",
      envelope_ref: "550e8400-e29b-41d4-a716-446655440000",
      steps: [
        {
          step_id: "step-1",
          order: 1,
          action: "clear_temp",
          title: "Clear temporary files",
        },
      ],
    };

    const result = validator.validatePlan(validPlan);
    assertEquals(result.valid, true, `Errors: ${JSON.stringify(result.errors)}`);
  });

  it("should require at least one step", async () => {
    const validator = await createValidator();

    const invalidPlan = {
      version: "1.0.0",
      plan_id: "550e8400-e29b-41d4-a716-446655440001",
      created_at: "2026-01-02T20:00:00Z",
      envelope_ref: "550e8400-e29b-41d4-a716-446655440000",
      steps: [],
    };

    const result = validator.validatePlan(invalidPlan);
    assertEquals(result.valid, false);
  });
});

describe("Receipt Validation", () => {
  it("should validate a valid receipt", async () => {
    const validator = await createValidator();

    const validReceipt = {
      version: "1.0.0",
      receipt_id: "550e8400-e29b-41d4-a716-446655440002",
      created_at: "2026-01-02T20:00:00Z",
      plan_ref: "550e8400-e29b-41d4-a716-446655440001",
      envelope_ref: "550e8400-e29b-41d4-a716-446655440000",
      status: "completed",
      steps_executed: [],
    };

    const result = validator.validateReceipt(validReceipt);
    assertEquals(result.valid, true, `Errors: ${JSON.stringify(result.errors)}`);
  });

  it("should reject invalid status", async () => {
    const validator = await createValidator();

    const invalidReceipt = {
      version: "1.0.0",
      receipt_id: "550e8400-e29b-41d4-a716-446655440002",
      created_at: "2026-01-02T20:00:00Z",
      plan_ref: "550e8400-e29b-41d4-a716-446655440001",
      envelope_ref: "550e8400-e29b-41d4-a716-446655440000",
      status: "invalid-status",
      steps_executed: [],
    };

    const result = validator.validateReceipt(invalidReceipt);
    assertEquals(result.valid, false);
  });
});

describe("System Weather Validation", () => {
  it("should validate a valid weather payload", async () => {
    const validator = await createValidator();

    const validWeather = {
      version: "1.0.0",
      timestamp: "2026-01-02T20:00:00Z",
      state: "calm",
      summary: "All systems operating normally",
    };

    const result = validator.validateWeather(validWeather);
    assertEquals(result.valid, true, `Errors: ${JSON.stringify(result.errors)}`);
  });

  it("should only allow calm/watch/act states", async () => {
    const validator = await createValidator();

    const invalidWeather = {
      version: "1.0.0",
      timestamp: "2026-01-02T20:00:00Z",
      state: "critical",
      summary: "Invalid state",
    };

    const result = validator.validateWeather(invalidWeather);
    assertEquals(result.valid, false);
  });
});

describe("Pack Manifest Validation", () => {
  it("should validate a valid pack manifest", async () => {
    const validator = await createValidator();

    const validPack = {
      version: "1.0.0",
      pack_id: "windows-tech-support",
      name: "Windows Tech Support Pack",
      platform: {
        os: ["windows"],
      },
      checks: [],
    };

    const result = validator.validatePack(validPack);
    assertEquals(result.valid, true, `Errors: ${JSON.stringify(result.errors)}`);
  });

  it("should reject invalid pack_id format", async () => {
    const validator = await createValidator();

    const invalidPack = {
      version: "1.0.0",
      pack_id: "Invalid Pack ID",
      name: "Test Pack",
      platform: { os: ["windows"] },
      checks: [],
    };

    const result = validator.validatePack(invalidPack);
    assertEquals(result.valid, false);
  });
});

describe("Ambient Payload Validation", () => {
  it("should validate a valid ambient payload", async () => {
    const validator = await createValidator();

    const validAmbient = {
      version: "1.0.0",
      timestamp: "2026-01-02T20:00:00Z",
      indicator: {
        state: "calm",
      },
    };

    const result = validator.validateAmbient(validAmbient);
    assertEquals(result.valid, true, `Errors: ${JSON.stringify(result.errors)}`);
  });
});
