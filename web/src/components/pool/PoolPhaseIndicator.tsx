// Phase stepper showing progress through the validation protocol.

const PHASES = ['Setup', 'Register', 'Compute', 'Seal & Reveal', 'Cache', 'Savings']

interface Props {
  currentStep: number
}

export default function PoolPhaseIndicator({ currentStep }: Props) {
  return (
    <div className="mb-8 overflow-x-auto pb-2">
      {/* Beads and connecting lines */}
      <div className="flex items-center p-0.5">
        {PHASES.map((label, i) => {
          const done = i < currentStep
          const active = i === currentStep
          return (
            <div key={label} className="flex items-center">
              {i > 0 && (
                <div className={`w-8 h-0.5 shrink-0 ${done ? 'bg-indigo-600' : 'bg-gray-200'}`} />
              )}
              <div
                className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-medium shrink-0
                  ${done ? 'bg-indigo-600 text-white' : active ? 'ring-2 ring-indigo-600 text-indigo-600 bg-white' : 'bg-gray-200 text-gray-500'}`}
              >
                {done ? '\u2713' : i + 1}
              </div>
            </div>
          )
        })}
      </div>
      {/* Labels */}
      <div className="flex">
        {PHASES.map((label, i) => {
          const active = i === currentStep
          return (
            <div key={label} className="flex items-center">
              {i > 0 && <div className="w-8 shrink-0" />}
              <span className={`w-8 shrink-0 text-center text-xs whitespace-nowrap mt-1 ${active ? 'text-indigo-600 font-medium' : 'text-gray-500'}`}>
                {label}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
