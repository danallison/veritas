import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { verificationApi } from '../api/verificationClient'
import type { SubmitVerificationRequest } from '../api/verificationTypes'

export default function VerifyPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const [poolId, setPoolId] = useState(searchParams.get('pool') ?? '')
  const [description, setDescription] = useState('')
  const [fingerprint, setFingerprint] = useState('')
  const [submittedResult, setSubmittedResult] = useState('')
  const [comparisonMethod, setComparisonMethod] = useState('exact')
  const [validatorCount, setValidatorCount] = useState(2)
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    const req: SubmitVerificationRequest = {
      pool_id: poolId.trim(),
      description: description.trim(),
      computation_fingerprint: fingerprint.trim(),
      submitted_result: submittedResult.trim() || undefined,
      comparison_method: comparisonMethod,
      validator_count: validatorCount,
    }

    try {
      const verification = await verificationApi.submitVerification(req)
      navigate(`/verify/${verification.id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to submit verification')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Submit for Verification</h1>
        <p className="text-gray-600 mt-1">
          Submit AI output for independent cross-validation by multiple agents.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Pool ID</label>
          <input
            type="text"
            value={poolId}
            onChange={(e) => setPoolId(e.target.value)}
            placeholder="UUID of the volunteer pool"
            required
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
          <p className="text-xs text-gray-500 mt-1">The pool of agents who will verify this output.</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
          <input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="e.g., Verify: What is the capital of France?"
            required
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Computation Fingerprint</label>
          <input
            type="text"
            value={fingerprint}
            onChange={(e) => setFingerprint(e.target.value)}
            placeholder="sha256:abc123..."
            required
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
          <p className="text-xs text-gray-500 mt-1">Content hash of the computation spec. Used for cache lookups.</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Submitted Result (optional)</label>
          <textarea
            value={submittedResult}
            onChange={(e) => setSubmittedResult(e.target.value)}
            placeholder="Hex-encoded result to verify (leave empty if validators compute independently)"
            rows={3}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
        </div>

        <div className="flex gap-4">
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">Comparison Method</label>
            <select
              value={comparisonMethod}
              onChange={(e) => setComparisonMethod(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <option value="exact">Exact Match</option>
              <option value="canonical">Canonical (JSON normalization)</option>
            </select>
          </div>
          <div className="w-32">
            <label className="block text-sm font-medium text-gray-700 mb-1">Validators</label>
            <input
              type="number"
              value={validatorCount}
              onChange={(e) => setValidatorCount(parseInt(e.target.value) || 2)}
              min={1}
              max={10}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>
        </div>

        {error && (
          <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full px-4 py-3 bg-indigo-600 text-white rounded-lg font-medium hover:bg-indigo-700 transition-colors disabled:opacity-50"
        >
          {submitting ? 'Submitting...' : 'Submit for Verification'}
        </button>
      </form>
    </div>
  )
}
