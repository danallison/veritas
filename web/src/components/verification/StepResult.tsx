import type { StepOutput } from './executeStep'

const statusColor: Record<string, string> = {
  pass: 'text-green-700 bg-green-50 border-green-200',
  fail: 'text-red-700 bg-red-50 border-red-200',
  error: 'text-amber-700 bg-amber-50 border-amber-200',
}

const statusLabel: Record<string, string> = {
  pass: '\u2713 PASS',
  fail: '\u2717 FAIL',
  error: '\u26A0 ERROR',
}

export default function StepResult({ result }: { result: StepOutput }) {
  const color = statusColor[result.status] ?? statusColor.error

  return (
    <div className={`border rounded p-3 ${color}`}>
      <div className="space-y-2">
        <div className="flex items-center gap-2">
          <span className="text-xs font-bold">{statusLabel[result.status]}</span>
          <span className="text-xs">{result.summary}</span>
        </div>
        {result.details && result.details.length > 0 && (
          <div className="space-y-1">
            {result.details.map((d, i) => (
              <div key={i} className="flex items-start gap-2 text-xs">
                <span className="shrink-0 opacity-70">{d.label}:</span>
                <code className="font-mono break-all">
                  {d.match === false && <span className="font-bold">{d.value}</span>}
                  {d.match !== false && d.value}
                </code>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
