// SPDX-License-Identifier: PMPL-1.0-or-later
/**
 * Schema validator for System Tools Contracts
 */

// deno-lint-ignore-file no-explicit-any
import AjvModule from "ajv";
import addFormatsModule from "ajv-formats";
import { loadSchema } from "../schemas/mod.js";

// Handle npm module default exports
const Ajv = AjvModule.default || AjvModule;
const addFormats = addFormatsModule.default || addFormatsModule;

/**
 * Create a validator instance with all schemas loaded
 */
export async function createValidator() {
  const ajv = new Ajv({
    allErrors: true,
    strict: false,
    validateSchema: false,
  });
  addFormats(ajv);

  // Load and add all schemas
  const schemaNames = [
    "evidenceEnvelope",
    "procedurePlan",
    "receipt",
    "systemWeather",
    "messageIntent",
    "runBundle",
    "packManifest",
    "ambientPayload",
  ];

  for (const name of schemaNames) {
    const schema = await loadSchema(name);
    ajv.addSchema(schema, name);
  }

  return new ContractValidator(ajv);
}

export class ContractValidator {
  constructor(ajv) {
    this.ajv = ajv;
  }

  /**
   * Validate data against a named schema
   */
  validate(schemaName, data) {
    const valid = this.ajv.validate(schemaName, data);

    if (valid) {
      return { valid: true };
    }

    return {
      valid: false,
      errors: this.ajv.errors?.map((err) => ({
        path: err.instancePath || "/",
        message: err.message || "Unknown error",
        keyword: err.keyword,
      })),
    };
  }

  /**
   * Validate an Evidence Envelope
   */
  validateEnvelope(data) {
    return this.validate("evidenceEnvelope", data);
  }

  /**
   * Validate a Procedure Plan
   */
  validatePlan(data) {
    return this.validate("procedurePlan", data);
  }

  /**
   * Validate a Receipt
   */
  validateReceipt(data) {
    return this.validate("receipt", data);
  }

  /**
   * Validate a System Weather payload
   */
  validateWeather(data) {
    return this.validate("systemWeather", data);
  }

  /**
   * Validate a Message Intent
   */
  validateIntent(data) {
    return this.validate("messageIntent", data);
  }

  /**
   * Validate a Run Bundle manifest
   */
  validateBundle(data) {
    return this.validate("runBundle", data);
  }

  /**
   * Validate a Pack Manifest
   */
  validatePack(data) {
    return this.validate("packManifest", data);
  }

  /**
   * Validate an Ambient Payload
   */
  validateAmbient(data) {
    return this.validate("ambientPayload", data);
  }
}
