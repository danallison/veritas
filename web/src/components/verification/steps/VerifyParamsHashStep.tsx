import RunnableCodeBlock from '../RunnableCodeBlock'
import { verifyParamsHashCode, VERIFY_PARAMS_HASH_PLACEHOLDER } from '../codeStrings'
import type { CeremonyResponse } from '../../../api/types'

interface VerifyParamsHashStepProps {
  ceremony: CeremonyResponse | null
}

export default function VerifyParamsHashStep({ ceremony }: VerifyParamsHashStepProps) {
  const code = ceremony
    ? verifyParamsHashCode(ceremony as unknown as Record<string, unknown>)
    : VERIFY_PARAMS_HASH_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 5: Verify ceremony parameters hash"
      description={
        <>
          <p>
            The <code className="text-xs bg-gray-100 px-1 rounded">params_hash</code> binds
            participant signatures to the exact ceremony configuration (question, outcome type,
            entropy method, deadlines, etc.). Reconstruct the canonical binary serialization
            and verify the hash.
          </p>
        </>
      }
      code={code}
      disabled={!ceremony}
    />
  )
}
