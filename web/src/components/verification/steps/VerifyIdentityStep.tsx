import RunnableCodeBlock from '../RunnableCodeBlock'
import { verifyIdentityCode, VERIFY_IDENTITY_PLACEHOLDER } from '../codeStrings'
import type { RosterEntry, CommitSigEntry } from '../auditLogParsing'

interface VerifyIdentityStepProps {
  ceremonyId: string | null
  paramsHash: string | null
  roster: RosterEntry[] | null
  ackSignatures: Record<string, string> | null
  commitSignatures: CommitSigEntry[] | null
  skippedReason?: string
}

export default function VerifyIdentityStep({
  ceremonyId,
  paramsHash,
  roster,
  ackSignatures,
  commitSignatures,
  skippedReason,
}: VerifyIdentityStepProps) {
  const hasData = ceremonyId && paramsHash && roster && roster.length > 0 && ackSignatures && commitSignatures
  const code = hasData
    ? verifyIdentityCode(ceremonyId, paramsHash, roster, ackSignatures, commitSignatures)
    : VERIFY_IDENTITY_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 4: Verify participant identity (self-certified ceremonies)"
      description={
        <>
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
              <li><strong>Public key registration</strong> — recorded in
                the <code className="text-xs bg-indigo-100 px-0.5 rounded">participant_joined</code> event</li>
              <li><strong>Roster signature</strong> — a signature over the ceremony
                roster, proving active participation at this stage</li>
              <li><strong>Signed commitment</strong> — a signature over the commitment
                payload, binding the key holder to accepting the outcome</li>
            </ol>
            <p className="text-sm text-indigo-800 mt-2">
              To deny involvement, a participant would have to claim their private key was
              compromised — a much stronger claim than "that wasn't me."
            </p>
          </div>

          <div className="space-y-3 mt-3">
            <div>
              <h3 className="text-sm font-medium text-gray-700">4a. Extract the roster</h3>
              <p className="text-sm text-gray-700">
                The <code className="text-xs bg-gray-100 px-1 rounded">roster_finalized</code> event
                contains the locked roster: an ordered list of (participant_id, public_key) pairs.
              </p>
            </div>

            <div>
              <h3 className="text-sm font-medium text-gray-700">4b. Verify roster signatures</h3>
              <p className="text-sm text-gray-700">
                Each participant signed the canonical roster payload. The payload is:
              </p>
              <pre className="bg-gray-50 border border-gray-200 rounded p-2 text-xs mt-1 overflow-x-auto">{`roster_payload = "veritas-roster-v2:"
  || ceremony_id_ascii
  || params_hash (32 bytes)
  || participant_id_1_ascii || public_key_1_bytes
  || participant_id_2_ascii || public_key_2_bytes
  || ...

Participants sorted by participant_id (UUID lexicographic).
Public keys are 32 raw bytes (hex-decoded from roster).`}</pre>
            </div>

            <div>
              <h3 className="text-sm font-medium text-gray-700">4c. Verify commit signatures</h3>
              <p className="text-sm text-gray-700">
                Each participant also signed their commitment payload:
              </p>
              <pre className="bg-gray-50 border border-gray-200 rounded p-2 text-xs mt-1 overflow-x-auto">{`commit_payload = "veritas-commit-v2:"
  || ceremony_id_ascii
  || participant_id_ascii
  || params_hash (32 bytes)
  || seal_hash_bytes?    (present if entropy method uses seals)`}</pre>
            </div>
          </div>

          <p className="text-xs text-gray-500 mt-2">
            Applies to <strong>SelfCertified</strong> identity mode. Requires browser support
            for Ed25519 (Chrome 113+, Safari 17+).
          </p>
        </>
      }
      code={code}
      disabled={!hasData}
      skippedReason={skippedReason}
    />
  )
}
