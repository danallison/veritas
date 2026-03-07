import type { IdentityMode, Phase } from '../api/types'

const PHASES: Phase[] = ['Gathering', 'AwaitingRosterAcks', 'Pending', 'AwaitingReveals', 'Resolving', 'Finalized']
const TERMINAL: Phase[] = ['Expired', 'Cancelled', 'Disputed']

const LABELS: Record<Phase, string> = {
  Gathering: 'Gathering',
  AwaitingRosterAcks: 'Roster',
  Pending: 'Commitments',
  AwaitingReveals: 'Reveals',
  AwaitingBeacon: 'Beacon',
  Resolving: 'Determining outcome',
  Finalized: 'Done',
  Expired: 'Expired',
  Cancelled: 'Cancelled',
  Disputed: 'Disputed',
}

export default function PhaseIndicator({
  phase,
  identityMode = 'SelfCertified',
}: {
  phase: Phase
  identityMode?: IdentityMode
}) {
  if (TERMINAL.includes(phase)) {
    return (
      <span className="inline-block px-3 py-1 rounded-full text-sm font-medium bg-red-100 text-red-700">
        {LABELS[phase]}
      </span>
    )
  }

  const phases = PHASES

  // Map AwaitingBeacon to the same step as AwaitingReveals
  const lookupPhase = phase === 'AwaitingBeacon' ? 'AwaitingReveals' : phase
  const currentIdx = phases.indexOf(lookupPhase)

  return (
    <div className="flex items-center gap-1">
      {phases.map((p, i) => {
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
            {i < phases.length - 1 && (
              <div className={`w-6 h-0.5 ${done ? 'bg-indigo-600' : 'bg-gray-200'}`} />
            )}
          </div>
        )
      })}
      <span className="ml-2 text-sm text-gray-600">{LABELS[phase]}</span>
    </div>
  )
}
