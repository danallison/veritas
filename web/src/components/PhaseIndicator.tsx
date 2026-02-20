import type { Phase } from '../api/types'

const PHASES: Phase[] = ['Pending', 'AwaitingReveals', 'Resolving', 'Finalized']
const TERMINAL: Phase[] = ['Expired', 'Cancelled', 'Disputed']

const LABELS: Record<Phase, string> = {
  Pending: 'Commitments',
  AwaitingReveals: 'Reveals',
  AwaitingBeacon: 'Beacon',
  Resolving: 'Determining outcome',
  Finalized: 'Done',
  Expired: 'Expired',
  Cancelled: 'Cancelled',
  Disputed: 'Disputed',
}

export default function PhaseIndicator({ phase }: { phase: Phase }) {
  if (TERMINAL.includes(phase)) {
    return (
      <span className="inline-block px-3 py-1 rounded-full text-sm font-medium bg-red-100 text-red-700">
        {LABELS[phase]}
      </span>
    )
  }

  const currentIdx = PHASES.indexOf(phase === 'AwaitingBeacon' ? 'AwaitingReveals' : phase)

  return (
    <div className="flex items-center gap-1">
      {PHASES.map((p, i) => {
        const done = i < currentIdx
        const active = i === currentIdx
        return (
          <div key={p} className="flex items-center gap-1">
            <div
              className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-medium ${
                done
                  ? 'bg-indigo-600 text-white'
                  : active
                    ? 'bg-indigo-100 text-indigo-700 ring-2 ring-indigo-600'
                    : 'bg-gray-200 text-gray-500'
              }`}
            >
              {i + 1}
            </div>
            {i < PHASES.length - 1 && (
              <div className={`w-6 h-0.5 ${done ? 'bg-indigo-600' : 'bg-gray-200'}`} />
            )}
          </div>
        )
      })}
      <span className="ml-2 text-sm text-gray-600">{LABELS[phase]}</span>
    </div>
  )
}
