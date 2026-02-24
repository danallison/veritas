import { useMemo } from 'react'
import RunnableCodeBlock from '../RunnableCodeBlock'
import { UTILITY_CODE, UTILITY_SELF_TEST } from '../codeStrings'

export default function UtilitiesSection() {
  const combined = useMemo(
    () =>
      '// These utility functions use the crypto.subtle Web Crypto API (browsers and Node.js 20+).\n\n' +
      UTILITY_CODE +
      '\n\n// --- Self-Test ---\n' +
      '// Verify the utility functions work in your environment.\n\n' +
      UTILITY_SELF_TEST,
    [],
  )

  return (
    <RunnableCodeBlock
      title="Utility functions"
      description={
        <p>
          These helper functions are used by all verification steps below.
          Click "Run" to verify they work in your environment.
        </p>
      }
      code={combined}
    />
  )
}
