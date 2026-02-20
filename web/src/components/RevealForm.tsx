import { useState } from 'react'
import { api } from '../api/client'
import { useParticipant } from '../hooks/useParticipant'
import { useCeremonySecrets } from '../hooks/useCeremonySecrets'

export default function RevealForm({
  ceremonyId,
  onRevealed,
}: {
  ceremonyId: string
  onRevealed: () => void
}) {
  const { participantId } = useParticipant()
  const { getSecrets } = useCeremonySecrets(ceremonyId)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [revealed, setRevealed] = useState(false)

  const secrets = getSecrets()

  if (!secrets?.entropy) {
    return (
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
        <p className="text-yellow-800 text-sm">
          No stored entropy found for this ceremony. You may have committed from a different
          browser or device, or your browser storage was cleared.
        </p>
      </div>
    )
  }

  if (revealed) {
    return (
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <p className="text-blue-800 text-sm">Entropy revealed successfully.</p>
      </div>
    )
  }

  const handleReveal = async () => {
    setLoading(true)
    setError(null)
    try {
      await api.reveal(ceremonyId, {
        participant_id: participantId,
        entropy_value: secrets.entropy,
      })
      setRevealed(true)
      onRevealed()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Reveal failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <h3 className="font-semibold mb-2">Reveal your entropy</h3>
      <p className="text-sm text-gray-600 mb-3">
        All commitments are in. Submit your entropy to compute the random outcome.
      </p>
      {error && <p className="text-red-600 text-sm mb-2">{error}</p>}
      <button
        onClick={handleReveal}
        disabled={loading}
        className="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700 disabled:opacity-50 transition-colors"
      >
        {loading ? 'Revealing...' : 'Reveal Entropy'}
      </button>
    </div>
  )
}
