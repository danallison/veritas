/**
 * Verification code strings — THE single source of truth.
 *
 * Each export is a JavaScript code string that is:
 *   1. Displayed in the code block (what the user reads)
 *   2. Executed by the Run button via AsyncFunction (what actually runs)
 *   3. Tested in vitest by executing the same string
 *
 * Step code references utility functions (hexToBytes, sha256, etc.) by name.
 * These are provided as AsyncFunction parameters at execution time — the user
 * can see their definitions in the Utilities section at the top of the page.
 */

import type { EntropyInputEntry, CommitRevealEntry, RosterEntry, CommitSigEntry } from './auditLogParsing'

// ---------------------------------------------------------------------------
// Input validation — defense-in-depth against code injection
// ---------------------------------------------------------------------------

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const HEX_RE = /^[0-9a-fA-F]*$/
const URL_RE = /^https?:\/\/[^\s'"\\]+$/

function assertUuid(value: string, label: string): void {
  if (!UUID_RE.test(value))
    throw new Error(`${label} is not a valid UUID: ${value.slice(0, 50)}`)
}

function assertHex(value: string, label: string): void {
  if (!HEX_RE.test(value))
    throw new Error(`${label} is not valid hex: ${value.slice(0, 50)}`)
}

function assertUrl(value: string, label: string): void {
  if (!URL_RE.test(value))
    throw new Error(`${label} is not a valid URL: ${value.slice(0, 50)}`)
}

function assertSafeInt(value: number, label: string): void {
  if (!Number.isSafeInteger(value))
    throw new Error(`${label} is not a safe integer: ${value}`)
}

// ---------------------------------------------------------------------------
// Shared utility functions
// ---------------------------------------------------------------------------

/** Displayed once at the top of the page. Defines helpers used by all steps. */
export const UTILITY_CODE = `\
function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2)
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  return bytes;
}

function bytesToHex(bytes) {
  return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
}

async function sha256(data) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', data));
}

async function hkdfSha256(ikm, info) {
  const salt = new TextEncoder().encode('veritas-salt');
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt, info },
    key, 256
  );
  return new Uint8Array(bits);
}

function bytesToBigInt(bytes) {
  let n = 0n;
  for (const b of bytes) n = n * 256n + BigInt(b);
  return n;
}`

/** Names of the utility functions provided to step code. */
export const UTILITY_NAMES = ['hexToBytes', 'bytesToHex', 'sha256', 'hkdfSha256', 'bytesToBigInt'] as const

/** Quick self-test code for the Utilities section Run button. */
export const UTILITY_SELF_TEST = `\
const testHex = 'a1b2c3d4';
const bytes = hexToBytes(testHex);
if (bytesToHex(bytes) !== testHex)
  return { status: 'fail', summary: 'hexToBytes/bytesToHex roundtrip failed' };

const hash = await sha256(new TextEncoder().encode('test'));
const hashHex = bytesToHex(hash);
if (hashHex.length !== 64)
  return { status: 'fail', summary: 'sha256 output wrong length: ' + hashHex.length };

const hkdf = await hkdfSha256(bytes, new TextEncoder().encode('test-info'));
if (bytesToHex(hkdf).length !== 64)
  return { status: 'fail', summary: 'hkdfSha256 output wrong length' };

const bi = bytesToBigInt(new Uint8Array([0x01, 0x00]));
if (bi !== 256n)
  return { status: 'fail', summary: 'bytesToBigInt(0x0100) should be 256, got ' + bi };

return {
  status: 'pass',
  summary: 'All utility functions working correctly',
  details: [
    { label: 'hexToBytes/bytesToHex', value: 'roundtrip OK' },
    { label: 'sha256', value: hashHex.slice(0, 16) + '...' },
    { label: 'hkdfSha256', value: bytesToHex(hkdf).slice(0, 16) + '...' },
    { label: 'bytesToBigInt', value: 'OK (256 = 0x0100)' },
  ]
};`

// ---------------------------------------------------------------------------
// Step 1: Fetch ceremony data
// ---------------------------------------------------------------------------

export const FETCH_DATA_PLACEHOLDER = `\
const response = await fetch('{BASE_URL}/api/ceremonies/{CEREMONY_ID}');
if (!response.ok)
  return { status: 'error', summary: 'Failed to fetch ceremony: HTTP ' + response.status };
const ceremony = await response.json();

const logResponse = await fetch('{BASE_URL}/api/ceremonies/{CEREMONY_ID}/log');
if (!logResponse.ok)
  return { status: 'error', summary: 'Failed to fetch audit log: HTTP ' + logResponse.status };
const auditLog = await logResponse.json();

const resolvedEvent = auditLog.entries.find(e => e.event_type === 'ceremony_resolved');
if (!resolvedEvent)
  return {
    status: 'fail',
    summary: 'No ceremony_resolved event found (ceremony may not be finalized)',
  };

const outcome = resolvedEvent.event_data.outcome;
const proof = outcome.outcomeProof;

return {
  status: 'pass',
  summary: 'Loaded "' + ceremony.question + '" (' + ceremony.phase + ')',
  details: [
    { label: 'Phase', value: ceremony.phase },
    { label: 'Type', value: ceremony.ceremony_type.tag },
    { label: 'Entropy method', value: ceremony.entropy_method },
    { label: 'Identity mode', value: ceremony.identity_mode },
    { label: 'Audit log entries', value: String(auditLog.entries.length) },
    { label: 'Entropy inputs', value: String(proof.proofEntropyInputs.length) },
  ],
  data: { ceremony, auditLog }
};`

export function fetchDataCode(ceremonyId: string, baseUrl: string): string {
  assertUuid(ceremonyId, 'ceremonyId')
  assertUrl(baseUrl, 'baseUrl')
  return `\
const response = await fetch('${baseUrl}/api/ceremonies/${ceremonyId}');
if (!response.ok)
  return { status: 'error', summary: 'Failed to fetch ceremony: HTTP ' + response.status };
const ceremony = await response.json();

const logResponse = await fetch('${baseUrl}/api/ceremonies/${ceremonyId}/log');
if (!logResponse.ok)
  return { status: 'error', summary: 'Failed to fetch audit log: HTTP ' + logResponse.status };
const auditLog = await logResponse.json();

const resolvedEvent = auditLog.entries.find(e => e.event_type === 'ceremony_resolved');
if (!resolvedEvent)
  return {
    status: 'fail',
    summary: 'No ceremony_resolved event found (ceremony may not be finalized)',
  };

const outcome = resolvedEvent.event_data.outcome;
const proof = outcome.outcomeProof;

return {
  status: 'pass',
  summary: 'Loaded "' + ceremony.question + '" (' + ceremony.phase + ')',
  details: [
    { label: 'Phase', value: ceremony.phase },
    { label: 'Type', value: ceremony.ceremony_type.tag },
    { label: 'Entropy method', value: ceremony.entropy_method },
    { label: 'Identity mode', value: ceremony.identity_mode },
    { label: 'Audit log entries', value: String(auditLog.entries.length) },
    { label: 'Entropy inputs', value: String(proof.proofEntropyInputs.length) },
  ],
  data: { ceremony, auditLog }
};`
}

// ---------------------------------------------------------------------------
// Step 2: Verify drand beacon
// ---------------------------------------------------------------------------

export const VERIFY_BEACON_PLACEHOLDER = `\
const network = '{CHAIN_HASH}';
const round = 0;
const expectedValue = '{BEACON_VALUE}';
const expectedSignature = '{BEACON_SIGNATURE}';

const url = 'https://api.drand.sh/' + network + '/public/' + round;
const res = await fetch(url);
const beacon = await res.json();

const valueMatch = beacon.randomness === expectedValue;
const sigMatch = beacon.signature === expectedSignature;

return {
  status: valueMatch && sigMatch ? 'pass' : 'fail',
  summary: valueMatch && sigMatch
    ? 'Beacon verified against drand'
    : 'MISMATCH',
  details: [
    { label: 'Randomness match', value: String(valueMatch), match: valueMatch },
    { label: 'Signature match', value: String(sigMatch), match: sigMatch },
  ]
};`

export function verifyBeaconCode(
  network: string,
  round: number,
  expectedValue: string,
  expectedSignature: string,
): string {
  assertHex(network, 'beacon network')
  assertSafeInt(round, 'beacon round')
  assertHex(expectedValue, 'beacon value')
  assertHex(expectedSignature, 'beacon signature')
  return `\
const network = '${network}';
const round = ${round};
const expectedValue = '${expectedValue}';
const expectedSignature = '${expectedSignature}';

const url = 'https://api.drand.sh/' + network + '/public/' + round;
const res = await fetch(url);
if (!res.ok)
  return { status: 'error', summary: 'Failed to fetch drand round: HTTP ' + res.status };
const beacon = await res.json();

const valueMatch = beacon.randomness === expectedValue;
const sigMatch = beacon.signature === expectedSignature;
const allMatch = valueMatch && sigMatch;

return {
  status: allMatch ? 'pass' : 'fail',
  summary: allMatch
    ? 'Beacon round ' + round + ' verified against drand'
    : 'MISMATCH — beacon data does not match drand',
  details: [
    { label: 'drand URL', value: url },
    { label: 'Randomness match', value: valueMatch ? 'Yes' : 'NO', match: valueMatch },
    { label: 'Signature match', value: sigMatch ? 'Yes' : 'NO', match: sigMatch },
    { label: 'Expected value', value: expectedValue.slice(0, 32) + '...' },
    { label: 'drand value', value: (beacon.randomness || '').slice(0, 32) + '...' },
  ]
};`
}

// ---------------------------------------------------------------------------
// Step 3: Verify commit-reveal integrity
// ---------------------------------------------------------------------------

export const VERIFY_COMMIT_REVEAL_PLACEHOLDER = `\
const ceremonyId = '{CEREMONY_ID}';
const participants = [
  { participantId: '{PARTICIPANT_ID}', sealHash: '{SEAL_HASH}', entropy: '{ENTROPY_HEX}' }
];
const encoder = new TextEncoder();
const results = [];

for (const p of participants) {
  const cidBytes = encoder.encode(ceremonyId);
  const pidBytes = encoder.encode(p.participantId);
  const entropyBytes = hexToBytes(p.entropy);

  const input = new Uint8Array(cidBytes.length + pidBytes.length + entropyBytes.length);
  input.set(cidBytes, 0);
  input.set(pidBytes, cidBytes.length);
  input.set(entropyBytes, cidBytes.length + pidBytes.length);

  const computed = bytesToHex(await sha256(input));
  const match = computed === p.sealHash;
  results.push({
    label: 'Participant ' + p.participantId.slice(0, 8) + '...',
    value: match ? 'Seal verified' : 'MISMATCH',
    match
  });
}

const allMatch = results.every(r => r.match);
return {
  status: allMatch ? 'pass' : 'fail',
  summary: allMatch
    ? 'All commit-reveal seals verified'
    : 'SEAL MISMATCH',
  details: results
};`

export function verifyCommitRevealCode(
  ceremonyId: string,
  participants: CommitRevealEntry[],
): string {
  assertUuid(ceremonyId, 'ceremonyId')
  for (const p of participants) {
    assertUuid(p.participantId, 'participantId')
    assertHex(p.sealHash, 'sealHash')
    assertHex(p.entropy, 'entropy')
  }
  return `\
const ceremonyId = '${ceremonyId}';
const participants = ${JSON.stringify(participants)};
const encoder = new TextEncoder();
const results = [];

for (const p of participants) {
  const cidBytes = encoder.encode(ceremonyId);
  const pidBytes = encoder.encode(p.participantId);
  const entropyBytes = hexToBytes(p.entropy);

  const input = new Uint8Array(cidBytes.length + pidBytes.length + entropyBytes.length);
  input.set(cidBytes, 0);
  input.set(pidBytes, cidBytes.length);
  input.set(entropyBytes, cidBytes.length + pidBytes.length);

  const computed = bytesToHex(await sha256(input));
  const match = computed === p.sealHash;
  results.push({
    label: 'Participant ' + p.participantId.slice(0, 8) + '...',
    value: match ? 'Seal verified' : 'MISMATCH — computed: ' + computed.slice(0, 16) + '...',
    match
  });
}

const allMatch = results.every(r => r.match);
return {
  status: allMatch ? 'pass' : 'fail',
  summary: allMatch
    ? 'All ' + participants.length + ' commit-reveal seals verified'
    : 'SEAL MISMATCH — some seals do not match revealed entropy',
  details: results
};`
}

// ---------------------------------------------------------------------------
// Step 4: Verify participant identity (self-certified)
// ---------------------------------------------------------------------------

export const VERIFY_IDENTITY_PLACEHOLDER = `\
const ceremonyId = '{CEREMONY_ID}';
const paramsHashHex = '{PARAMS_HASH}';
const roster = [
  { participantId: '{PARTICIPANT_ID}', publicKey: '{PUBLIC_KEY_HEX}' }
];
const ackSignatures = { '{PARTICIPANT_ID}': '{ROSTER_SIGNATURE_HEX}' };
const commitSignatures = [
  { participantId: '{PARTICIPANT_ID}', signature: '{COMMIT_SIGNATURE_HEX}', sealHash: null }
];
const encoder = new TextEncoder();
const results = [];

// Build roster payload
const sortedRoster = [...roster].sort((a, b) =>
  a.participantId < b.participantId ? -1 : 1);
const parts = [
  encoder.encode('veritas-roster-v2:'),
  encoder.encode(ceremonyId),
  hexToBytes(paramsHashHex)
];
for (const entry of sortedRoster) {
  parts.push(encoder.encode(entry.participantId));
  parts.push(hexToBytes(entry.publicKey));
}
const totalLen = parts.reduce((s, p) => s + p.length, 0);
const rosterPayload = new Uint8Array(totalLen);
let offset = 0;
for (const p of parts) { rosterPayload.set(p, offset); offset += p.length; }

// Verify each roster signature with Ed25519
for (const entry of roster) {
  const sig = ackSignatures[entry.participantId];
  if (!sig) {
    results.push({ label: 'Roster sig ' + entry.participantId.slice(0, 8), value: 'Missing', match: false });
    continue;
  }
  const key = await crypto.subtle.importKey(
    'raw', hexToBytes(entry.publicKey), { name: 'Ed25519' }, false, ['verify']);
  const valid = await crypto.subtle.verify('Ed25519', key, hexToBytes(sig), rosterPayload);
  results.push({
    label: 'Roster sig ' + entry.participantId.slice(0, 8),
    value: valid ? 'Valid' : 'INVALID', match: valid
  });
}

// Verify each commit signature
for (const commit of commitSignatures) {
  const entry = roster.find(r => r.participantId === commit.participantId);
  if (!entry) continue;
  const commitParts = [
    encoder.encode('veritas-commit-v2:'),
    encoder.encode(ceremonyId),
    encoder.encode(commit.participantId),
    hexToBytes(paramsHashHex),
  ];
  if (commit.sealHash) commitParts.push(hexToBytes(commit.sealHash));
  const cLen = commitParts.reduce((s, p) => s + p.length, 0);
  const commitPayload = new Uint8Array(cLen);
  let off = 0;
  for (const p of commitParts) { commitPayload.set(p, off); off += p.length; }

  const key = await crypto.subtle.importKey(
    'raw', hexToBytes(entry.publicKey), { name: 'Ed25519' }, false, ['verify']);
  const valid = await crypto.subtle.verify(
    'Ed25519', key, hexToBytes(commit.signature), commitPayload);
  results.push({
    label: 'Commit sig ' + commit.participantId.slice(0, 8),
    value: valid ? 'Valid' : 'INVALID', match: valid
  });
}

const allMatch = results.every(r => r.match);
return {
  status: allMatch ? 'pass' : 'fail',
  summary: allMatch
    ? 'All signatures verified'
    : 'SIGNATURE MISMATCH',
  details: results
};`

export function verifyIdentityCode(
  ceremonyId: string,
  paramsHash: string,
  roster: RosterEntry[],
  ackSignatures: Record<string, string>,
  commitSignatures: CommitSigEntry[],
): string {
  assertUuid(ceremonyId, 'ceremonyId')
  assertHex(paramsHash, 'paramsHash')
  for (const r of roster) {
    assertUuid(r.participantId, 'roster participantId')
    assertHex(r.publicKey, 'roster publicKey')
  }
  for (const [pid, sig] of Object.entries(ackSignatures)) {
    assertUuid(pid, 'ack participantId')
    assertHex(sig, 'ack signature')
  }
  for (const c of commitSignatures) {
    assertUuid(c.participantId, 'commit participantId')
    assertHex(c.signature, 'commit signature')
    if (c.sealHash) assertHex(c.sealHash, 'commit sealHash')
  }
  return `\
const ceremonyId = '${ceremonyId}';
const paramsHashHex = '${paramsHash}';
const roster = ${JSON.stringify(roster)};
const ackSignatures = ${JSON.stringify(ackSignatures)};
const commitSignatures = ${JSON.stringify(commitSignatures)};
const encoder = new TextEncoder();
const results = [];

// Build roster payload: "veritas-roster-v2:" || ceremonyId || paramsHash || sorted entries
const sortedRoster = [...roster].sort((a, b) =>
  a.participantId < b.participantId ? -1 : 1);
const parts = [
  encoder.encode('veritas-roster-v2:'),
  encoder.encode(ceremonyId),
  hexToBytes(paramsHashHex)
];
for (const entry of sortedRoster) {
  parts.push(encoder.encode(entry.participantId));
  parts.push(hexToBytes(entry.publicKey));
}
const totalLen = parts.reduce((s, p) => s + p.length, 0);
const rosterPayload = new Uint8Array(totalLen);
let offset = 0;
for (const p of parts) { rosterPayload.set(p, offset); offset += p.length; }

// Verify each roster signature with Ed25519
for (const entry of roster) {
  const sig = ackSignatures[entry.participantId];
  if (!sig) {
    results.push({
      label: 'Roster sig ' + entry.participantId.slice(0, 8) + '...',
      value: 'No signature found', match: false
    });
    continue;
  }
  try {
    const key = await crypto.subtle.importKey(
      'raw', hexToBytes(entry.publicKey), { name: 'Ed25519' }, false, ['verify']);
    const valid = await crypto.subtle.verify('Ed25519', key, hexToBytes(sig), rosterPayload);
    results.push({
      label: 'Roster sig ' + entry.participantId.slice(0, 8) + '...',
      value: valid ? 'Valid' : 'INVALID', match: valid
    });
  } catch (err) {
    results.push({
      label: 'Roster sig ' + entry.participantId.slice(0, 8) + '...',
      value: 'Error: ' + err.message, match: false
    });
  }
}

// Verify each commit signature
for (const commit of commitSignatures) {
  const entry = roster.find(r => r.participantId === commit.participantId);
  if (!entry) {
    results.push({
      label: 'Commit sig ' + commit.participantId.slice(0, 8) + '...',
      value: 'Not in roster', match: false
    });
    continue;
  }
  const commitParts = [
    encoder.encode('veritas-commit-v2:'),
    encoder.encode(ceremonyId),
    encoder.encode(commit.participantId),
    hexToBytes(paramsHashHex),
  ];
  if (commit.sealHash) commitParts.push(hexToBytes(commit.sealHash));
  const cLen = commitParts.reduce((s, p) => s + p.length, 0);
  const commitPayload = new Uint8Array(cLen);
  let off = 0;
  for (const p of commitParts) { commitPayload.set(p, off); off += p.length; }

  try {
    const key = await crypto.subtle.importKey(
      'raw', hexToBytes(entry.publicKey), { name: 'Ed25519' }, false, ['verify']);
    const valid = await crypto.subtle.verify(
      'Ed25519', key, hexToBytes(commit.signature), commitPayload);
    results.push({
      label: 'Commit sig ' + commit.participantId.slice(0, 8) + '...',
      value: valid ? 'Valid' : 'INVALID', match: valid
    });
  } catch (err) {
    results.push({
      label: 'Commit sig ' + commit.participantId.slice(0, 8) + '...',
      value: 'Error: ' + err.message, match: false
    });
  }
}

const allMatch = results.length > 0 && results.every(r => r.match);
return {
  status: allMatch ? 'pass' : 'fail',
  summary: allMatch
    ? 'All ' + results.length + ' signatures verified'
    : 'SIGNATURE VERIFICATION FAILED',
  details: results
};`
}

// ---------------------------------------------------------------------------
// Step 5: Verify ceremony parameters hash
// ---------------------------------------------------------------------------

export const VERIFY_PARAMS_HASH_PLACEHOLDER = `\
const ceremony = { /* loaded ceremony data */ };
const expectedHash = ceremony.params_hash;
const encoder = new TextEncoder();

function u32be(n) {
  return new Uint8Array([(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff]);
}

function lpString(s) {
  const bytes = encoder.encode(s);
  return concatBytes([u32be(bytes.length), bytes]);
}

function optionalBytes(value) {
  if (value === null) return new Uint8Array([0x00]);
  return concatBytes([new Uint8Array([0x01]), value]);
}

function concatBytes(parts) {
  const total = parts.reduce((s, p) => s + p.length, 0);
  const result = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { result.set(p, off); off += p.length; }
  return result;
}

// ... (ceremony type serialization, beacon spec, etc.)

const payload = concatBytes([
  encoder.encode('veritas-params-v1:'),
  lpString(ceremony.question),
  ceremonyTypeBytes(ceremony.ceremony_type),
  lpString(ceremony.entropy_method),
  u32be(ceremony.required_parties),
  lpString(ceremony.commitment_mode),
  lpString(ceremony.commit_deadline),
  optionalBytes(ceremony.reveal_deadline ? lpString(ceremony.reveal_deadline) : null),
  optionalBytes(ceremony.non_participation_policy ? lpString(ceremony.non_participation_policy) : null),
  optionalBytes(ceremony.beacon_spec ? beaconSpecBytes(ceremony.beacon_spec) : null),
  lpString(ceremony.identity_mode)
]);

const computed = bytesToHex(await sha256(payload));
const match = computed === expectedHash;

return {
  status: match ? 'pass' : 'fail',
  summary: match
    ? 'Parameters hash verified: ' + computed.slice(0, 16) + '...'
    : 'MISMATCH',
  details: [
    { label: 'Computed hash', value: computed, match },
    { label: 'Expected hash', value: expectedHash, match },
  ]
};`

export function verifyParamsHashCode(ceremony: Record<string, unknown>): string {
  assertHex(ceremony.params_hash as string, 'params_hash')
  assertUuid(ceremony.id as string, 'ceremony id')
  return `\
const ceremony = ${JSON.stringify(ceremony)};
const expectedHash = ceremony.params_hash;
const encoder = new TextEncoder();

function u32be(n) {
  return new Uint8Array([(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff]);
}

function lpString(s) {
  const bytes = encoder.encode(s);
  return concatBytes([u32be(bytes.length), bytes]);
}

function optionalBytes(value) {
  if (value === null) return new Uint8Array([0x00]);
  return concatBytes([new Uint8Array([0x01]), value]);
}

function concatBytes(parts) {
  const total = parts.reduce((s, p) => s + p.length, 0);
  const result = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { result.set(p, off); off += p.length; }
  return result;
}


function ceremonyTypeBytes(ct) {
  switch (ct.tag) {
    case 'CoinFlip':
      return concatBytes([lpString('CoinFlip'), lpString(ct.contents[0]), lpString(ct.contents[1])]);
    case 'UniformChoice':
      return concatBytes([lpString('UniformChoice'), u32be(ct.contents.length),
        ...ct.contents.map(lpString)]);
    case 'Shuffle':
      return concatBytes([lpString('Shuffle'), u32be(ct.contents.length),
        ...ct.contents.map(lpString)]);
    case 'IntRange':
      return concatBytes([lpString('IntRange'), u32be(ct.contents[0]), u32be(ct.contents[1])]);
    case 'WeightedChoice':
      return concatBytes([lpString('WeightedChoice'), u32be(ct.contents.length),
        ...ct.contents.flatMap(([label, weight]) =>
          [lpString(label), lpString(weight.numerator + ' % ' + weight.denominator)])]);
  }
}

function beaconSpecBytes(spec) {
  return concatBytes([
    lpString(spec.beaconNetwork),
    optionalBytes(spec.beaconRound !== null ? u32be(spec.beaconRound) : null),
    beaconFallbackBytes(spec.beaconFallback)
  ]);
}

function beaconFallbackBytes(fb) {
  switch (fb.tag) {
    case 'ExtendDeadline':
      return concatBytes([new Uint8Array([0x01]), lpString(String(fb.contents) + 's')]);
    case 'AlternateSource':
      return concatBytes([new Uint8Array([0x02]), beaconSpecBytes(fb.contents)]);
    case 'CancelCeremony':
      return new Uint8Array([0x03]);
  }
}

const payload = concatBytes([
  encoder.encode('veritas-params-v1:'),
  lpString(ceremony.question),
  ceremonyTypeBytes(ceremony.ceremony_type),
  lpString(ceremony.entropy_method),
  u32be(ceremony.required_parties),
  lpString(ceremony.commitment_mode),
  lpString(ceremony.commit_deadline),
  optionalBytes(ceremony.reveal_deadline !== null ? lpString(ceremony.reveal_deadline) : null),
  optionalBytes(ceremony.non_participation_policy !== null ? lpString(ceremony.non_participation_policy) : null),
  optionalBytes(ceremony.beacon_spec !== null ? beaconSpecBytes(ceremony.beacon_spec) : null),
  lpString(ceremony.identity_mode)
]);

const computed = bytesToHex(await sha256(payload));
const match = computed === expectedHash;

return {
  status: match ? 'pass' : 'fail',
  summary: match
    ? 'Parameters hash verified: ' + computed.slice(0, 16) + '...'
    : 'MISMATCH — computed: ' + computed.slice(0, 16) + '... expected: ' + expectedHash.slice(0, 16) + '...',
  details: [
    { label: 'Question', value: ceremony.question },
    { label: 'Type', value: ceremony.ceremony_type.tag },
    { label: 'Entropy method', value: ceremony.entropy_method },
    { label: 'Computed hash', value: computed, match },
    { label: 'Expected hash', value: expectedHash, match },
  ]
};`
}

// ---------------------------------------------------------------------------
// Step 6: Verify entropy combination
// ---------------------------------------------------------------------------

export const VERIFY_ENTROPY_PLACEHOLDER = `\
const priority = { ParticipantEntropy: 0, DefaultEntropy: 1, BeaconEntropy: 2, VRFEntropy: 3 };
const inputs = [
  { sourceType: 'ParticipantEntropy', sourceId: '{PARTICIPANT_ID}', valueHex: '{ENTROPY_HEX}' }
];
const sorted = [...inputs].sort((a, b) => {
  if (priority[a.sourceType] !== priority[b.sourceType])
    return priority[a.sourceType] - priority[b.sourceType];
  return a.sourceId < b.sourceId ? -1 : a.sourceId > b.sourceId ? 1 : 0;
});

const parts = sorted.map(i => hexToBytes(i.valueHex));
const total = parts.reduce((s, p) => s + p.length, 0);
const concat = new Uint8Array(total);
let offset = 0;
for (const p of parts) { concat.set(p, offset); offset += p.length; }

const computed = bytesToHex(await sha256(concat));
const expected = '{EXPECTED_COMBINED_ENTROPY}';
const match = computed === expected;

return {
  status: match ? 'pass' : 'fail',
  summary: match
    ? 'Combined entropy matches: ' + computed.slice(0, 16) + '...'
    : 'MISMATCH',
  details: [
    ...sorted.map(s => ({
      label: s.sourceType + ' ' + s.sourceId.slice(0, 8),
      value: s.valueHex.slice(0, 32) + '...'
    })),
    { label: 'Computed', value: computed, match },
    { label: 'Expected', value: expected, match },
  ]
};`

export function verifyEntropyCode(
  inputs: EntropyInputEntry[],
  expectedCombined: string,
): string {
  for (const inp of inputs) {
    assertHex(inp.valueHex, 'entropy valueHex')
  }
  assertHex(expectedCombined, 'expectedCombined')
  return `\
const priority = { ParticipantEntropy: 0, DefaultEntropy: 1, BeaconEntropy: 2, VRFEntropy: 3 };
const inputs = ${JSON.stringify(inputs)};
const sorted = [...inputs].sort((a, b) => {
  if (priority[a.sourceType] !== priority[b.sourceType])
    return priority[a.sourceType] - priority[b.sourceType];
  return a.sourceId < b.sourceId ? -1 : a.sourceId > b.sourceId ? 1 : 0;
});

const parts = sorted.map(i => hexToBytes(i.valueHex));
const total = parts.reduce((s, p) => s + p.length, 0);
const concat = new Uint8Array(total);
let offset = 0;
for (const p of parts) { concat.set(p, offset); offset += p.length; }

const computed = bytesToHex(await sha256(concat));
const expected = '${expectedCombined}';
const match = computed === expected;

return {
  status: match ? 'pass' : 'fail',
  summary: match
    ? 'Combined entropy matches: ' + computed.slice(0, 16) + '...'
    : 'MISMATCH — computed: ' + computed.slice(0, 16) + '... expected: ' + expected.slice(0, 16) + '...',
  details: [
    ...sorted.map(s => ({
      label: s.sourceType + ' ' + s.sourceId.slice(0, 8),
      value: s.valueHex.slice(0, 32) + '...'
    })),
    { label: 'Computed', value: computed, match },
    { label: 'Expected', value: expected, match },
  ]
};`
}

// ---------------------------------------------------------------------------
// Step 7: Verify outcome derivation
// ---------------------------------------------------------------------------

export const VERIFY_OUTCOME_PLACEHOLDER = `\
const TWO_TO_256 = 2n ** 256n;
const entropyHex = '{COMBINED_ENTROPY}';
const ceremonyType = { tag: 'CoinFlip', contents: ['Heads', 'Tails'] };
const expectedOutcome = '{EXPECTED_OUTCOME}';

const entropy = hexToBytes(entropyHex);
const uniformInfo = new TextEncoder().encode('veritas-uniform');
const okm = await hkdfSha256(entropy, uniformInfo);
const n = bytesToBigInt(okm);

let computedOutcome;
switch (ceremonyType.tag) {
  case 'CoinFlip': {
    const labels = ceremonyType.contents;
    computedOutcome = (n * 2n >= TWO_TO_256) ? labels[0] : labels[1];
    break;
  }
  case 'UniformChoice': {
    const choices = ceremonyType.contents;
    const idx = Number((n * BigInt(choices.length)) / TWO_TO_256);
    computedOutcome = choices[Math.min(idx, choices.length - 1)];
    break;
  }
  case 'IntRange': {
    const [lo, hi] = ceremonyType.contents;
    const range = BigInt(hi - lo + 1);
    const off = Number((n * range) / TWO_TO_256);
    computedOutcome = lo + Math.min(off, hi - lo);
    break;
  }
  case 'WeightedChoice': {
    // Weights are Haskell Rationals: {numerator, denominator}
    const choices = ceremonyType.contents.map(([label, w]) =>
      [label, BigInt(w.numerator), BigInt(w.denominator)]);
    // Use exact rational arithmetic with BigInt to avoid floating point
    // Common denominator: lcd = product of all denominators (simple, correct)
    const lcd = choices.reduce((acc, [,, d]) => acc * d, 1n);
    const scaled = choices.map(([label, num, den]) => [label, num * (lcd / den)]);
    const totalScaled = scaled.reduce((sum, [, w]) => sum + w, 0n);
    let remaining = n * totalScaled;
    computedOutcome = scaled[scaled.length - 1][0];
    for (let i = 0; i < scaled.length; i++) {
      if (i === scaled.length - 1) { computedOutcome = scaled[i][0]; break; }
      const threshold = scaled[i][1] * TWO_TO_256;
      if (remaining < threshold) { computedOutcome = scaled[i][0]; break; }
      remaining -= threshold;
    }
    break;
  }
  case 'Shuffle': {
    const items = [...ceremonyType.contents];
    for (let i = items.length - 1; i >= 1; i--) {
      const subInfo = new TextEncoder().encode('veritas-shuffle-' + i);
      const subOkm = await hkdfSha256(entropy, subInfo);
      const subN = bytesToBigInt(subOkm);
      const range = BigInt(i + 1);
      const j = Number((subN * range) / TWO_TO_256);
      const safeJ = Math.min(j, i);
      const tmp = items[i];
      items[i] = items[safeJ];
      items[safeJ] = tmp;
    }
    computedOutcome = items;
    break;
  }
}

const match = JSON.stringify(computedOutcome) === JSON.stringify(expectedOutcome);

return {
  status: match ? 'pass' : 'fail',
  summary: match
    ? 'Outcome verified: ' + JSON.stringify(computedOutcome)
    : 'MISMATCH',
  details: [
    { label: 'Ceremony type', value: ceremonyType.tag },
    { label: 'Computed', value: JSON.stringify(computedOutcome), match },
    { label: 'Expected', value: JSON.stringify(expectedOutcome), match },
  ]
};`

export function verifyOutcomeCode(
  ceremonyType: { tag: string; contents?: unknown },
  combinedEntropy: string,
  expectedOutcome: unknown,
): string {
  assertHex(combinedEntropy, 'combinedEntropy')
  return `\
const TWO_TO_256 = 2n ** 256n;
const entropyHex = '${combinedEntropy}';
const ceremonyType = ${JSON.stringify(ceremonyType)};
const expectedOutcome = ${JSON.stringify(expectedOutcome)};

const entropy = hexToBytes(entropyHex);
const uniformInfo = new TextEncoder().encode('veritas-uniform');
const okm = await hkdfSha256(entropy, uniformInfo);
const n = bytesToBigInt(okm);

let computedOutcome;
switch (ceremonyType.tag) {
  case 'CoinFlip': {
    const labels = ceremonyType.contents;
    computedOutcome = (n * 2n >= TWO_TO_256) ? labels[0] : labels[1];
    break;
  }
  case 'UniformChoice': {
    const choices = ceremonyType.contents;
    const idx = Number((n * BigInt(choices.length)) / TWO_TO_256);
    computedOutcome = choices[Math.min(idx, choices.length - 1)];
    break;
  }
  case 'IntRange': {
    const [lo, hi] = ceremonyType.contents;
    const range = BigInt(hi - lo + 1);
    const off = Number((n * range) / TWO_TO_256);
    computedOutcome = lo + Math.min(off, hi - lo);
    break;
  }
  case 'WeightedChoice': {
    // Weights are Haskell Rationals: {numerator, denominator}
    const choices = ceremonyType.contents.map(([label, w]) =>
      [label, BigInt(w.numerator), BigInt(w.denominator)]);
    // Use exact rational arithmetic with BigInt to avoid floating point
    // Common denominator: lcd = product of all denominators (simple, correct)
    const lcd = choices.reduce((acc, [,, d]) => acc * d, 1n);
    const scaled = choices.map(([label, num, den]) => [label, num * (lcd / den)]);
    const totalScaled = scaled.reduce((sum, [, w]) => sum + w, 0n);
    let remaining = n * totalScaled;
    computedOutcome = scaled[scaled.length - 1][0];
    for (let i = 0; i < scaled.length; i++) {
      if (i === scaled.length - 1) { computedOutcome = scaled[i][0]; break; }
      const threshold = scaled[i][1] * TWO_TO_256;
      if (remaining < threshold) { computedOutcome = scaled[i][0]; break; }
      remaining -= threshold;
    }
    break;
  }
  case 'Shuffle': {
    const items = [...ceremonyType.contents];
    for (let i = items.length - 1; i >= 1; i--) {
      const subInfo = new TextEncoder().encode('veritas-shuffle-' + i);
      const subOkm = await hkdfSha256(entropy, subInfo);
      const subN = bytesToBigInt(subOkm);
      const range = BigInt(i + 1);
      const j = Number((subN * range) / TWO_TO_256);
      const safeJ = Math.min(j, i);
      const tmp = items[i];
      items[i] = items[safeJ];
      items[safeJ] = tmp;
    }
    computedOutcome = items;
    break;
  }
  default:
    return { status: 'error', summary: 'Unknown ceremony type: ' + ceremonyType.tag };
}

const match = JSON.stringify(computedOutcome) === JSON.stringify(expectedOutcome);

return {
  status: match ? 'pass' : 'fail',
  summary: match
    ? 'Outcome verified: ' + JSON.stringify(computedOutcome)
    : 'MISMATCH — computed: ' + JSON.stringify(computedOutcome) + ', expected: ' + JSON.stringify(expectedOutcome),
  details: [
    { label: 'Ceremony type', value: ceremonyType.tag },
    { label: 'Combined entropy', value: entropyHex.slice(0, 32) + '...' },
    { label: 'Computed outcome', value: JSON.stringify(computedOutcome), match },
    { label: 'Expected outcome', value: JSON.stringify(expectedOutcome), match },
  ]
};`
}
