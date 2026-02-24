import RunnableCodeBlock from '../RunnableCodeBlock'
import { verifyCommitRevealCode, VERIFY_COMMIT_REVEAL_PLACEHOLDER } from '../codeStrings'
import type { CommitRevealEntry } from '../auditLogParsing'

interface VerifyCommitRevealStepProps {
  ceremonyId: string | null
  commitReveals: CommitRevealEntry[] | null
  skippedReason?: string
}

export default function VerifyCommitRevealStep({ ceremonyId, commitReveals, skippedReason }: VerifyCommitRevealStepProps) {
  const hasData = ceremonyId && commitReveals && commitReveals.length > 0
  const code = hasData
    ? verifyCommitRevealCode(ceremonyId, commitReveals)
    : VERIFY_COMMIT_REVEAL_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 3: Verify commit-reveal integrity"
      description={
        <>
          <p>
            Each participant committed a seal <em>before</em> any entropy was revealed.
            Verify that each revealed entropy value matches its commitment:
          </p>
          <p className="text-xs font-mono text-gray-600 bg-gray-50 rounded px-2 py-1">
            seal = SHA-256(ceremony_id_ascii || participant_id_ascii || entropy_bytes)
          </p>
          <p className="text-xs text-gray-500">
            Applies to <strong>ParticipantReveal</strong> or <strong>Combined</strong> entropy.
          </p>
        </>
      }
      code={code}
      disabled={!hasData}
      skippedReason={skippedReason}
    />
  )
}
