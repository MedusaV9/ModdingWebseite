import crypto from 'node:crypto';
import { httpError, nowIso, readJsonObject, sendJson } from './util.js';

export const MIGRATION_FORMAT = 'sooodreamy-couple-v1';
export const MIGRATION_SCHEMA_VERSION = 1;
const IMPORT_LIMIT_BYTES = 16 * 1024 * 1024;

function cloneJSON(value) {
  return JSON.parse(JSON.stringify(value));
}

function canonicalJSONString(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJSONString).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJSONString(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function coupleForExport(couple) {
  const exported = cloneJSON(couple);
  if (exported.pendingMigrationPartner
      && !exported.members.some((member) => member.id === exported.pendingMigrationPartner.id)) {
    exported.members.push(exported.pendingMigrationPartner);
  }
  delete exported.pendingMigrationPartner;
  delete exported.migration;
  // Credential material never migrates (same rule as bearer sessions):
  // recovery-key digests and pending replace codes stay on the source server.
  delete exported.partnerReplace;
  for (const member of exported.members) delete member.recovery;
  return exported;
}

export function migrationDigest(couple) {
  const logical = coupleForExport(couple);
  delete logical.id;
  delete logical.code;
  return crypto.createHash('sha256')
    .update(canonicalJSONString(logical), 'utf8')
    .digest('hex');
}

export function createMigrationBundle(couple, {
  sourceVersion = 'unknown',
  exportedAt = nowIso(),
} = {}) {
  const snapshot = coupleForExport(couple);
  return {
    format: MIGRATION_FORMAT,
    schemaVersion: MIGRATION_SCHEMA_VERSION,
    exportedAt,
    sourceVersion,
    sourceCoupleId: couple.id,
    digest: migrationDigest(snapshot),
    couple: snapshot,
    media: {
      included: false,
      reason: 'binary-media-stays-in-the-server-data-directory',
    },
  };
}

function validateBundle(bundle, sourceMemberId) {
  if (!bundle || typeof bundle !== 'object' || Array.isArray(bundle)) {
    throw httpError(400, 'invalid_migration', 'Migration bundle must be an object');
  }
  if (bundle.format !== MIGRATION_FORMAT || bundle.schemaVersion !== MIGRATION_SCHEMA_VERSION) {
    throw httpError(409, 'unsupported_migration', 'Unsupported migration format or schema');
  }
  const source = bundle.couple;
  if (!source || typeof source !== 'object' || Array.isArray(source)) {
    throw httpError(400, 'invalid_migration', 'Migration bundle has no couple snapshot');
  }
  if (!Array.isArray(source.members) || source.members.length < 1 || source.members.length > 2) {
    throw httpError(400, 'invalid_migration', 'Migration snapshot must contain one or two members');
  }
  if (new Set(source.members.map((member) => member?.id)).size !== source.members.length
      || source.members.some((member) => typeof member?.id !== 'string')) {
    throw httpError(400, 'invalid_migration', 'Migration member identifiers are invalid');
  }
  if (!source.members.some((member) => member.id === sourceMemberId)) {
    throw httpError(400, 'unknown_source_member', 'Choose a member contained in this migration');
  }
  if (bundle.digest !== migrationDigest(source)) {
    throw httpError(400, 'migration_digest_mismatch', 'Migration content does not match its digest');
  }
  return cloneJSON(source);
}

export function isFreshMigrationDestination(couple) {
  if (!couple || couple.members?.length !== 1) return false;
  const ignored = new Set([
    'id', 'code', 'name', 'anniversary', 'palette', 'monogramStyle',
    'createdAt', 'members', 'counters',
  ]);
  return Object.entries(couple).every(([key, value]) => {
    if (ignored.has(key)) return true;
    // A zero games aggregate is birth state (newCouple initialises it);
    // any counted game is real history and blocks the import.
    if (key === 'gamesAggregate') return !value?.total;
    if (Array.isArray(value)) return value.length === 0;
    if (value && typeof value === 'object') return Object.keys(value).length === 0;
    return value == null;
  });
}

export function importMigrationBundle({
  store,
  destination,
  destinationMemberId,
  bundle,
  sourceMemberId,
}) {
  if (!isFreshMigrationDestination(destination)) {
    throw httpError(409, 'migration_destination_not_empty',
      'Import requires a newly created, single-member couple');
  }
  const imported = validateBundle(bundle, sourceMemberId);
  const sourceMember = imported.members.find((member) => member.id === sourceMemberId);
  const sourcePartner = imported.members.find((member) => member.id !== sourceMemberId) ?? null;
  const destinationId = destination.id;
  const destinationCode = destination.code;

  imported.id = destinationId;
  imported.code = destinationCode;
  imported.members = [sourceMember];
  if (sourcePartner) imported.pendingMigrationPartner = sourcePartner;
  imported.migration = {
    importedAt: nowIso(),
    sourceCoupleId: bundle.sourceCoupleId,
    sourceVersion: bundle.sourceVersion,
    requiresPartnerRepair: Boolean(sourcePartner),
  };

  for (const record of Object.values(store.data.tokens)) {
    if (record.coupleId === destinationId && record.memberId === destinationMemberId) {
      record.memberId = sourceMemberId;
    }
  }
  store.data.couples[destinationId] = imported;
  store.markDirty();
  return {
    coupleId: destinationId,
    memberId: sourceMemberId,
    code: destinationCode,
    requiresPartnerRepair: Boolean(sourcePartner),
    digest: migrationDigest(imported),
  };
}

export function registerMigrationRoutes(route) {
  route('GET', '/api/migration/export', { auth: true }, (c) => {
    sendJson(c.res, 200, {
      bundle: createMigrationBundle(c.auth.couple, { sourceVersion: c.config.version }),
      me: c.auth.memberId,
    });
  });

  route('POST', '/api/migration/import', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req, IMPORT_LIMIT_BYTES);
    if (body.confirm !== 'IMPORT') {
      throw httpError(400, 'migration_confirmation_required',
        'Set confirm to IMPORT after reviewing the destination warning');
    }
    const result = importMigrationBundle({
      store: c.store,
      destination: c.auth.couple,
      destinationMemberId: c.auth.memberId,
      bundle: body.bundle,
      sourceMemberId: body.sourceMemberId,
    });
    sendJson(c.res, 200, result);
  });
}
