import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../api/client'
import type { AuditLogResponse, AuditLogEntryResponse, EntropyMethod, CeremonyType, IdentityMode } from '../api/types'

interface BeaconData {
  network: string
  round: number
  value: string
  signature: string
}

interface EntropyInput {
  sourceType: string
  sourceLabel: string
  value: string
}

interface VerificationInfo {
  beacon: BeaconData | null
  entropyInputs: EntropyInput[]
  combinedEntropy: string
  outcomeValue: unknown
}

function extractBeaconData(entries: AuditLogEntryResponse[]): BeaconData | null {
  const event = entries.find((e) => e.event_type === 'beacon_anchored')
  if (!event) return null
  const data = event.event_data as Record<string, unknown>
  const anchor = data?.anchor as Record<string, unknown> | undefined
  if (!anchor) return null
  return {
    network: anchor.baNetwork as string,
    round: anchor.baRound as number,
    value: anchor.baValue as string,
    signature: anchor.baSignature as string,
  }
}

function extractVerificationInfo(
  entries: AuditLogEntryResponse[],
  entropyMethod: EntropyMethod,
): VerificationInfo | null {
  const resolvedEvent = entries.find((e) => e.event_type === 'ceremony_resolved')
  if (!resolvedEvent) return null

  const data = resolvedEvent.event_data as Record<string, unknown>
  const outcome = data?.outcome as Record<string, unknown> | undefined
  if (!outcome) return null

  const proof = outcome.outcomeProof as Record<string, unknown> | undefined
  const inputs = (proof?.proofEntropyInputs ?? []) as Array<Record<string, unknown>>

  const entropyInputs: EntropyInput[] = inputs.map((input) => {
    const source = input.ecSource as Record<string, unknown>
    const tag = source?.tag as string
    let sourceType = tag
    let sourceLabel = ''

    switch (tag) {
      case 'ParticipantEntropy':
        sourceType = 'Participant'
        sourceLabel = source.participant as string
        break
      case 'DefaultEntropy':
        sourceType = 'Default'
        sourceLabel = source.participant as string
        break
      case 'BeaconEntropy':
        sourceType = 'Beacon'
        sourceLabel = 'drand'
        break
      case 'VRFEntropy':
        sourceType = 'VRF'
        sourceLabel = 'server'
        break
    }

    return {
      sourceType,
      sourceLabel,
      value: input.ecValue as string,
    }
  })

  const beacon = (entropyMethod === 'ExternalBeacon' || entropyMethod === 'Combined')
    ? extractBeaconData(entries)
    : null

  return {
    beacon,
    entropyInputs,
    combinedEntropy: outcome.combinedEntropy as string,
    outcomeValue: outcome.outcomeValue,
  }
}

interface RosterParticipant {
  participantId: string
  publicKey: string
  rosterSignature: string | null
}

function extractIdentityData(entries: AuditLogEntryResponse[]): RosterParticipant[] | null {
  const rosterEvent = entries.find((e) => e.event_type === 'roster_finalized')
  if (!rosterEvent) return null

  const data = rosterEvent.event_data as Record<string, unknown>
  const contents = data?.contents as [string, string][] | undefined
  if (!contents) return null

  // Build a map of participant_id → roster_signature from roster_acknowledged events
  const ackMap = new Map<string, string>()
  for (const entry of entries) {
    if (entry.event_type === 'roster_acknowledged') {
      const ackData = entry.event_data as Record<string, unknown>
      const pid = ackData?.participant as string
      const sig = ackData?.signature as string
      if (pid && sig) ackMap.set(pid, sig)
    }
  }

  return contents.map(([pid, pk]) => ({
    participantId: pid,
    publicKey: pk,
    rosterSignature: ackMap.get(pid) ?? null,
  }))
}

function formatOutcome(value: unknown, ceremonyType: CeremonyType): string {
  const v = value as Record<string, unknown>
  const tag = v?.tag as string
  const contents = v?.contents

  switch (tag) {
    case 'CoinFlipResult':
      return String(contents)
    case 'ChoiceResult':
    case 'WeightedChoiceResult':
      return String(contents)
    case 'ShuffleResult':
      return (contents as string[]).join(', ')
    case 'IntRangeResult':
      return String(contents)
    default:
      return JSON.stringify(value)
  }
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)

  const handleCopy = () => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <button
      onClick={handleCopy}
      className="ml-2 px-1.5 py-0.5 text-xs text-gray-500 hover:text-gray-700 border border-gray-300 rounded hover:bg-gray-100"
      title="Copy to clipboard"
    >
      {copied ? 'Copied' : 'Copy'}
    </button>
  )
}

function HexValue({ value, label }: { value: string; label?: string }) {
  return (
    <div className="flex items-start gap-2">
      {label && <span className="text-gray-500 text-xs shrink-0 pt-0.5">{label}:</span>}
      <code className="font-mono text-xs break-all text-gray-800 flex-1">{value}</code>
      <CopyButton text={value} />
    </div>
  )
}

