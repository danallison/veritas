import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

export default function HomePage() {
  const [joinId, setJoinId] = useState('')
  const navigate = useNavigate()

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
    </div>
  )
}
