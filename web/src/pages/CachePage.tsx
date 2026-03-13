import { useState, useEffect } from 'react'
import { verificationApi } from '../api/verificationClient'
import type { CacheEntry, CacheStats, VerdictOutcome } from '../api/verificationTypes'

function outcomeLabel(outcome: VerdictOutcome): string {
  switch (outcome.tag) {
    case 'unanimous': return 'Unanimous'
    case 'majority_agree': return 'Majority'
    case 'inconclusive': return 'Inconclusive'
  }
}

function outcomeBadgeColor(outcome: VerdictOutcome): string {
  switch (outcome.tag) {
    case 'unanimous': return 'bg-green-50 text-green-700'
    case 'majority_agree': return 'bg-yellow-50 text-yellow-700'
    case 'inconclusive': return 'bg-red-50 text-red-700'
  }
}

function CacheEntryRow({ entry }: { entry: CacheEntry }) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <p className="text-sm font-mono text-gray-900 truncate">{entry.fingerprint}</p>
          <p className="text-xs text-gray-500 mt-1">
            Cached {new Date(entry.provenance.cached_at).toLocaleString()}
            {entry.ttl_seconds && ` | TTL: ${entry.ttl_seconds}s`}
          </p>
        </div>
        <span className={`text-xs px-2 py-0.5 rounded-full ml-3 ${outcomeBadgeColor(entry.provenance.verdict_outcome)}`}>
          {outcomeLabel(entry.provenance.verdict_outcome)}
        </span>
      </div>
      <div className="mt-2 text-xs text-gray-600">
        <span>Agreement: {entry.provenance.agreement_count} agents</span>
        <span className="mx-2">|</span>
        <span>Result: <span className="font-mono">{entry.result.slice(0, 32)}{entry.result.length > 32 ? '...' : ''}</span></span>
      </div>
    </div>
  )
}

export default function CachePage() {
  const [entries, setEntries] = useState<CacheEntry[]>([])
  const [stats, setStats] = useState<CacheStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [searchFingerprint, setSearchFingerprint] = useState('')
  const [searchResult, setSearchResult] = useState<CacheEntry | null | undefined>(undefined)
  const [searching, setSearching] = useState(false)

  useEffect(() => {
    Promise.all([
      verificationApi.listCache().catch(() => [] as CacheEntry[]),
      verificationApi.getCacheStats().catch(() => null),
    ])
      .then(([entriesData, statsData]) => {
        setEntries(entriesData)
        setStats(statsData)
      })
      .catch(err => setError(err instanceof Error ? err.message : 'Failed to load cache'))
      .finally(() => setLoading(false))
  }, [])

  const handleSearch = async (e: React.FormEvent) => {
    e.preventDefault()
    const fp = searchFingerprint.trim()
    if (!fp) return
    setSearching(true)
    setSearchResult(undefined)
    try {
      const entry = await verificationApi.lookupCache(fp)
      setSearchResult(entry)
    } catch {
      setSearchResult(null)
    } finally {
      setSearching(false)
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Verified Cache</h1>
        <p className="text-gray-600 mt-1">Content-addressed cache of verified computation results.</p>
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-3 gap-4">
          <div className="bg-white border border-gray-200 rounded-lg p-4 text-center">
            <p className="text-2xl font-bold text-gray-900">{stats.total_entries}</p>
            <p className="text-xs text-gray-500 mt-1">Total Entries</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4 text-center">
            <p className="text-2xl font-bold text-green-600">{stats.unanimous_count}</p>
            <p className="text-xs text-gray-500 mt-1">Unanimous</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4 text-center">
            <p className="text-2xl font-bold text-yellow-600">{stats.majority_count}</p>
            <p className="text-xs text-gray-500 mt-1">Majority</p>
          </div>
        </div>
      )}

      {/* Search */}
      <form onSubmit={handleSearch} className="flex gap-2">
        <input
          type="text"
          value={searchFingerprint}
          onChange={(e) => setSearchFingerprint(e.target.value)}
          placeholder="Search by fingerprint (e.g., sha256:abc123...)"
          className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
        />
        <button
          type="submit"
          disabled={searching}
          className="px-4 py-2 bg-gray-800 text-white rounded-lg text-sm hover:bg-gray-900 transition-colors disabled:opacity-50"
        >
          {searching ? 'Searching...' : 'Lookup'}
        </button>
      </form>

      {searchResult === null && (
        <div className="p-3 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-600">
          No cached result found for that fingerprint.
        </div>
      )}
      {searchResult && <CacheEntryRow entry={searchResult} />}

      {error && (
        <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">{error}</div>
      )}

      {/* Entries list */}
      {loading ? (
        <div className="text-center text-gray-500 py-8">Loading cache...</div>
      ) : entries.length === 0 ? (
        <div className="text-center text-gray-500 py-8">
          <p>Cache is empty.</p>
          <p className="text-sm mt-1">Results are cached after successful verification.</p>
        </div>
      ) : (
        <div className="space-y-3">
          <h2 className="text-sm font-semibold text-gray-700 uppercase tracking-wide">All Entries</h2>
          {entries.map(entry => <CacheEntryRow key={entry.fingerprint} entry={entry} />)}
        </div>
      )}
    </div>
  )
}
