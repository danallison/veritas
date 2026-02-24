import RunnableCodeBlock from '../RunnableCodeBlock'
import { fetchDataCode, FETCH_DATA_PLACEHOLDER } from '../codeStrings'
import type { StepOutput } from '../executeStep'

interface FetchDataStepProps {
  ceremonyId: string | null
  baseUrl: string
  onResult: (result: StepOutput) => void
}

export default function FetchDataStep({ ceremonyId, baseUrl, onResult }: FetchDataStepProps) {
  const code = ceremonyId
    ? fetchDataCode(ceremonyId, baseUrl)
    : FETCH_DATA_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 1: Fetch ceremony data"
      description={
        <p>
          Fetch the ceremony details and its complete audit log. The audit log contains
          all events from creation through finalization, including the outcome proof.
        </p>
      }
      code={code}
      disabled={!ceremonyId}
      onResult={onResult}
    />
  )
}
