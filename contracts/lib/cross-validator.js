// SPDX-License-Identifier: PMPL-1.0-or-later
/**
 * Cross-Schema Reference Validator (CRIT-004 fix)
 *
 * Validates that references between schemas are valid:
 * - Evidence envelope artifact references
 * - Envelope -> Plan references
 * - Plan -> Receipt references
 * - Finding -> Evidence references
 */

/**
 * Registry of known entities for cross-reference validation
 */
export class EntityRegistry {
  constructor() {
    this.envelopes = new Map();
    this.plans = new Map();
    this.receipts = new Map();
    this.artifacts = new Map();
  }

  registerEnvelope(id, envelope) {
    this.envelopes.set(id, envelope);
    // Also register all artifacts from this envelope
    for (const artifact of envelope.artifact_ids) {
      this.artifacts.set(artifact, { envelope_id: id });
    }
  }

  registerPlan(id, plan) {
    this.plans.set(id, plan);
  }

  registerReceipt(id, receipt) {
    this.receipts.set(id, receipt);
  }

  hasEnvelope(id) {
    return this.envelopes.has(id);
  }

  hasPlan(id) {
    return this.plans.has(id);
  }

  hasReceipt(id) {
    return this.receipts.has(id);
  }

  hasArtifact(id) {
    return this.artifacts.has(id);
  }

  getEnvelope(id) {
    return this.envelopes.get(id);
  }

  clear() {
    this.envelopes.clear();
    this.plans.clear();
    this.receipts.clear();
    this.artifacts.clear();
  }
}

/**
 * Validate cross-references within an evidence envelope
 */
