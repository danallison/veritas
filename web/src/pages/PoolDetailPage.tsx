import { useState, useEffect } from 'react'
import { useParams, Link } from 'react-router-dom'
import { verificationApi } from '../api/verificationClient'
import type { VolunteerPool, PoolMember, JoinPoolRequest } from '../api/verificationTypes'

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    active: 'bg-green-50 text-green-700',
    suspended: 'bg-yellow-50 text-yellow-700',
    withdrawn: 'bg-gray-100 text-gray-500',
  }
  return (
    <span className={`text-xs px-2 py-0.5 rounded-full ${colors[status] ?? 'bg-gray-100 text-gray-500'}`}>
      {status}
    </span>
  )
}

function MemberRow({ member }: { member: PoolMember }) {
  return (
    <div className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
      <div className="flex items-center gap-3">
        <div>
          <span className="text-sm font-medium text-gray-900">{member.display_name}</span>
          <p className="text-xs text-gray-500 font-mono">{member.agent_id.slice(0, 12)}...</p>
        </div>
      </div>
      <div className="flex items-center gap-3">
        {member.capabilities.length > 0 && (
          <div className="flex gap-1">
            {member.capabilities.map(cap => (
              <span key={cap} className="text-xs px-1.5 py-0.5 bg-indigo-50 text-indigo-600 rounded">
                {cap}
              </span>
            ))}
          </div>
        )}
        <StatusBadge status={member.status} />
      </div>
    </div>
  )
}

export default function PoolDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [pool, setPool] = useState<VolunteerPool | null>(null)
  const [members, setMembers] = useState<PoolMember[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  // Join form
  const [showJoin, setShowJoin] = useState(false)
  const [agentId, setAgentId] = useState('')
  const [publicKey, setPublicKey] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [capabilities, setCapabilities] = useState('')
  const [joining, setJoining] = useState(false)

  useEffect(() => {
    if (!id) return
    Promise.all([
      verificationApi.getPool(id),
      verificationApi.getMembers(id),
    ])
      .then(([poolData, membersData]) => {
        setPool(poolData)
        setMembers(membersData)
      })
      .catch(err => setError(err instanceof Error ? err.message : 'Failed to load pool'))
      .finally(() => setLoading(false))
  }, [id])

  const handleJoin = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!id) return
    setJoining(true)
    setError(null)

    const req: JoinPoolRequest = {
      agent_id: agentId.trim(),
      public_key: publicKey.trim(),
      display_name: displayName.trim(),
      capabilities: capabilities.split(',').map(c => c.trim()).filter(Boolean),
    }

    try {
      const member = await verificationApi.joinPool(id, req)
      setMembers(prev => [...prev, member])
      setShowJoin(false)
      setAgentId('')
      setPublicKey('')
      setDisplayName('')
      setCapabilities('')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to join pool')
    } finally {
      setJoining(false)
    }
  }

  if (loading) {
    return <div className="text-center text-gray-500 py-12">Loading pool...</div>
  }

  if (error && !pool) {
    return (
      <div className="space-y-4">
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">{error}</div>
        <Link to="/pools" className="text-indigo-600 hover:underline text-sm">Back to pools</Link>
      </div>
    )
  }

  if (!pool) return null

  const activeCount = members.filter(m => m.status === 'active').length

  return (
    <div className="space-y-6">
      <div>
        <Link to="/pools" className="text-sm text-indigo-600 hover:underline">All Pools</Link>
        <h1 className="text-2xl font-bold text-gray-900 mt-1">{pool.name}</h1>
        {pool.description && <p className="text-gray-600 mt-1">{pool.description}</p>}
      </div>

      {/* Pool info */}
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="grid grid-cols-3 gap-4 text-sm">
          <div>
            <span className="text-gray-500">Task Type</span>
            <p className="font-medium">{pool.task_type === 'cross_validation' ? 'Cross-Validation' : pool.task_type}</p>
          </div>
          <div>
            <span className="text-gray-500">Selection Size</span>
            <p className="font-medium">{pool.selection_size} per task</p>
          </div>
          <div>
            <span className="text-gray-500">Members</span>
            <p className="font-medium">{activeCount} active / {members.length} total</p>
          </div>
        </div>
        <p className="text-xs text-gray-400 mt-3">Pool ID: {pool.id}</p>
      </div>

      {/* Members */}
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-sm font-semibold text-gray-700 uppercase tracking-wide">Members</h2>
          <button
            onClick={() => setShowJoin(!showJoin)}
            className="text-sm text-indigo-600 hover:text-indigo-700"
          >
            {showJoin ? 'Cancel' : 'Join Pool'}
          </button>
        </div>

        {showJoin && (
          <form onSubmit={handleJoin} className="bg-gray-50 rounded-lg p-3 mb-4 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <input
                type="text"
                value={agentId}
                onChange={(e) => setAgentId(e.target.value)}
                placeholder="Agent ID (UUID)"
                required
                className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
              <input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="Display name"
                required
                className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
            <input
              type="text"
              value={publicKey}
              onChange={(e) => setPublicKey(e.target.value)}
              placeholder="Ed25519 public key (hex)"
              required
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
            <input
              type="text"
              value={capabilities}
              onChange={(e) => setCapabilities(e.target.value)}
              placeholder="Capabilities (comma-separated, e.g. claude-sonnet, python)"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
            <button
              type="submit"
              disabled={joining}
              className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition-colors disabled:opacity-50"
            >
              {joining ? 'Joining...' : 'Join'}
            </button>
          </form>
        )}

        {error && (
          <div className="p-2 bg-red-50 border border-red-200 rounded text-sm text-red-700 mb-3">
            {error}
          </div>
        )}

        {members.length === 0 ? (
          <p className="text-sm text-gray-500 py-4 text-center">No members yet. Be the first to join.</p>
        ) : (
          <div>{members.map(m => <MemberRow key={m.agent_id} member={m} />)}</div>
        )}
      </div>

      {/* Actions */}
      <div className="flex gap-3">
        <Link
          to={`/verify/new?pool=${pool.id}`}
          className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition-colors"
        >
          Submit for Verification
        </Link>
      </div>
    </div>
  )
}
