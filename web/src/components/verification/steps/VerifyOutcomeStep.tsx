import RunnableCodeBlock from '../RunnableCodeBlock'
import { verifyOutcomeCode, VERIFY_OUTCOME_PLACEHOLDER } from '../codeStrings'

interface VerifyOutcomeStepProps {
  ceremonyType: { tag: string; contents?: unknown } | null
  combinedEntropy: string | null
  expectedOutcome: unknown
}

export default function VerifyOutcomeStep({
  ceremonyType,
  combinedEntropy,
  expectedOutcome,
}: VerifyOutcomeStepProps) {
  const hasData = ceremonyType && combinedEntropy && expectedOutcome !== undefined
  const code = hasData
    ? verifyOutcomeCode(ceremonyType, combinedEntropy, expectedOutcome)
    : VERIFY_OUTCOME_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 7: Verify outcome derivation"
      description={
        <>
          <p>
            The combined entropy is passed through HKDF-SHA256 to derive a uniform random value,
            then used to determine the outcome based on the ceremony type (coin flip, choice,
            shuffle, etc.).
          </p>
        </>
      }
      code={code}
      disabled={!hasData}
    />
  )
}
