import { useState } from 'react'
import { api } from '../api/client'
import { generateEntropy, computeSeal } from '../crypto/entropy'
import { useParticipant } from '../hooks/useParticipant'
import { useCeremonySecrets } from '../hooks/useCeremonySecrets'
import { commitPayloadHex, describeCommitPayload } from '../crypto/identity'
import { verifyParamsHash } from '../crypto/ceremonyParams'
import SigningInstructions from './SigningInstructions'
import type { EntropyMethod, CeremonyResponse } from '../api/types'

interface PreparedCommit {
  entropy: string | undefined
  seal: string | undefined
  payloadHex: string
  payloadDescription: string
}

// TODO: OAuth mode will use bearer token instead of Ed25519 signature
export default function CommitForm({
  ceremonyId,
  entropyMethod,
  ceremony,
  onCommitted,
}: {
  ceremonyId: string
  entropyMethod: EntropyMethod
  ceremony?: CeremonyResponse
  onCommitted: () => void
}) {
  const { participantId, displayName, setDisplayName } = useParticipant()
  const { getSecrets, saveSecrets } = useCeremonySecrets(ceremonyId)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [localName, setLocalName] = useState(displayName)
  const [preparedCommit, setPreparedCommit] = useState<PreparedCommit | null>(null)

  const alreadyCommitted = getSecrets() !== null
  const needsSeal = entropyMethod === 'ParticipantReveal' || entropyMethod === 'Combined'

  const handlePrepare = async () => {
    setLoading(true)
    setError(null)
    try {
      // Verify params_hash before presenting signing payload
      if (ceremony) {
        const valid = await verifyParamsHash(ceremony)
        if (!valid) {
          setError('params_hash mismatch: the server\'s hash does not match the ceremony parameters. Do not sign — this could indicate a server error or tampering.')
          return
        }
      }

      let entropy: string | undefined
      let seal: string | undefined
      if (needsSeal) {
        entropy = generateEntropy()
        seal = await computeSeal(ceremonyId, participantId, entropy)
      }

      const paramsHash = ceremony?.params_hash ?? ''
      const payHex = commitPayloadHex(ceremonyId, participantId, paramsHash, seal)
      const payDesc = describeCommitPayload(ceremonyId, participantId, paramsHash, seal, ceremony)

      setPreparedCommit({ entropy, seal, payloadHex: payHex, payloadDescription: payDesc })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to prepare commit')
    } finally {
      setLoading(false)
    }
  }

  const handleSignatureSubmit = async (signatureHex: string) => {
    if (!preparedCommit) return
    setLoading(true)
    setError(null)
    try {
      const trimmedName = localName.trim()
      if (trimmedName) {
        setDisplayName(trimmedName)
      }

      await api.commit(ceremonyId, {
        participant_id: participantId,
        entropy_seal: preparedCommit.seal,
        display_name: trimmedName || undefined,
        signature: signatureHex,
      })
      saveSecrets({
        entropy: preparedCommit.entropy,
        seal: preparedCommit.seal,
        committed: true,
      })
      onCommitted()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Commit failed')
    } finally {
      setLoading(false)
    }
  }

  if (alreadyCommitted) {
    return (
      <div className="bg-green-50 border border-green-200 rounded-lg p-4">
        <p className="text-green-800 text-sm">You're committed to this ceremony.</p>
      </div>
    )
  }

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <h3 className="font-semibold mb-2">Join this ceremony</h3>
      {needsSeal && (
        <p className="text-sm text-gray-600 mb-3">
          Your entropy will be generated automatically and stored in your browser
          for the reveal phase.
        </p>
      )}
      <div className="mb-3">
        <input
          type="text"
          value={localName}
          onChange={(e) => setLocalName(e.target.value)}
          placeholder="Your name (optional)"
          className="w-full px-3 py-2 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
        />
      </div>

      {error && !preparedCommit && <p className="text-red-600 text-sm mb-2">{error}</p>}

      {!preparedCommit && (
        <button
          onClick={handlePrepare}
          disabled={loading}
          className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 disabled:opacity-50 transition-colors"
        >
          {loading ? 'Preparing...' : 'Prepare Commit'}
        </button>
      )}

      {preparedCommit && (
        <div className="mt-2">
          <p className="text-sm text-gray-600 mb-3">
            Sign the commit payload with your private key and paste the signature below.
          </p>
          <SigningInstructions
            payloadHex={preparedCommit.payloadHex}
            payloadDescription={preparedCommit.payloadDescription}
            onSignatureSubmit={handleSignatureSubmit}
            loading={loading}
            error={error}
          />
        </div>
      )}
    </div>
  )
}
