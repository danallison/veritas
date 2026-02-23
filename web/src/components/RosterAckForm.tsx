import { useState, useMemo, useEffect } from 'react'
import { api } from '../api/client'
import { useParticipant } from '../hooks/useParticipant'
import { rosterPayloadHex, describeRosterPayload } from '../crypto/identity'
import { verifyParamsHash } from '../crypto/ceremonyParams'
import SigningInstructions from './SigningInstructions'
import type { RosterEntry, CeremonyResponse } from '../api/types'

export default function RosterAckForm({
  ceremonyId,
  roster,
  ceremony,
  onAcknowledged,
}: {
  ceremonyId: string
  roster: RosterEntry[]
  ceremony: CeremonyResponse
  onAcknowledged: () => void
}) {
  const { participantId } = useParticipant()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [paramsHashValid, setParamsHashValid] = useState<boolean | null>(null)

  useEffect(() => {
    verifyParamsHash(ceremony).then(setParamsHashValid)
  }, [ceremony])

  const myEntry = roster.find((r) => r.participant_id === participantId)
  const alreadyAcked = myEntry?.acknowledged ?? false

  const rosterForSigning = useMemo(
    () => roster.map((r) => ({ participantId: r.participant_id, publicKey: r.public_key })),
    [roster],
  )

  const payloadHex = useMemo(
    () => rosterPayloadHex(ceremonyId, ceremony.params_hash, rosterForSigning),
    [ceremonyId, ceremony.params_hash, rosterForSigning],
  )

  const payloadDescription = useMemo(
    () => describeRosterPayload(ceremonyId, ceremony.params_hash, rosterForSigning, ceremony),
    [ceremonyId, ceremony, rosterForSigning],
  )

  const handleSignatureSubmit = async (signatureHex: string) => {
    setLoading(true)
    setError(null)
    try {
      await api.ackRoster(ceremonyId, {
        participant_id: participantId,
        signature: signatureHex,
      })
      onAcknowledged()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to acknowledge roster')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <h3 className="font-semibold mb-2">Roster Acknowledgment</h3>
      <p className="text-sm text-gray-600 mb-3">
        The roster is locked. Review the participants, then sign the roster
        payload with your private key and paste the signature below.
      </p>

      <div className="mb-4 space-y-2">
        {roster.map((entry) => (
          <div
            key={entry.participant_id}
            className="flex items-center justify-between text-sm bg-gray-50 p-2 rounded"
          >
            <div>
              <span className="font-medium">
                {entry.display_name || `Participant ${entry.participant_id.slice(0, 8)}...`}
              </span>
              <code className="block text-xs text-gray-400 break-all mt-0.5">
                {entry.public_key.slice(0, 16)}...
              </code>
            </div>
            <span
              className={`text-xs px-2 py-0.5 rounded-full ${
                entry.acknowledged
                  ? 'bg-green-100 text-green-700'
                  : 'bg-gray-200 text-gray-500'
              }`}
            >
              {entry.acknowledged ? 'Acknowledged' : 'Pending'}
            </span>
          </div>
        ))}
      </div>

      {paramsHashValid === false && (
        <div className="bg-red-50 border border-red-300 rounded p-3 mb-3">
          <p className="text-red-800 text-sm font-medium">
            Warning: params_hash mismatch
          </p>
          <p className="text-red-700 text-xs mt-1">
            The server's params_hash does not match the ceremony parameters shown
            on this page. Do not sign — the hash may correspond to different
            ceremony rules than what you see. This could indicate a server error
            or tampering.
          </p>
        </div>
      )}

      {myEntry && !alreadyAcked && paramsHashValid === true && (
        <SigningInstructions
          payloadHex={payloadHex}
          payloadDescription={payloadDescription}
          onSignatureSubmit={handleSignatureSubmit}
          loading={loading}
          error={error}
        />
      )}

      {myEntry && !alreadyAcked && paramsHashValid === null && (
        <p className="text-gray-500 text-sm">Verifying ceremony parameters...</p>
      )}

      {alreadyAcked && (
        <p className="text-green-700 text-sm">
          You have acknowledged the roster. Waiting for other participants...
        </p>
      )}

      {!myEntry && (
        <p className="text-gray-500 text-sm">
          You are not a participant in this ceremony.
        </p>
      )}
    </div>
  )
}
