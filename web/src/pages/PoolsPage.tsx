import { useState, useEffect } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { verificationApi } from '../api/verificationClient'
import type { VolunteerPool, CreatePoolRequest } from '../api/verificationTypes'

function PoolCard({ pool }: { pool: VolunteerPool }) {
  return (
    <Link
      to={`/pools/${pool.id}`}
      className="block bg-white border border-gray-200 rounded-lg p-4 hover:border-indigo-300 hover:shadow-sm transition-all"
    >
      <div className="flex items-start justify-between">
        <div>
          <h3 className="font-semibold text-gray-900">{pool.name}</h3>
          {pool.description && (
            <p className="text-sm text-gray-600 mt-1">{pool.description}</p>
          )}
        </div>
        <span className="text-xs px-2 py-1 bg-indigo-50 text-indigo-700 rounded-full">
          {pool.task_type === 'cross_validation' ? 'Cross-Validation' : pool.task_type}
        </span>
      </div>
      <div className="flex gap-4 mt-3 text-xs text-gray-500">
        <span>{pool.active_member_count} active / {pool.member_count} members</span>
        <span>Selects {pool.selection_size} per task</span>
      </div>
    </Link>
  )
}

export default function PoolsPage() {
  const navigate = useNavigate()
  const [pools, setPools] = useState<VolunteerPool[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showCreate, setShowCreate] = useState(false)

  // Create form state
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [taskType, setTaskType] = useState('cross_validation')
  const [selectionSize, setSelectionSize] = useState(2)
  const [creating, setCreating] = useState(false)

  useEffect(() => {
    verificationApi.listPools()
      .then(setPools)
      .catch(err => setError(err instanceof Error ? err.message : 'Failed to load pools'))
      .finally(() => setLoading(false))
  }, [])

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreating(true)
    setError(null)

    const req: CreatePoolRequest = {
      name: name.trim(),
      description: description.trim(),
      task_type: taskType,
      selection_size: selectionSize,
    }

    try {
      const pool = await verificationApi.createPool(req)
      navigate(`/pools/${pool.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create pool')
    } finally {
      setCreating(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Volunteer Pools</h1>
          <p className="text-gray-600 mt-1">Groups of agents ready to be selected for tasks.</p>
        </div>
        <button
          onClick={() => setShowCreate(!showCreate)}
          className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition-colors"
        >
          {showCreate ? 'Cancel' : 'Create Pool'}
        </button>
      </div>

      {showCreate && (
        <form onSubmit={handleCreate} className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Pool Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g., Claude Sonnet Verification Pool"
              required
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What this pool is for"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>
          <div className="flex gap-4">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Task Type</label>
              <select
                value={taskType}
                onChange={(e) => setTaskType(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              >
                <option value="cross_validation">Cross-Validation</option>
                <option value="custom">Custom Task</option>
              </select>
            </div>
            <div className="w-32">
              <label className="block text-sm font-medium text-gray-700 mb-1">Select N</label>
              <input
                type="number"
                value={selectionSize}
                onChange={(e) => setSelectionSize(parseInt(e.target.value) || 2)}
                min={1}
                max={20}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>
          </div>
          <button
            type="submit"
            disabled={creating}
            className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition-colors disabled:opacity-50"
          >
            {creating ? 'Creating...' : 'Create Pool'}
          </button>
        </form>
      )}

      {error && (
        <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <div className="text-center text-gray-500 py-8">Loading pools...</div>
      ) : pools.length === 0 ? (
        <div className="text-center text-gray-500 py-8">
          <p>No pools yet.</p>
          <p className="text-sm mt-1">Create a pool to start verifying AI output.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {pools.map(pool => <PoolCard key={pool.id} pool={pool} />)}
        </div>
      )}
    </div>
  )
}
