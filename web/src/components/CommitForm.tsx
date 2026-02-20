import { useState } from 'react'
import { api } from '../api/client'
import { generateEntropy, computeSeal } from '../crypto/entropy'
import { useParticipant } from '../hooks/useParticipant'
import { useCeremonySecrets } from '../hooks/useCeremonySecrets'
import type { EntropyMethod } from '../api/types'

export default function CommitForm({
  ceremonyId,
  entropyMethod,
  onCommitted,
}: {
  ceremonyId: string
  entropyMethod: EntropyMethod
  onCommitted: () => void
}) {
  const { participantId, displayName, setDisplayName } = useParticipant()
  const { getSecrets, saveSecrets } = useCeremonySecrets(ceremonyId)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [localName, setLocalName] = useState(displayName)

  const alreadyCommitted = getSecrets() !== null
  const needsSeal = entropyMethod === 'ParticipantReveal' || entropyMethod === 'Combined'

  const handleCommit = async () => {
    setLoading(true)
    setError(null)
    try {
      let entropy_seal: string | undefined
      let entropy: string | undefined
      if (needsSeal) {
        entropy = generateEntropy()
        const seal = await computeSeal(ceremonyId, participantId, entropy)
        entropy_seal = seal
      }

      const trimmedName = localName.trim()
      if (trimmedName) {
        setDisplayName(trimmedName)
      }

      await api.commit(ceremonyId, {
        participant_id: participantId,
        entropy_seal,
        display_name: trimmedName || undefined,
      })
      saveSecrets({ entropy, seal: entropy_seal, committed: true })
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
      {error && <p className="text-red-600 text-sm mb-2">{error}</p>}
      <button
        onClick={handleCommit}
        disabled={loading}
        className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 disabled:opacity-50 transition-colors"
      >
        {loading ? 'Committing...' : 'Commit'}
      </button>
    </div>
  )
}
