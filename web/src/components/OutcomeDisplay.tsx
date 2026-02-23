import { useEffect, useState } from 'react'
import { api } from '../api/client'
import type { CeremonyType, OutcomeResponse } from '../api/types'

export default function OutcomeDisplay({
  ceremonyId,
  ceremonyType,
}: {
  ceremonyId: string
  ceremonyType: CeremonyType
}) {
  const [outcome, setOutcome] = useState<OutcomeResponse | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api.getOutcome(ceremonyId).then(setOutcome).catch((e) => setError(e.message))
  }, [ceremonyId])

  if (error) return <p className="text-red-600 text-sm">{error}</p>
  if (!outcome) return <p className="text-gray-500 text-sm">Loading outcome...</p>

  const value = outcome.outcome as Record<string, unknown>
  const tag = value?.tag as string | undefined

  return (
    <div className="bg-green-50 border border-green-200 rounded-lg p-4">
      <h3 className="font-semibold text-green-800 mb-2">Outcome</h3>
      {renderResult(tag, value, ceremonyType)}
      <p className="text-xs text-gray-500 mt-2">
        Determined at {new Date(outcome.resolved_at).toLocaleString()}
      </p>
    </div>
  )
}

function renderResult(
  tag: string | undefined,
  value: Record<string, unknown>,
  ceremonyType: CeremonyType,
) {
  const contents = value?.contents
  const typeLabel = ceremonyType.tag

  switch (tag) {
    case 'CoinFlipResult':
      return (
        <p className="text-3xl font-bold text-center py-4">
          {String(contents)}
        </p>
      )
    case 'ChoiceResult':
    case 'WeightedChoiceResult':
      return <p className="text-2xl font-bold text-center py-4">{String(contents)}</p>
    case 'ShuffleResult':
      return (
        <ol className="list-decimal list-inside space-y-1">
          {(contents as string[]).map((item, i) => (
            <li key={i} className="text-lg">{item}</li>
          ))}
        </ol>
      )
    case 'IntRangeResult':
      return <p className="text-3xl font-bold text-center py-4">{String(contents)}</p>
    default:
      return (
        <div>
          <p className="text-sm text-gray-600 mb-1">{typeLabel}</p>
          <pre className="text-sm bg-white p-2 rounded overflow-auto">
            {JSON.stringify(value, null, 2)}
          </pre>
        </div>
      )
  }
}