export function validateEnvelopeInternalRefs(envelope) {
  const errors = [];
  const warnings = [];

  const envelopeId = envelope.envelope_id;
  const artifacts = envelope.artifacts || [];
  const findings = envelope.findings || [];

  // Build set of artifact IDs
  const artifactIds = new Set(
    artifacts.map((a) => a.artifact_id).filter(Boolean),
  );

  // Validate finding evidence_refs point to actual artifacts
  for (const finding of findings) {
    const findingId = finding.finding_id;
    const evidenceRefs = finding.evidence_refs || [];

    for (const ref of evidenceRefs) {
      if (!artifactIds.has(ref)) {
        errors.push({
          type: "missing_reference",
          source_schema: "evidence-envelope",
          source_id: envelopeId,
          target_schema: "artifact",
          target_id: ref,
          field: `findings[${findingId}].evidence_refs`,
          message: `Finding "${findingId}" references non-existent artifact "${ref}"`,
        });
      }
    }
  }

  // Check for parent envelope reference (can't validate without registry)
  const provenance = envelope.provenance;
  if (provenance?.parent_envelope_id) {
    warnings.push({
      type: "unverified_reference",
      message: `Parent envelope "${provenance.parent_envelope_id}" cannot be verified without registry`,
    });
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

/**
 * Validate cross-references between related documents
 */
export function validateCrossReferences(registry, documents) {
  const errors = [];
  const warnings = [];

  // Register all envelopes
  for (const envelope of documents.envelopes || []) {
    const id = envelope.envelope_id;
    const artifacts = envelope.artifacts || [];
    registry.registerEnvelope(id, {
      artifact_ids: artifacts.map((a) => a.artifact_id),
      parent_envelope_id: envelope.provenance?.parent_envelope_id,
    });
  }

  // Register all plans
  for (const plan of documents.plans || []) {
    const id = plan.plan_id;
    registry.registerPlan(id, {
      envelope_id: plan.source_envelope_id,
      receipt_id: plan.receipt_id,
    });
  }

  // Register all receipts
  for (const receipt of documents.receipts || []) {
    const id = receipt.receipt_id;
    registry.registerReceipt(id, {
      plan_id: receipt.plan_id,
      envelope_id: receipt.envelope_id,
    });
  }

  // Now validate all cross-references

  // Validate envelope -> parent envelope
  for (const envelope of documents.envelopes || []) {
    const id = envelope.envelope_id;
    const provenance = envelope.provenance;
    const parentId = provenance?.parent_envelope_id;

    if (parentId && !registry.hasEnvelope(parentId)) {
      errors.push({
        type: "missing_reference",
        source_schema: "evidence-envelope",
        source_id: id,
        target_schema: "evidence-envelope",
        target_id: parentId,
        field: "provenance.parent_envelope_id",
        message: `Envelope "${id}" references non-existent parent envelope "${parentId}"`,
      });
    }

    // Check for circular reference
    if (parentId === id) {
      errors.push({
        type: "circular_reference",
        source_schema: "evidence-envelope",
        source_id: id,
        target_schema: "evidence-envelope",
        target_id: parentId,
        field: "provenance.parent_envelope_id",
        message: `Envelope "${id}" references itself as parent`,
      });
    }

    // Validate internal refs
    const internalResult = validateEnvelopeInternalRefs(envelope);
    errors.push(...internalResult.errors);
    warnings.push(...internalResult.warnings);
  }

  // Validate plan -> envelope
  for (const plan of documents.plans || []) {
    const id = plan.plan_id;
    const envelopeId = plan.source_envelope_id;

    if (envelopeId && !registry.hasEnvelope(envelopeId)) {
      errors.push({
        type: "missing_reference",
        source_schema: "procedure-plan",
        source_id: id,
        target_schema: "evidence-envelope",
        target_id: envelopeId,
        field: "source_envelope_id",
        message: `Plan "${id}" references non-existent envelope "${envelopeId}"`,
      });
    }
  }

  // Validate receipt -> plan
  for (const receipt of documents.receipts || []) {
    const id = receipt.receipt_id;
    const planId = receipt.plan_id;
    const envelopeId = receipt.source_envelope_id;

    if (planId && !registry.hasPlan(planId)) {
      errors.push({
        type: "missing_reference",
        source_schema: "receipt",
        source_id: id,
        target_schema: "procedure-plan",
        target_id: planId,
        field: "plan_id",
        message: `Receipt "${id}" references non-existent plan "${planId}"`,
      });
    }

    if (envelopeId && !registry.hasEnvelope(envelopeId)) {
      errors.push({
        type: "missing_reference",
        source_schema: "receipt",
        source_id: id,
        target_schema: "evidence-envelope",
        target_id: envelopeId,
        field: "source_envelope_id",
        message: `Receipt "${id}" references non-existent envelope "${envelopeId}"`,
      });
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

/**
 * Quick validation for a single document with a registry
 */
export function validateDocumentRefs(registry, schemaType, document) {
  const errors = [];
  const warnings = [];

  switch (schemaType) {
    case "envelope": {
      // Validate internal refs
      const result = validateEnvelopeInternalRefs(document);
      errors.push(...result.errors);
      warnings.push(...result.warnings);

      // Validate parent envelope ref
      const provenance = document.provenance;
      const parentId = provenance?.parent_envelope_id;
      if (parentId && !registry.hasEnvelope(parentId)) {
        warnings.push({
          type: "unverified_reference",
          message: `Parent envelope "${parentId}" not in registry`,
        });
      }
      break;
    }

    case "plan": {
      const id = document.plan_id;
      const envelopeId = document.source_envelope_id;
      if (envelopeId && !registry.hasEnvelope(envelopeId)) {
        errors.push({
          type: "missing_reference",
          source_schema: "procedure-plan",
          source_id: id,
          target_schema: "evidence-envelope",
          target_id: envelopeId,
          field: "source_envelope_id",
          message: `Plan references non-existent envelope "${envelopeId}"`,
        });
      }
      break;
    }

    case "receipt": {
      const id = document.receipt_id;
      const planId = document.plan_id;
      if (planId && !registry.hasPlan(planId)) {
        errors.push({
          type: "missing_reference",
          source_schema: "receipt",
          source_id: id,
          target_schema: "procedure-plan",
          target_id: planId,
          field: "plan_id",
          message: `Receipt references non-existent plan "${planId}"`,
        });
      }
      break;
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}
