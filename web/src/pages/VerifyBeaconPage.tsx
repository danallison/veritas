import { useEffect, useState } from 'react'
import { api } from '../api/client'
import type { BeaconVerificationGuideResponse } from '../api/types'

export default function VerifyBeaconPage() {
  const [guide, setGuide] = useState<BeaconVerificationGuideResponse | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api.getBeaconVerificationGuide()
      .then(setGuide)
      .catch((e) => setError(e.message))
  }, [])

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Beacon Verification Guide</h1>
      <p className="text-gray-600 text-sm">
        Veritas ceremonies that use the <strong>ExternalBeacon</strong> or <strong>Combined</strong> entropy
        method anchor their randomness to a publicly verifiable drand beacon. You can independently verify
        that the beacon value used in a ceremony is authentic by checking the BLS signature against the
        drand network's public key.
      </p>

      <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
        <h2 className="text-lg font-semibold">Why verify?</h2>
        <p className="text-sm text-gray-700">
          Verifying the beacon signature proves that the randomness came from the drand distributed
          network and was not fabricated by the Veritas server. This is a key part of the trust model:
          you don't need to trust Veritas — you can verify independently.
        </p>
      </section>

      <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
        <h2 className="text-lg font-semibold">Verification steps</h2>
        {error && <p className="text-red-600 text-sm">{error}</p>}
        {guide ? (
          <ol className="list-decimal list-inside space-y-2 text-sm text-gray-700">
            {guide.steps.map((step, i) => (
              <li key={i} className="leading-relaxed">{step.replace(/^\d+\.\s*/, '')}</li>
            ))}
          </ol>
        ) : !error ? (
          <p className="text-sm text-gray-500">Loading...</p>
        ) : null}
      </section>

      {guide && (
        <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
          <h2 className="text-lg font-semibold">Server configuration</h2>
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            <dt className="font-medium text-gray-600">Scheme</dt>
            <dd className="font-mono text-gray-800">{guide.scheme}</dd>

            <dt className="font-medium text-gray-600">Chain hash</dt>
            <dd className="font-mono text-gray-800 break-all">{guide.chain_hash}</dd>

            <dt className="font-medium text-gray-600">DST</dt>
            <dd className="font-mono text-gray-800 break-all">{guide.dst}</dd>

            <dt className="font-medium text-gray-600">drand info URL</dt>
            <dd>
              <a href={guide.drand_info_url} target="_blank" rel="noopener noreferrer"
                className="text-indigo-600 hover:underline break-all">
                {guide.drand_info_url}
              </a>
            </dd>

            <dt className="font-medium text-gray-600">Public key</dt>
            <dd className="font-mono text-gray-800 break-all text-xs">
              {guide.public_key ?? <span className="text-gray-400 italic">Not available</span>}
            </dd>
          </dl>
        </section>
      )}

      <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
        <h2 className="text-lg font-semibold">Pseudocode</h2>
        <pre className="bg-gray-50 border border-gray-200 rounded p-4 text-xs overflow-x-auto leading-relaxed">{`# From the audit log's BeaconAnchored event:
anchor = event_data["anchor"]
ba_round     = anchor["baRound"]       # round number
ba_signature = anchor["baSignature"]   # hex-encoded BLS signature
ba_value     = anchor["baValue"]       # hex-encoded randomness

# Step 1: Verify randomness derivation
assert ba_value == SHA256(bytes.fromhex(ba_signature))

# Step 2: Construct the message
round_bytes = ba_round.to_bytes(8, byteorder='big')
message = SHA256(round_bytes)

# Step 3: Fetch drand public key
public_key = fetch(drand_info_url).public_key

# Step 4: Verify BLS signature
DST = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_"
assert bls_verify(public_key, message, bytes.fromhex(ba_signature), DST)`}</pre>
      </section>

      <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-3">
        <h2 className="text-lg font-semibold">Reference implementations</h2>
        <ul className="list-disc list-inside text-sm text-gray-700 space-y-1">
          <li><strong>Go / JavaScript:</strong> drand/drand-client</li>
          <li><strong>Rust:</strong> drand/drand-verify</li>
          <li><strong>Haskell:</strong> Veritas.Crypto.BLS (this project)</li>
        </ul>
        <p className="text-xs text-gray-500 mt-2">
          For maximum trust, fetch the drand public key directly from the drand network rather
          than relying on the value served by this endpoint.
        </p>
      </section>
    </div>
  )
}
