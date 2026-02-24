import { useState, useCallback, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { api } from '../api/client'
import type { CeremonyResponse, AuditLogEntryResponse } from '../api/types'
import type { StepOutput } from '../components/verification/executeStep'
import { extractVerificationData, unwrapOutcomeValue } from '../components/verification/auditLogParsing'
import type { CeremonyVerificationData } from '../components/verification/auditLogParsing'
import CeremonyInput, { isValidUuid } from '../components/verification/CeremonyInput'
import UtilitiesSection from '../components/verification/steps/UtilitiesSection'
import FetchDataStep from '../components/verification/steps/FetchDataStep'
import VerifyBeaconStep from '../components/verification/steps/VerifyBeaconStep'
import VerifyCommitRevealStep from '../components/verification/steps/VerifyCommitRevealStep'
import VerifyIdentityStep from '../components/verification/steps/VerifyIdentityStep'
import VerifyParamsHashStep from '../components/verification/steps/VerifyParamsHashStep'
import VerifyEntropyStep from '../components/verification/steps/VerifyEntropyStep'
import VerifyOutcomeStep from '../components/verification/steps/VerifyOutcomeStep'

export default function VerificationGuidePage() {
  const { ceremonyId: urlCeremonyId } = useParams<{ ceremonyId: string }>()
  const navigate = useNavigate()

  // Only accept URL param if it's a valid UUID — prevents injection via crafted URLs
  const safeUrlId = urlCeremonyId && isValidUuid(urlCeremonyId) ? urlCeremonyId : ''
  const [ceremonyId, setCeremonyId] = useState<string>(safeUrlId)
  const [ceremony, setCeremony] = useState<CeremonyResponse | null>(null)
  const [verificationData, setVerificationData] = useState<CeremonyVerificationData | null>(null)
  const [loading, setLoading] = useState(false)

  const baseUrl = window.location.origin

  // Auto-fetch ceremony data when we have a valid ID
  useEffect(() => {
    if (!ceremonyId) return
    let cancelled = false
    setLoading(true)
    setCeremony(null)
    setVerificationData(null)
    Promise.all([api.getCeremony(ceremonyId), api.getAuditLog(ceremonyId)])
      .then(([c, log]) => {
        if (cancelled) return
        setCeremony(c)
        setVerificationData(extractVerificationData(c, log.entries))
      })
      .catch(() => { /* step 1 will surface the error when run */ })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [ceremonyId])

  const handleLoad = useCallback((id: string) => {
    // CeremonyInput already validates, but defense-in-depth
    if (!isValidUuid(id)) return
    setCeremonyId(id)
    if (id !== urlCeremonyId) {
      navigate(`/verify/${id}`, { replace: true })
    }
  }, [navigate, urlCeremonyId])

  const handleFetchResult = useCallback((result: StepOutput) => {
    if (result.status === 'pass' && result.data) {
      const { ceremony: c, auditLog } = result.data as {
        ceremony: CeremonyResponse
        auditLog: { entries: AuditLogEntryResponse[] }
      }
      setCeremony(c)
      setVerificationData(extractVerificationData(c, auditLog.entries))
    }
  }, [])

  // Determine which steps are applicable — when not applicable, explain why
  const entropyMethod = ceremony?.entropy_method
  const identityMode = ceremony?.identity_mode

  const beaconSkipped = entropyMethod && entropyMethod !== 'ExternalBeacon' && entropyMethod !== 'Combined'
    ? `Not applicable — this ceremony uses ${entropyMethod} entropy (beacon verification applies to ExternalBeacon or Combined).`
    : undefined

  const commitRevealSkipped = entropyMethod && entropyMethod !== 'ParticipantReveal' && entropyMethod !== 'Combined'
    ? `Not applicable — this ceremony uses ${entropyMethod} entropy (commit-reveal verification applies to ParticipantReveal or Combined).`
    : undefined

  const identitySkipped = identityMode && identityMode !== 'SelfCertified'
    ? `Not applicable — this ceremony uses ${identityMode} identity mode (signature verification applies to SelfCertified).`
    : undefined

  // Unwrap outcome value for the outcome step
  const expectedOutcome = verificationData?.outcomeValue
    ? unwrapOutcomeValue(verificationData.outcomeValue)
    : undefined

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Interactive Verification Guide</h1>

      <div className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
        <p className="text-sm text-gray-700">
          Veritas produces cryptographically verifiable random outcomes. Every step from
          entropy collection to outcome derivation is deterministic and reproducible.
          This guide lets you <strong>independently verify</strong> any finalized ceremony
          by running the verification code directly in your browser or as standalone
          scripts in an environment that you control.
        </p>

        <CeremonyInput
          initialId={ceremonyId}
          onLoad={handleLoad}
          loading={loading}
        />

        {ceremony && (
          <div className="bg-gray-50 rounded p-3 text-xs space-y-1">
            <div className="flex items-center gap-3">
              <span className="text-gray-500">Question:</span>
              <span className="font-medium text-gray-800">{ceremony.question}</span>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-gray-500">Type:</span>
              <code className="font-mono text-gray-800">{ceremony.ceremony_type.tag}</code>
              <span className="text-gray-500">Entropy:</span>
              <code className="font-mono text-gray-800">{ceremony.entropy_method}</code>
              <span className="text-gray-500">Identity:</span>
              <code className="font-mono text-gray-800">{ceremony.identity_mode}</code>
            </div>
          </div>
        )}
      </div>

      <UtilitiesSection />

      <FetchDataStep
        ceremonyId={ceremonyId || null}
        baseUrl={baseUrl}
        onResult={handleFetchResult}
      />

      <VerifyBeaconStep
        beacon={verificationData?.beacon ?? null}
        skippedReason={beaconSkipped}
      />

      <VerifyCommitRevealStep
        ceremonyId={ceremony?.id ?? null}
        commitReveals={verificationData?.commitReveals ?? null}
        skippedReason={commitRevealSkipped}
      />

      <VerifyIdentityStep
        ceremonyId={ceremony?.id ?? null}
        paramsHash={ceremony?.params_hash ?? null}
        roster={verificationData?.roster ?? null}
        ackSignatures={verificationData?.ackSignatures ?? null}
        commitSignatures={verificationData?.commitSignatures ?? null}
        skippedReason={identitySkipped}
      />

      <VerifyParamsHashStep ceremony={ceremony} />

      <VerifyEntropyStep
        entropyInputs={verificationData?.entropyInputs ?? null}
        combinedEntropy={verificationData?.combinedEntropy ?? null}
      />

      <VerifyOutcomeStep
        ceremonyType={ceremony?.ceremony_type ?? null}
        combinedEntropy={verificationData?.combinedEntropy ?? null}
        expectedOutcome={expectedOutcome}
      />
    </div>
  )
}
