// Cost savings visualization comparing with/without pool.

import { useState } from 'react'
import { estimateCallCost, formatUsd, formatSavings } from '../../utils/costs'

const LATENCY_PER_CALL_MS = 2800  // ~2.8s typical LLM API call
const CACHE_LATENCY_MS = 5        // cache lookup

function formatLatency(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

interface Props {
  model: string
  validatorCount: number
  cacheHitCount: number
}

export default function CostComparisonCard({ model, validatorCount, cacheHitCount }: Props) {
  const [agentCount, setAgentCount] = useState(validatorCount + cacheHitCount)
  const costPerCall = estimateCallCost(model).costUsd

  // Without pool: every agent makes their own API call
  const withoutPoolCalls = agentCount
  const withoutPoolCost = withoutPoolCalls * costPerCall
  const withoutPoolLatency = withoutPoolCalls * LATENCY_PER_CALL_MS

  // With pool: only validators compute, rest get cache hits
  const withPoolCalls = Math.min(validatorCount, agentCount)
  const withPoolCost = withPoolCalls * costPerCall
  const hits = Math.max(0, agentCount - validatorCount)
  const withPoolLatency = withPoolCalls * LATENCY_PER_CALL_MS + hits * CACHE_LATENCY_MS

  const latencySaved = withoutPoolLatency - withPoolLatency
  const latencyPct = withoutPoolLatency > 0 ? ((latencySaved / withoutPoolLatency) * 100).toFixed(0) : '0'

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Cost Comparison</h3>

      <div className="mb-4">
        <label className="text-sm text-gray-600 block mb-1">
          Total agents needing this computation: <span className="font-medium">{agentCount}</span>
        </label>
        <input
          type="range"
          min={validatorCount}
          max={50}
          value={agentCount}
          onChange={(e) => setAgentCount(parseInt(e.target.value))}
          className="w-full"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="p-4 rounded-lg bg-red-50 border border-red-200">
          <div className="text-sm font-medium text-red-800 mb-2">Without Pool</div>
          <div className="text-2xl font-bold text-red-900">{formatUsd(withoutPoolCost)}</div>
          <div className="text-xs text-red-700 mt-1">{withoutPoolCalls} API calls</div>
          <div className="text-xs text-red-700">0 cache hits</div>
          <div className="text-xs text-red-700 mt-2">Total latency: {formatLatency(withoutPoolLatency)}</div>
        </div>
        <div className="p-4 rounded-lg bg-green-50 border border-green-200">
          <div className="text-sm font-medium text-green-800 mb-2">With Pool</div>
          <div className="text-2xl font-bold text-green-900">{formatUsd(withPoolCost)}</div>
          <div className="text-xs text-green-700 mt-1">{withPoolCalls} API calls</div>
          <div className="text-xs text-green-700">{hits} cache hits ({formatLatency(CACHE_LATENCY_MS)} each)</div>
          <div className="text-xs text-green-700 mt-2">Total latency: {formatLatency(withPoolLatency)}</div>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-4">
        <div className="p-3 bg-indigo-50 rounded-lg text-center">
          <div className="text-xs text-indigo-600 mb-1">Dollar savings</div>
          <span className="text-sm font-medium text-indigo-800">
            {formatSavings(withoutPoolCost, withPoolCost)}
          </span>
        </div>
        <div className="p-3 bg-indigo-50 rounded-lg text-center">
          <div className="text-xs text-indigo-600 mb-1">Latency savings</div>
          <span className="text-sm font-medium text-indigo-800">
            {formatLatency(latencySaved)} saved ({latencyPct}% reduction)
          </span>
        </div>
      </div>
    </div>
  )
}
