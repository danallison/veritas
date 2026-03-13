import { useState, useEffect, useRef } from 'react'
import { useParams, Link } from 'react-router-dom'
import { verificationApi } from '../api/verificationClient'
import type { Verification, VerdictOutcome } from '../api/verificationTypes'

function outcomeLabel(outcome: VerdictOutcome): string {
  switch (outcome.tag) {
    case 'unanimous': return 'Unanimous'
    case 'majority_agree': return 'Majority Agree'
    case 'inconclusive': return 'Inconclusive'
  }
}

function outcomeColor(outcome: VerdictOutcome): string {
  switch (outcome.tag) {
    case 'unanimous': return 'text-green-700 bg-green-50 border-green-200'
    case 'majority_agree': return 'text-yellow-700 bg-yellow-50 border-yellow-200'
    case 'inconclusive': return 'text-red-700 bg-red-50 border-red-200'
  }
}

function PhaseProgress({ phase }: { phase: string }) {
  const phases = ['collecting', 'deciding', 'decided']
  const currentIdx = phases.indexOf(phase)

  return (
    <div className="flex items-center gap-2">
      {phases.map((p, i) => (
        <div key={p} className="flex items-center gap-2">
          <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
            i < currentIdx ? 'bg-indigo-600 text-white' :
            i === currentIdx ? 'bg-indigo-100 text-indigo-700 ring-2 ring-indigo-600' :
            'bg-gray-100 text-gray-400'
          }`}>
            {i + 1}
          </div>
          <span className={`text-sm ${i === currentIdx ? 'font-medium text-gray-900' : 'text-gray-500'}`}>
            {p === 'collecting' ? 'Collecting' : p === 'deciding' ? 'Deciding' : 'Decided'}
          </span>
          {i < phases.length - 1 && <div className="w-8 h-px bg-gray-300" />}
        </div>
      ))}
    </div>
  )
}

export default function VerificationDetailPage() {
  const { id } = useParams<{ id: string }>()
  const [verification, setVerification] = useState<Verification | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const phaseRef = useRef<string | null>(null)

  // Keep ref in sync with state so the interval callback sees the latest phase
  useEffect(() => {
    phaseRef.current = verification?.phase ?? null
  }, [verification?.phase])

  useEffect(() => {
    if (!id) return

    let cancelled = false
    const fetchData = async () => {
      try {
        const data = await verificationApi.getVerification(id)
        if (!cancelled) {
          setVerification(data)
          setError(null)
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Failed to load verification')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    fetchData()

    // Poll while not decided
    const interval = setInterval(async () => {
      if (phaseRef.current === 'decided') return
      try {
        const data = await verificationApi.getVerification(id)
        if (!cancelled) {
          setVerification(data)
          setError(null)
        }
      } catch {
        // ignore polling errors
      }
    }, 3000)

    return () => {
      cancelled = true
      clearInterval(interval)
    }
  }, [id])

  if (loading) {
    return <div className="text-center text-gray-500 py-12">Loading verification...</div>
  }

  if (error) {
    return (
      <div className="space-y-4">
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">{error}</div>
        <Link to="/verify/new" className="text-indigo-600 hover:underline text-sm">Submit a new verification</Link>
      </div>
    )
  }

  if (!verification) return null

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Verification</h1>
        <p className="text-sm text-gray-500 font-mono mt-1">{verification.id}</p>
      </div>

      <PhaseProgress phase={verification.phase} />

      {/* Spec details */}
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <h2 className="text-sm font-semibold text-gray-700 uppercase tracking-wide">Specification</h2>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <span className="text-gray-500">Description</span>
            <p className="font-medium">{verification.spec.description}</p>
          </div>
          <div>
            <span className="text-gray-500">Comparison</span>
            <p className="font-medium">{verification.spec.comparison_method}</p>
          </div>
          <div>
            <span className="text-gray-500">Fingerprint</span>
            <p className="font-mono text-xs break-all">{verification.spec.computation_fingerprint}</p>
          </div>
          <div>
            <span className="text-gray-500">Validators</span>
            <p className="font-medium">{verification.spec.validator_count}</p>
          </div>
        </div>
      </div>

      {/* Submissions progress */}
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <h2 className="text-sm font-semibold text-gray-700 uppercase tracking-wide">Submissions</h2>
        <div className="flex items-center gap-3">
          <div className="flex-1 bg-gray-100 rounded-full h-3">
            <div
              className="bg-indigo-600 h-3 rounded-full transition-all"
              style={{ width: `${(verification.submission_count / verification.expected_submissions) * 100}%` }}
            />
          </div>
          <span className="text-sm font-medium text-gray-700">
            {verification.submission_count} / {verification.expected_submissions}
          </span>
        </div>
        <div className="text-sm text-gray-600">
          <p>Submitter: <span className="font-mono text-xs">{verification.submitter}</span></p>
          <p>Validators: {verification.validators.map(v => (
            <span key={v} className="font-mono text-xs ml-1">{v.slice(0, 8)}...</span>
          ))}</p>
        </div>
      </div>

      {/* Verdict */}
      {verification.verdict && (
        <div className={`border rounded-lg p-5 ${outcomeColor(verification.verdict.outcome)}`}>
          <h2 className="text-lg font-bold mb-2">Verdict: {outcomeLabel(verification.verdict.outcome)}</h2>
          <div className="space-y-1 text-sm">
            <p>Agreement: {verification.verdict.agreement_count} / {verification.expected_submissions} agents</p>
            {verification.verdict.majority_result && (
              <p>Result: <span className="font-mono text-xs">{verification.verdict.majority_result}</span></p>
            )}
            {verification.verdict.outcome.tag === 'majority_agree' && (
              <p>Dissenters: {verification.verdict.outcome.dissenters.map(d => (
                <span key={d} className="font-mono text-xs ml-1">{d.slice(0, 8)}...</span>
              ))}</p>
            )}
            <p className="text-xs opacity-75">Decided at {new Date(verification.verdict.decided_at).toLocaleString()}</p>
          </div>
        </div>
      )}

      {verification.phase === 'collecting' && (
        <div className="text-center py-4 text-gray-500">
          Waiting for all participants to submit their results...
        </div>
      )}

      {verification.phase === 'deciding' && (
        <div className="text-center py-4 text-gray-500">
          All submissions received. Computing verdict...
        </div>
      )}

      <div className="text-sm text-gray-500">
        Created {new Date(verification.created_at).toLocaleString()}
        {' | '}Pool <span className="font-mono text-xs">{verification.pool_id}</span>
      </div>
    </div>
  )
}
