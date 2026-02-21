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
          This guide walks through the full verification pipeline. For any finalized
          ceremony, you can reproduce every step using standard command-line tools.
        </p>
        <div className="bg-gray-50 rounded p-3">
          <p className="text-xs font-medium text-gray-600 mb-2">Verification pipeline:</p>
          <ol className="list-decimal list-inside text-sm text-gray-700 space-y-1">
            <li>Fetch the ceremony audit log</li>
            <li>Verify the drand beacon (if applicable)</li>
            <li>Verify commit-reveal integrity (if applicable)</li>
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
    "outcomeValue": { "tag": "CoinFlipResult", "contents": true },
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

      {/* Step 4: Verify entropy combination */}
      <Section title="Step 4: Verify entropy combination">
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

      {/* Step 5: Verify outcome derivation */}
      <Section title="Step 5: Verify outcome derivation">
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

# Step 3: Convert to rational in [0, 1)
n = big_endian_integer(okm)   # 256-bit unsigned integer
r = n / 2^256                 # rational number in [0, 1)`}</CodeBlock>

        <h3 className="text-sm font-medium text-gray-700">Type-specific derivation</h3>

        <div className="space-y-3">
          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">CoinFlip</p>
            <code className="text-xs text-gray-800">
              result = r &gt;= 0.5 → heads (true), otherwise tails (false)
            </code>
          </div>

          <div className="bg-gray-50 rounded p-3">
            <p className="text-xs font-medium text-gray-600 mb-1">UniformChoice</p>
            <code className="text-xs text-gray-800">
              index = floor(r * num_options) → select from options list
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
          The authoritative reference is the source
          code: <code className="bg-gray-100 px-1 rounded">src/Veritas/Core/Resolution.hs</code> (outcome
          derivation) and <code className="bg-gray-100 px-1 rounded">src/Veritas/Crypto/Hash.hs</code> (HKDF
          and entropy combination).
        </p>
      </Section>
    </div>
  )
}
