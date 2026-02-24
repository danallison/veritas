import RunnableCodeBlock from '../RunnableCodeBlock'
import { verifyEntropyCode, VERIFY_ENTROPY_PLACEHOLDER } from '../codeStrings'
import type { EntropyInputEntry } from '../auditLogParsing'

interface VerifyEntropyStepProps {
  entropyInputs: EntropyInputEntry[] | null
  combinedEntropy: string | null
}

export default function VerifyEntropyStep({ entropyInputs, combinedEntropy }: VerifyEntropyStepProps) {
  const hasData = entropyInputs && entropyInputs.length > 0 && combinedEntropy
  const code = hasData
    ? verifyEntropyCode(entropyInputs, combinedEntropy)
    : VERIFY_ENTROPY_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 6: Verify entropy combination"
      description={
        <>
          <p>
            All entropy contributions are combined deterministically. Sort by canonical
            priority (Participant &gt; Default &gt; Beacon &gt; VRF), concatenate raw bytes,
            and SHA-256 hash.
          </p>
        </>
      }
      code={code}
      disabled={!hasData}
    />
  )
}
