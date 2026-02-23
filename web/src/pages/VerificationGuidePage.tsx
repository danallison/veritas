import { useEffect, useState } from 'react'
import { api } from '../api/client'
import type { BeaconVerificationGuideResponse } from '../api/types'

function CodeBlock({ children, copyText }: { children: string; copyText?: string }) {
  const [copied, setCopied] = useState(false)
  const text = copyText ?? children

  const handleCopy = () => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <div className="relative group">
      <pre className="bg-gray-50 border border-gray-200 rounded p-4 text-xs overflow-x-auto leading-relaxed">
        {children}
      </pre>
      <button
        onClick={handleCopy}
        className="absolute top-2 right-2 px-1.5 py-0.5 text-xs text-gray-400 hover:text-gray-700 border border-gray-300 rounded hover:bg-gray-100 opacity-0 group-hover:opacity-100 transition-opacity"
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}

function Section({
  title,
  children,
}: {
  title: string
  children: React.ReactNode
}) {
  return (
    <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
      <h2 className="text-lg font-semibold">{title}</h2>
      {children}
    </section>
  )
}

export default function VerificationGuidePage() {
  const [guide, setGuide] = useState<BeaconVerificationGuideResponse | null>(null)
  const [guideError, setGuideError] = useState<string | null>(null)

  useEffect(() => {
    api.getBeaconVerificationGuide()
      .then(setGuide)
      .catch((e) => setGuideError(e.message))
  }, [])

  const baseUrl = window.location.origin

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Verification Guide</h1>

      {/* Introduction */}
      <Section title="Why verify?">
        <p className="text-sm text-gray-700">
          Veritas produces cryptographically verifiable random outcomes. Every step from
          entropy collection to outcome derivation is deterministic and reproducible. You
          don't need to trust Veritas — you can independently verify that the reported
          outcome is the only possible result given the entropy inputs.
        </p>
        <p className="text-sm text-gray-700">
          For self-certified ceremonies, the audit log also contains cryptographic proof
          tying each participant to a public key. Multiple signatures from that key are
          recorded at different stages of the ceremony, making it effectively impossible
          for a participant to deny involvement. The ceremony record alone is sufficient
          to prove participation — no external identity provider required.
        </p>
        <p className="text-sm text-gray-700">
          This guide walks through the full verification pipeline. For any finalized
          ceremony, you can reproduce every step using standard command-line tools.
        </p>
        <div className="bg-gray-50 rounded p-3">
          <p className="text-xs font-medium text-gray-600 mb-2">Verification pipeline:</p>
          <ol className="list-decimal list-inside text-sm text-gray-700 space-y-1">
            <li>Fetch the ceremony audit log</li>
            <li>Verify the drand beacon (if applicable)</li>
            <li>Verify commit-reveal integrity (if applicable)</li>
            <li>Verify participant identity (self-certified ceremonies)</li>
            <li>Verify entropy combination</li>
            <li>Verify outcome derivation</li>
          </ol>
        </div>
      </Section>

      {/* Step 1: Fetch data */}
      <Section title="Step 1: Fetch the ceremony data">
        <p className="text-sm text-gray-700">
          Every ceremony has an audit log containing all events from creation through
          finalization. Fetch it with:
        </p>
        <CodeBlock>{`curl -s ${baseUrl}/api/ceremonies/{CEREMONY_ID}/log | jq`}</CodeBlock>
        <p className="text-sm text-gray-700">
          The key event is <code className="text-xs bg-gray-100 px-1 rounded">ceremony_resolved</code>,
          which contains the full outcome proof:
        </p>
        <CodeBlock>{`// ceremony_resolved event_data structure:
{
  "tag": "CeremonyResolved",
  "outcome": {
    "outcomeValue": { "tag": "CoinFlipResult", "contents": "Heads" },
    "combinedEntropy": "hex...",
    "outcomeProof": {
      "proofEntropyInputs": [
        {
          "ecCeremony": "ceremony-uuid",
          "ecSource": { "tag": "ParticipantEntropy", "participant": "uuid" },
          "ecValue": "hex..."
        }
      ],
      "proofDerivation": "..."
    }
  }
}`}</CodeBlock>
        <p className="text-sm text-gray-700">
          Other useful events: <code className="text-xs bg-gray-100 px-1 rounded">beacon_anchored</code> (beacon
          data), <code className="text-xs bg-gray-100 px-1 rounded">participant_committed</code> (commitment
          seals), <code className="text-xs bg-gray-100 px-1 rounded">entropy_revealed</code> (revealed values).
        </p>
      </Section>

      {/* Step 2: Verify beacon */}
      <Section title="Step 2: Verify the drand beacon">
        <p className="text-sm text-gray-700">
          Applies to ceremonies using <strong>ExternalBeacon</strong> or <strong>Combined</strong> entropy
          methods. The <code className="text-xs bg-gray-100 px-1 rounded">beacon_anchored</code> event
          contains the drand round data used for randomness.
        </p>

        <h3 className="text-sm font-medium text-gray-700">2a. Fetch the same round from drand</h3>
        <p className="text-sm text-gray-700">
          From the <code className="text-xs bg-gray-100 px-1 rounded">beacon_anchored</code> event,
          extract the <code className="text-xs bg-gray-100 px-1 rounded">baNetwork</code> (chain hash)
          and <code className="text-xs bg-gray-100 px-1 rounded">baRound</code>, then fetch directly from drand:
        </p>
        <CodeBlock>{`curl -s https://api.drand.sh/{CHAIN_HASH}/public/{ROUND} | jq`}</CodeBlock>
        <p className="text-sm text-gray-700">
          Compare the response's <code className="text-xs bg-gray-100 px-1 rounded">randomness</code> field
          with <code className="text-xs bg-gray-100 px-1 rounded">baValue</code> and
          the <code className="text-xs bg-gray-100 px-1 rounded">signature</code> field
          with <code className="text-xs bg-gray-100 px-1 rounded">baSignature</code> from
          the audit log. They must match exactly.
        </p>
        <p className="text-sm text-gray-700">
          <strong>What this proves:</strong> the beacon data is real drand output, not fabricated by Veritas.
        </p>

        <h3 className="text-sm font-medium text-gray-700">2b. Full BLS signature verification</h3>
        <p className="text-sm text-gray-700">
          For cryptographic verification of the BLS signature itself, use drand's official
          tools which verify automatically when fetching:
        </p>
        <ul className="list-disc list-inside text-sm text-gray-700 space-y-1">
          <li><strong>Go:</strong> github.com/drand/go-clients</li>
          <li><strong>Rust:</strong> github.com/drand/drand-verify</li>
        </ul>

        {guide && (
          <div className="bg-gray-50 rounded p-3 space-y-1.5">
            <p className="text-xs font-medium text-gray-600">Server's drand configuration:</p>
            <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
              <span className="text-gray-500">Scheme:</span>
              <code className="font-mono text-gray-800">{guide.scheme}</code>
              <span className="text-gray-500">Chain hash:</span>
              <code className="font-mono text-gray-800 break-all">{guide.chain_hash}</code>
              <span className="text-gray-500">DST:</span>
              <code className="font-mono text-gray-800 break-all">{guide.dst}</code>
              <span className="text-gray-500">Public key:</span>
              <code className="font-mono text-gray-800 break-all text-xs">
                {guide.public_key ?? 'Not available'}
              </code>
            </div>
          </div>
        )}
        {guideError && (
          <p className="text-xs text-red-600">Could not load drand configuration: {guideError}</p>
        )}
      </Section>

      {/* Step 3: Verify commit-reveal */}
      <Section title="Step 3: Verify commit-reveal integrity">
        <p className="text-sm text-gray-700">
          Applies to ceremonies using <strong>ParticipantReveal</strong> or <strong>Combined</strong> entropy
          methods. Each participant commits a seal <em>before</em> any entropy is revealed. The seal
          binds them to their entropy value.
        </p>
        <p className="text-sm text-gray-700">
          For each participant, verify that the revealed entropy matches their commitment seal:
        </p>
        <CodeBlock>{`seal = SHA-256(ceremony_id_ascii || participant_id_ascii || entropy_bytes)`}</CodeBlock>
        <p className="text-sm text-gray-700">
          The commitment seal is stored in
          the <code className="text-xs bg-gray-100 px-1 rounded">participant_committed</code> event's
          <code className="text-xs bg-gray-100 px-1 rounded">entropySealHash</code> field. The revealed
          entropy is in
          the <code className="text-xs bg-gray-100 px-1 rounded">entropy_revealed</code> event.
        </p>

        <h3 className="text-sm font-medium text-gray-700">Compute with standard tools</h3>
        <CodeBlock>{`# For each participant, verify their seal:
# ceremony_id and participant_id are ASCII UUID strings
# entropy_hex is the revealed entropy value (hex-encoded)

printf '%s%s' "CEREMONY_ID" "PARTICIPANT_ID" \\
  | cat - <(echo -n "ENTROPY_HEX" | xxd -r -p) \\
  | sha256sum

# The output should match the entropySealHash from the
# participant_committed event.`}</CodeBlock>
        <p className="text-sm text-gray-700">
          <strong>What this proves:</strong> participants couldn't change their entropy after committing.
          The cryptographic seal binds them to their choice before anyone else's entropy is visible.
        </p>
      </Section>

      {/* Step 4: Verify participant identity */}
      <Section title="Step 4: Verify participant identity (self-certified ceremonies)">
        <p className="text-sm text-gray-700">
          Applies to ceremonies with <code className="text-xs bg-gray-100 px-1 rounded">identity_mode: "SelfCertified"</code>.
          This is the step that establishes <strong>who</strong> participated — not just
          that the outcome is correct, but that specific cryptographic identities
          knowingly agreed to be bound by it.
        </p>

        <div className="bg-indigo-50 border border-indigo-200 rounded p-3">
          <p className="text-sm text-indigo-900 font-medium mb-1">Why this matters</p>
          <p className="text-sm text-indigo-800">
            In an anonymous ceremony, participants are identified by ephemeral UUIDs with
            no authentication. Anyone can claim "that wasn't me" after an unfavorable
            outcome. Self-certified identity solves this: each participant is identified
            by an Ed25519 public key, and the audit log contains multiple signatures
            from that key, making denial implausible.
          </p>
          <p className="text-sm text-indigo-800 mt-2">
            The audit log records three layers of cryptographic evidence per participant:
          </p>
          <ol className="list-decimal list-inside text-sm text-indigo-800 mt-2 space-y-1">
            <li><strong>Public key registration</strong> — the key is recorded before any
              commitments, in
              the <code className="text-xs bg-indigo-100 px-0.5 rounded">participant_joined</code> event</li>
            <li><strong>Roster signature</strong> — a signature from that key over the ceremony
              roster, proving the key holder actively participated at this stage, in
              the <code className="text-xs bg-indigo-100 px-0.5 rounded">roster_acknowledged</code> event</li>
            <li><strong>Signed commitment</strong> — a signature from that key over the commitment
              payload, binding the key holder to accepting the outcome</li>
          </ol>
          <p className="text-sm text-indigo-800 mt-2">
            To deny involvement, a participant would have to claim their private key was
            compromised — a much stronger claim than "that wasn't me," because the record
            contains multiple distinct signatures from the same key at different stages
            of the ceremony.
          </p>
        </div>

        <h3 className="text-sm font-medium text-gray-700">4a. Extract the roster</h3>
        <p className="text-sm text-gray-700">
          Find the <code className="text-xs bg-gray-100 px-1 rounded">roster_finalized</code> event
          in the audit log. Its <code className="text-xs bg-gray-100 px-1 rounded">event_data</code> contains
          the locked roster: an ordered list of (participant_id, public_key) pairs.
        </p>
        <CodeBlock>{`# The roster_finalized event contains:
{
  "tag": "RosterFinalized",
  "contents": [
    ["participant-uuid-1", "hex-encoded-public-key-1"],
    ["participant-uuid-2", "hex-encoded-public-key-2"]
  ]
}`}</CodeBlock>

        <h3 className="text-sm font-medium text-gray-700">4b. Verify roster signatures</h3>
        <p className="text-sm text-gray-700">
          Each participant signed the canonical roster payload. The payload is a
          version prefix, the ceremony ID, the ceremony parameters hash, and all
          roster entries (sorted by participant ID), with UUIDs as ASCII bytes and
          public keys as raw bytes:
        </p>
        <CodeBlock>{`roster_payload = "veritas-roster-v2:"
  || ceremony_id_ascii
  || params_hash (32 bytes)
  || participant_id_1_ascii || public_key_1_bytes
  || participant_id_2_ascii || public_key_2_bytes
  || ...

# Participants are sorted by participant_id (UUID lexicographic).
# UUIDs are 36-character ASCII strings (with hyphens).
# Public keys are 32 raw bytes (hex-decode from the roster).
# params_hash is the SHA-256 hash of the canonical ceremony parameters
# (available as params_hash in the ceremony response).`}</CodeBlock>
        <p className="text-sm text-gray-700">
          For each participant, find their <code className="text-xs bg-gray-100 px-1 rounded">roster_acknowledged</code> event
          and extract the signature. Then verify the Ed25519 signature over the roster
          payload using the participant's public key from the roster.
        </p>
        <CodeBlock>{`# Using Python (pip install pynacl):
from nacl.signing import VerifyKey

# Build roster_payload by concatenating the fields described above
verify_key = VerifyKey(bytes.fromhex(participant_public_key))
verify_key.verify(roster_payload, bytes.fromhex(roster_signature))

# Using Node.js (@noble/ed25519):
import * as ed from '@noble/ed25519'
// Build rosterPayload by concatenating the fields described above
const valid = await ed.verifyAsync(
  hexToBytes(signature),
  rosterPayload,
  hexToBytes(publicKey)
)`}</CodeBlock>
        <p className="text-sm text-gray-700">
          <strong>What this proves:</strong> the holder of the registered public key
          produced a signature over this specific ceremony's roster. This is a second
          signed artifact from the same key (after registration), strengthening the
          link between the key and the act of participation. The participant cannot
          deny involvement without claiming their private key was compromised.
        </p>

        <h3 className="text-sm font-medium text-gray-700">4c. Verify commit signatures</h3>
        <p className="text-sm text-gray-700">
          Each participant also signed their commitment. The commit payload is:
        </p>
        <CodeBlock>{`commit_payload = "veritas-commit-v2:"
  || ceremony_id_ascii
  || participant_id_ascii
  || params_hash (32 bytes)
  || seal_hash_bytes?    # present if entropy method uses seals

# params_hash is the SHA-256 hash of the canonical ceremony parameters
# (available as params_hash in the ceremony response).`}</CodeBlock>
        <p className="text-sm text-gray-700">
          The server verified this signature at commit time, but you can independently
          re-verify it: reconstruct the commit payload, then check the Ed25519 signature
          (from the <code className="text-xs bg-gray-100 px-1 rounded">participant_committed</code> event)
          against the participant's public key from the roster.
        </p>
        <p className="text-sm text-gray-700">
          <strong>What this proves:</strong> the holder of the registered public key
          explicitly committed to this ceremony. The ceremony record now contains three
          distinct signatures from the same key — registration, roster acknowledgment,
          and commitment — making it self-contained proof that this cryptographic identity
          participated and agreed to be bound by the outcome.
        </p>
      </Section>

      {/* Step 4d: Verify params_hash */}
      <Section title="Step 4d: Verify the ceremony parameters hash">
        <p className="text-sm text-gray-700">
          The roster and commit payloads (sections 4b and 4c above) both include
          a <code className="text-xs bg-gray-100 px-1 rounded">params_hash</code> — a
          SHA-256 hash of all ceremony parameters. This cryptographically binds
          each participant's signatures to the specific rules of the ceremony
          (question, outcome type, entropy method, deadlines, etc.).
        </p>
        <p className="text-sm text-gray-700">
          The <code className="text-xs bg-gray-100 px-1 rounded">params_hash</code> is
          available in the ceremony API response
          at <code className="text-xs bg-gray-100 px-1 rounded">GET /api/ceremonies/{'{'}id{'}'}</code>.
          To verify it independently, reconstruct the canonical byte serialization
          and hash it yourself.
        </p>

        <h3 className="text-sm font-medium text-gray-700">Encoding primitives</h3>
        <p className="text-sm text-gray-700">
          The serialization uses three building blocks:
        </p>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="text-left py-1.5 pr-3">Name</th>
                <th className="text-left py-1.5">Encoding</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-gray-100">
                <td className="py-1.5 pr-3 font-mono">len_string(s)</td>
                <td className="py-1.5">4-byte big-endian byte length of <em>s</em>, then the UTF-8 bytes of <em>s</em></td>
              </tr>
              <tr className="border-b border-gray-100">
                <td className="py-1.5 pr-3 font-mono">u32(n)</td>
                <td className="py-1.5">4-byte big-endian unsigned integer</td>
              </tr>
              <tr>
                <td className="py-1.5 pr-3 font-mono">optional(x)</td>
                <td className="py-1.5">
                  If absent: single byte <code className="bg-gray-100 px-0.5 rounded">0x00</code>.
                  If present: byte <code className="bg-gray-100 px-0.5 rounded">0x01</code> followed by the encoded value.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <h3 className="text-sm font-medium text-gray-700">Overall structure</h3>
        <CodeBlock>{`params_hash = SHA-256(
  "veritas-params-v1:"                   # version prefix (raw ASCII, not length-prefixed)
  || len_string(question)
  || ceremony_type_bytes                  # see below
  || len_string(entropy_method)           # e.g. "OfficiantVRF", "Combined"
  || u32(required_parties)
  || len_string(commitment_mode)          # e.g. "Immediate"
  || len_string(commit_deadline)          # ISO 8601, e.g. "2026-06-01T12:00:00Z"
  || optional(len_string(reveal_deadline))
  || optional(len_string(non_participation_policy))
  || optional(beacon_spec_bytes)          # see below
  || len_string(identity_mode)            # "Anonymous" or "SelfCertified"
)`}</CodeBlock>
        <p className="text-sm text-gray-700">
          All field values come directly from the ceremony API response. String
          values like <code className="text-xs bg-gray-100 px-1 rounded">entropy_method</code> and{' '}
          <code className="text-xs bg-gray-100 px-1 rounded">identity_mode</code> are
          encoded exactly as they appear in the JSON.
        </p>

        <h3 className="text-sm font-medium text-gray-700">Ceremony type encoding</h3>
        <CodeBlock>{`CoinFlip:
  len_string("CoinFlip") || len_string(sideA) || len_string(sideB)

UniformChoice:
  len_string("UniformChoice") || u32(count) || len_string(opt1) || len_string(opt2) || ...

Shuffle:
  len_string("Shuffle") || u32(count) || len_string(item1) || len_string(item2) || ...

IntRange:
  len_string("IntRange") || u32(lo) || u32(hi)

WeightedChoice:
  len_string("WeightedChoice") || u32(count)
    || len_string(label1) || len_string(weight1_as_fraction)
    || len_string(label2) || len_string(weight2_as_fraction)
    || ...
  # Weights are encoded as fraction strings: "3 % 2" for 1.5, "1 % 1" for 1`}</CodeBlock>

        <h3 className="text-sm font-medium text-gray-700">Beacon spec encoding (when present)</h3>
        <CodeBlock>{`beacon_spec_bytes =
  len_string(network)
  || optional(u32(round))
  || fallback_bytes

fallback_bytes:
  ExtendDeadline:   0x01 || len_string(seconds + "s")     # e.g. "3600s"
  AlternateSource:  0x02 || beacon_spec_bytes(alt_spec)
  CancelCeremony:   0x03`}</CodeBlock>

        <h3 className="text-sm font-medium text-gray-700">Example (Python)</h3>
        <CodeBlock>{`import struct, hashlib, json, urllib.request

# Fetch ceremony
ceremony = json.loads(urllib.request.urlopen(
    "BASE_URL/api/ceremonies/CEREMONY_ID"
).read())

def len_string(s):
    b = s.encode("utf-8")
    return struct.pack(">I", len(b)) + b

def u32(n):
    return struct.pack(">I", n)

def optional(value):
    if value is None:
        return b"\\x00"
    return b"\\x01" + value

# Build the canonical bytes (for a CoinFlip ceremony with no beacon)
ct = ceremony["ceremony_type"]
payload = b"veritas-params-v1:"
payload += len_string(ceremony["question"])
payload += len_string(ct["tag"]) + len_string(ct["contents"][0]) + len_string(ct["contents"][1])
payload += len_string(ceremony["entropy_method"])
payload += u32(ceremony["required_parties"])
payload += len_string(ceremony["commitment_mode"])
payload += len_string(ceremony["commit_deadline"])
payload += optional(len_string(ceremony["reveal_deadline"]) if ceremony["reveal_deadline"] else None)
payload += optional(len_string(ceremony["non_participation_policy"]) if ceremony["non_participation_policy"] else None)
payload += optional(None)  # no beacon_spec
payload += len_string(ceremony["identity_mode"])

computed = hashlib.sha256(payload).hexdigest()
assert computed == ceremony["params_hash"]`}</CodeBlock>

        <p className="text-sm text-gray-700">
          <strong>What this proves:</strong> by signing a payload that includes{' '}
          <code className="text-xs bg-gray-100 px-1 rounded">params_hash</code>,
          a participant cryptographically commits to the exact ceremony configuration.
          They cannot later claim "I didn't know it was a shuffle of 100 items — I
          thought it was a coin flip." The hash is deterministic: given the same
          ceremony parameters, any implementation must produce the same hash.
        </p>
      </Section>

      {/* Step 5: Verify entropy combination */}
      <Section title="Step 5: Verify entropy combination">
        <p className="text-sm text-gray-700">
          All entropy contributions are combined deterministically. The order is fixed by a
          canonical sorting key — the same inputs always produce the same combined entropy.
        </p>

        <h3 className="text-sm font-medium text-gray-700">Canonical sort order</h3>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="text-left py-1.5 pr-3">Source Type</th>
                <th className="text-left py-1.5 pr-3">Priority</th>
                <th className="text-left py-1.5">Sort Key</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-gray-100">
                <td className="py-1.5 pr-3">ParticipantEntropy</td>
                <td className="py-1.5 pr-3 font-mono">0</td>
                <td className="py-1.5 font-mono">participant UUID (ASCII bytes)</td>
              </tr>
              <tr className="border-b border-gray-100">
                <td className="py-1.5 pr-3">DefaultEntropy</td>
                <td className="py-1.5 pr-3 font-mono">1</td>
                <td className="py-1.5 font-mono">participant UUID (ASCII bytes)</td>
              </tr>
              <tr className="border-b border-gray-100">
                <td className="py-1.5 pr-3">BeaconEntropy</td>
                <td className="py-1.5 pr-3 font-mono">2</td>
                <td className="py-1.5 font-mono">"beacon"</td>
              </tr>
              <tr>
                <td className="py-1.5 pr-3">VRFEntropy</td>
                <td className="py-1.5 pr-3 font-mono">3</td>
                <td className="py-1.5 font-mono">"vrf"</td>
              </tr>
            </tbody>
          </table>
        </div>

        <h3 className="text-sm font-medium text-gray-700">Combination algorithm</h3>
        <CodeBlock>{`# 1. Sort entropy contributions by (priority, sort_key)
# 2. Concatenate raw entropy values in sorted order (no delimiters)
# 3. SHA-256 hash the concatenation

# The result must equal the combinedEntropy field in the
# ceremony_resolved event.

# Example with two inputs (hex entropy values):
echo -n "ENTROPY_1_HEX ENTROPY_2_HEX" \\
  | tr -d ' ' | xxd -r -p | sha256sum`}</CodeBlock>
        <p className="text-sm text-gray-700">
          The <code className="text-xs bg-gray-100 px-1 rounded">proofEntropyInputs</code> array
          in the <code className="text-xs bg-gray-100 px-1 rounded">ceremony_resolved</code> event
          may not be in canonical order. You must sort the entries by <code className="text-xs bg-gray-100 px-1 rounded">(priority, sort_key)</code> using
          the table above before concatenating. Then concatenate
          the <code className="text-xs bg-gray-100 px-1 rounded">ecValue</code> fields
          (as raw bytes, not hex strings) and SHA-256 hash the result.
        </p>
      </Section>

      {/* Step 6: Verify outcome derivation */}
      <Section title="Step 6: Verify outcome derivation">
        <p className="text-sm text-gray-700">
          The combined entropy is passed through HKDF-SHA256 to derive a uniform random value,
          which is then used to determine the ceremony outcome based on the ceremony type.
        </p>

        <h3 className="text-sm font-medium text-gray-700">HKDF derivation</h3>
        <CodeBlock>{`# HKDF-SHA256 parameters:
salt = "veritas-salt"        # fixed ASCII string
hash = SHA-256

# Step 1: Extract
prk = HMAC-SHA256(key=salt, data=combined_entropy)

# Step 2: Expand
okm = HKDF-Expand(prk, info="veritas-uniform", length=32)

# Step 3: Convert to a value in [0, 1)
n = big_endian_integer(okm)   # 256-bit unsigned integer
r = n / 2^256                 # value in [0, 1)`}</CodeBlock>

        <h3 className="text-sm font-medium text-gray-700">Type-specific derivation</h3>

        <div className="space-y-3">
          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">CoinFlip</p>
            <code className="text-xs text-gray-800">
              if r &gt;= 0.5: result = first label, else: result = second label
            </code>
          </div>

          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">UniformChoice</p>
            <code className="text-xs text-gray-800">
              index = floor(r * num_options); result = options[index]
            </code>
          </div>

          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">IntRange [lo, hi]</p>
            <code className="text-xs text-gray-800">
              result = lo + floor(r * (hi - lo + 1))
            </code>
          </div>

          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">WeightedChoice</p>
            <CodeBlock>{`total = sum of all weights
target = r * total
# Walk through choices, subtracting weights:
for each (choice, weight):
  if target < weight: return choice
  target -= weight`}</CodeBlock>
          </div>

          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">Shuffle (Fisher-Yates)</p>
            <CodeBlock>{`# Uses per-position HKDF sub-values:
items = [...original list]
for i from (n-1) down to 1:
  sub = HKDF-Expand(prk, info="veritas-shuffle-{i}", length=32)
  j = floor(big_endian_integer(sub) / 2^256 * (i + 1))
  swap items[i] and items[j]`}</CodeBlock>
          </div>
        </div>
      </Section>

      {/* Algorithm reference */}
      <Section title="Algorithm reference">
        <CodeBlock>{`# Full verification pseudocode:

# 1. Fetch audit log
log = GET /api/ceremonies/{id}/log

# 2. Extract ceremony_resolved event
resolved = log.entries.find(e => e.event_type == "ceremony_resolved")
proof = resolved.event_data.outcome.outcomeProof
inputs = proof.proofEntropyInputs
reported_combined = resolved.event_data.outcome.combinedEntropy
reported_outcome = resolved.event_data.outcome.outcomeValue

# 3. Verify entropy combination
# Sort inputs by (priority, sort_key) — see table above
sorted_inputs = sort(inputs, key=canonical_sort_key)
concat = b""
for input in sorted_inputs:
    concat += bytes.fromhex(input.ecValue)
computed_combined = SHA256(concat)
assert computed_combined == reported_combined

# 4. Verify outcome derivation
prk = HMAC_SHA256(key=b"veritas-salt", data=computed_combined)
okm = HKDF_Expand(prk, info=b"veritas-uniform", length=32)
r = int.from_bytes(okm, 'big') / 2**256

# Apply type-specific derivation (see above)
computed_outcome = derive(ceremony_type, r, prk)
assert computed_outcome == reported_outcome`}</CodeBlock>

        <div className="bg-gray-50 rounded p-3">
          <p className="text-xs font-medium text-gray-600 mb-2">HKDF parameters:</p>
          <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
            <span className="text-gray-500">Hash:</span>
            <code className="font-mono text-gray-800">SHA-256</code>
            <span className="text-gray-500">Salt:</span>
            <code className="font-mono text-gray-800">"veritas-salt"</code>
            <span className="text-gray-500">Info (uniform):</span>
            <code className="font-mono text-gray-800">"veritas-uniform"</code>
            <span className="text-gray-500">Info (shuffle):</span>
            <code className="font-mono text-gray-800">{'"veritas-shuffle-{i}"'}</code>
            <span className="text-gray-500">Output length:</span>
            <code className="font-mono text-gray-800">32 bytes</code>
          </div>
        </div>

        <p className="text-xs text-gray-500">
          The authoritative reference is the Veritas source code (outcome derivation
          and HKDF/entropy combination modules), available on the project repository.
        </p>
      </Section>
    </div>
  )
}