export default function VerificationData({
  ceremonyId,
  entropyMethod,
  ceremonyType,
  identityMode = 'Anonymous',
}: {
  ceremonyId: string
  entropyMethod: EntropyMethod
  ceremonyType: CeremonyType
  identityMode?: IdentityMode
}) {
  const [log, setLog] = useState<AuditLogResponse | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api.getAuditLog(ceremonyId).then(setLog).catch((e) => setError(e.message))
  }, [ceremonyId])

  if (error) return <p className="text-red-600 text-sm">{error}</p>
  if (!log) return null

  const info = extractVerificationInfo(log.entries, entropyMethod)
  if (!info) return null

  const identityData = identityMode === 'SelfCertified'
    ? extractIdentityData(log.entries)
    : null

  const curlCommand = info.beacon
    ? `curl -s https://api.drand.sh/${info.beacon.network}/public/${info.beacon.round} | jq`
    : null

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-5 space-y-5">
      <h3 className="font-semibold text-gray-900">Verification Data</h3>

      {info.beacon && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium text-gray-700">Beacon</h4>
          <div className="space-y-1.5 bg-gray-50 rounded p-3">
            <div className="flex items-center gap-2 text-xs">
              <span className="text-gray-500">Round:</span>
              <span className="font-mono text-gray-800">{info.beacon.round}</span>
            </div>
            <div className="flex items-center gap-2 text-xs">
              <span className="text-gray-500">Network:</span>
              <code className="font-mono text-gray-800 break-all">{info.beacon.network}</code>
            </div>
            <HexValue value={info.beacon.value} label="Value" />
            <HexValue value={info.beacon.signature} label="Signature" />
          </div>
          {curlCommand && (
            <div className="space-y-1">
              <p className="text-xs text-gray-500">
                Fetch this round directly from drand and compare:
              </p>
              <div className="flex items-start gap-2 bg-gray-50 rounded p-2">
                <code className="font-mono text-xs break-all text-gray-800 flex-1">
                  {curlCommand}
                </code>
                <CopyButton text={curlCommand} />
              </div>
            </div>
          )}
        </div>
      )}

      {identityData && identityData.length > 0 && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium text-gray-700">Participant Identity (Self-Certified)</h4>
          <p className="text-xs text-gray-500">
            Each participant registered a public key, signed the roster, and signed their
            commitment. This constitutes non-repudiable proof of participation — denying
            involvement requires claiming private key compromise.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-gray-200">
                  <th className="text-left py-1.5 pr-3">Participant</th>
                  <th className="text-left py-1.5 pr-3">Public Key</th>
                  <th className="text-left py-1.5">Roster Signature</th>
                </tr>
              </thead>
              <tbody>
                {identityData.map((p) => (
                  <tr key={p.participantId} className="border-b border-gray-100">
                    <td className="py-1.5 pr-3 font-mono text-gray-600">
                      {p.participantId.slice(0, 8)}...
                    </td>
                    <td className="py-1.5 pr-3">
                      <div className="flex items-center gap-1">
                        <code className="font-mono break-all text-gray-800">
                          {p.publicKey.slice(0, 16)}...
                        </code>
                        <CopyButton text={p.publicKey} />
                      </div>
                    </td>
                    <td className="py-1.5">
                      {p.rosterSignature ? (
                        <div className="flex items-center gap-1">
                          <code className="font-mono break-all text-gray-800">
                            {p.rosterSignature.slice(0, 16)}...
                          </code>
                          <CopyButton text={p.rosterSignature} />
                        </div>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="space-y-2">
        <h4 className="text-sm font-medium text-gray-700">Entropy Inputs</h4>
        <p className="text-xs text-gray-500">
          Listed as reported. Canonical combination order is determined by
          source type priority and participant ID (see verification guide).
        </p>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="text-left py-1.5 pr-3">Source</th>
                <th className="text-left py-1.5 pr-3">ID</th>
                <th className="text-left py-1.5">Value</th>
              </tr>
            </thead>
            <tbody>
              {info.entropyInputs.map((input, i) => (
                <tr key={i} className="border-b border-gray-100">
                  <td className="py-1.5 pr-3 text-gray-600">{input.sourceType}</td>
                  <td className="py-1.5 pr-3 font-mono text-gray-600">
                    {input.sourceLabel.length > 12
                      ? input.sourceLabel.slice(0, 8) + '...'
                      : input.sourceLabel}
                  </td>
                  <td className="py-1.5">
                    <div className="flex items-center gap-1">
                      <code className="font-mono break-all text-gray-800">{input.value}</code>
                      <CopyButton text={input.value} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="space-y-1.5">
        <h4 className="text-sm font-medium text-gray-700">Combined Entropy</h4>
        <HexValue value={info.combinedEntropy} />
      </div>

      <div className="space-y-1.5">
        <h4 className="text-sm font-medium text-gray-700">Reported Outcome</h4>
        <code className="font-mono text-sm text-gray-900">
          {formatOutcome(info.outcomeValue, ceremonyType)}
        </code>
      </div>

      <p className="text-xs text-gray-500">
        To independently reproduce this outcome, follow the{' '}
        <Link to={`/verify/${ceremonyId}`} className="text-indigo-600 hover:underline">
          step-by-step verification guide
        </Link>.
      </p>
    </div>
  )
}
