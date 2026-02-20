import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import type { CeremonyResponse, EntropyMethod, Phase } from '../api/types'

const PHASE_LABELS: Record<Phase, string> = {
  Pending: 'Pending',
  AwaitingReveals: 'Awaiting reveals',
  AwaitingBeacon: 'Awaiting beacon',
  Resolving: 'Determining outcome',
  Finalized: 'Finalized',
  Expired: 'Expired',
  Cancelled: 'Cancelled',
  Disputed: 'Disputed',
}

const METHOD_LABELS: Record<EntropyMethod, string> = {
  OfficiantVRF: 'Server generated',
  ExternalBeacon: 'External beacon',
  ParticipantReveal: 'Participant reveal',
  Combined: 'Combined',
}

export default function HomePage() {
  const [joinId, setJoinId] = useState('')
  const [ceremonies, setCeremonies] = useState<CeremonyResponse[]>([])
  const navigate = useNavigate()

  useEffect(() => {
    api.listCeremonies().then(setCeremonies).catch(() => {})
  }, [])

  const handleJoin = (e: React.FormEvent) => {
    e.preventDefault()
    const id = joinId.trim()
    if (id) navigate(`/ceremonies/${id}`)
  }

  return (
    <div className="space-y-8">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Veritas</h1>
        <p className="text-gray-600">Verifiable social randomness you can trust</p>
      </div>

      <div className="flex gap-4 justify-center">
        <Link
          to="/create"
          className="px-6 py-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors font-medium"
        >
          Create Ceremony
        </Link>
        <Link
          to="/random"
          className="px-6 py-3 bg-white border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors font-medium"
        >
          Random Tools
        </Link>
      </div>

      <form onSubmit={handleJoin} className="flex gap-2 max-w-md mx-auto">
        <input
          type="text"
          value={joinId}
          onChange={(e) => setJoinId(e.target.value)}
          placeholder="Paste ceremony ID to join..."
          className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
        />
        <button
          type="submit"
          className="px-4 py-2 bg-gray-800 text-white rounded-lg text-sm hover:bg-gray-900 transition-colors"
        >
          Join
        </button>
      </form>

      {ceremonies.length > 0 && (
        <div>
          <h2 className="text-lg font-semibold mb-3">Recent Ceremonies</h2>
          <div className="space-y-2">
            {ceremonies.slice(0, 10).map((c) => (
              <Link
                key={c.id}
                to={`/ceremonies/${c.id}`}
                className="block p-3 bg-white border border-gray-200 rounded-lg hover:border-indigo-300 transition-colors"
              >
                <div className="flex justify-between items-center">
                  <div>
                    <p className="font-medium text-sm">{c.question}</p>
                    <p className="text-xs text-gray-500">
                      {c.ceremony_type.tag}
                      {' \u00B7 '}{METHOD_LABELS[c.entropy_method]}
                      {' \u00B7 '}{c.commitment_count}/{c.required_parties} committed
                    </p>
                  </div>
                  <span className={`text-xs px-2 py-0.5 rounded-full ${
                    c.phase === 'Finalized' ? 'bg-green-100 text-green-700' :
                    c.phase === 'Pending' ? 'bg-yellow-100 text-yellow-700' :
                    'bg-gray-100 text-gray-600'
                  }`}>
                    {PHASE_LABELS[c.phase]}
                  </span>
                </div>
              </Link>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
