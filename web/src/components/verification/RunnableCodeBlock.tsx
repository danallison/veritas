import { useState, useCallback, useMemo } from 'react'
import { executeStep, type StepOutput } from './executeStep'
import { UTILITY_CODE } from './codeStrings'
import { highlightJs } from './highlight'
import StepResult from './StepResult'

interface RunnableCodeBlockProps {
  title: string
  description?: React.ReactNode
  code: string
  disabled?: boolean
  skippedReason?: string
  onResult?: (result: StepOutput) => void
}

function buildStandaloneScript(title: string, code: string): string {
  return `#!/usr/bin/env node
// Veritas Verification: ${title}
// Requires Node.js 20+ (fetch and crypto.subtle are stable)

${UTILITY_CODE}

;(async () => {
${code}
})().then(result => {
  console.log(JSON.stringify(result, null, 2));
  if (result.status !== 'pass') process.exit(1);
}).catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
`
}

export default function RunnableCodeBlock({
  title,
  description,
  code,
  disabled = false,
  skippedReason,
  onResult,
}: RunnableCodeBlockProps) {
  const [result, setResult] = useState<StepOutput | null>(null)
  const [running, setRunning] = useState(false)
  const [copied, setCopied] = useState<string | null>(null)

  const highlighted = useMemo(() => highlightJs(code), [code])

  const handleRun = useCallback(async () => {
    setRunning(true)
    setResult(null)
    try {
      const output = await executeStep(code)
      setResult(output)
      onResult?.(output)
    } finally {
      setRunning(false)
    }
  }, [code, onResult])

  const handleCopy = useCallback((text: string, label: string) => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(label)
      setTimeout(() => setCopied(null), 1500)
    })
  }, [])

  if (skippedReason) {
    return (
      <section className="bg-gray-50 border border-gray-200 rounded-lg p-5 opacity-60">
        <h2 className="text-lg font-semibold text-gray-400">{title}</h2>
        <p className="text-sm text-gray-400 mt-1">{skippedReason}</p>
      </section>
    )
  }

  return (
    <section className="bg-white border border-gray-200 rounded-lg p-5 space-y-3">
      <h2 className="text-lg font-semibold">{title}</h2>
      {description && <div className="text-sm text-gray-700 space-y-2">{description}</div>}

      {/* Code block */}
      <div className="relative group">
        <pre className="bg-gray-50 border border-gray-200 rounded p-4 text-xs overflow-x-auto leading-relaxed max-h-96">
          <code dangerouslySetInnerHTML={{ __html: highlighted }} />
        </pre>
        <button
          onClick={() => handleCopy(code, 'code')}
          className="absolute top-2 right-2 px-1.5 py-0.5 text-xs text-gray-400 hover:text-gray-700 border border-gray-300 rounded hover:bg-gray-100 opacity-0 group-hover:opacity-100 transition-opacity"
        >
          {copied === 'code' ? 'Copied' : 'Copy'}
        </button>
      </div>

      {/* Action buttons */}
      <div className="flex items-center gap-2">
        <button
          onClick={handleRun}
          disabled={disabled || running}
          className="px-3 py-1.5 text-xs font-medium rounded border border-indigo-300 text-indigo-700 hover:bg-indigo-50 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {running ? 'Running...' : 'Run'}
        </button>
        <button
          onClick={() => handleCopy(buildStandaloneScript(title, code), 'standalone')}
          className="px-3 py-1.5 text-xs font-medium rounded border border-gray-300 text-gray-600 hover:bg-gray-50"
        >
          {copied === 'standalone' ? 'Copied!' : 'Copy standalone'}
        </button>
      </div>

      {/* Result */}
      {result && <StepResult result={result} />}
    </section>
  )
}
