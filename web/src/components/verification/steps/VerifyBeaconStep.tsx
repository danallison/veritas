import RunnableCodeBlock from '../RunnableCodeBlock'
import { verifyBeaconCode, VERIFY_BEACON_PLACEHOLDER } from '../codeStrings'
import type { BeaconData } from '../auditLogParsing'

interface VerifyBeaconStepProps {
  beacon: BeaconData | null
  skippedReason?: string
}

export default function VerifyBeaconStep({ beacon, skippedReason }: VerifyBeaconStepProps) {
  const code = beacon
    ? verifyBeaconCode(beacon.network, beacon.round, beacon.value, beacon.signature)
    : VERIFY_BEACON_PLACEHOLDER

  return (
    <RunnableCodeBlock
      title="Step 2: Verify the drand beacon"
      description={
        <>
          <p>
            Fetch the same beacon round directly from the drand network and compare
            the randomness and signature values. This proves the beacon data is real
            drand output, not fabricated.
          </p>
          <p className="text-xs text-gray-500">
            Applies to ceremonies using <strong>ExternalBeacon</strong> or <strong>Combined</strong> entropy.
          </p>
        </>
      }
      code={code}
      disabled={!beacon}
      skippedReason={skippedReason}
    />
  )
}
