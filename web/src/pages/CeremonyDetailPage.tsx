import { useParams } from 'react-router-dom'
import { useCeremony } from '../hooks/useCeremony'
import PhaseIndicator from '../components/PhaseIndicator'
import CopyLinkButton from '../components/CopyLinkButton'
import CommitForm from '../components/CommitForm'
import RevealForm from '../components/RevealForm'
import OutcomeDisplay from '../components/OutcomeDisplay'
import AuditLog from '../components/AuditLog'
import type { EntropyMethod } from '../api/types'

const METHOD_LABELS: Record<EntropyMethod, string> = {
  OfficiantVRF: 'Server generated',
  ExternalBeacon: 'External beacon',
  ParticipantReveal: 'Participant reveal',
  Combined: 'Combined',
}

export default function CeremonyDetailPage() {
  const { id } = useParams<{ id: string }>()
  const { ceremony, error, loading, refetch } = useCeremony(id)

  if (loading) return <p className="text-gray-500">Loading ceremony...</p>
  if (error) return <p className="text-red-600">{error}</p>
  if (!ceremony || !id) return <p className="text-red-600">Ceremony not found</p>

  const typeLabel = ceremony.ceremony_type.tag

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold">{ceremony.question}</h1>
          <p className="text-sm text-gray-500 mt-1">
            {typeLabel} &middot; {METHOD_LABELS[ceremony.entropy_method]} &middot;{' '}
            {ceremony.commitment_count}/{ceremony.required_parties} committed
          </p>
        </div>
        <CopyLinkButton ceremonyId={id} />
      </div>

      <PhaseIndicator phase={ceremony.phase} />

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          <Dt>ID</Dt>
          <Dd><code className="text-xs break-all">{ceremony.id}</code></Dd>
          <Dt>Commitment Mode</Dt>
          <Dd>{ceremony.commitment_mode}</Dd>
          <Dt>Commit Deadline</Dt>
          <Dd>{new Date(ceremony.commit_deadline).toLocaleString()}</Dd>
          {ceremony.reveal_deadline && (
            <>
              <Dt>Reveal Deadline</Dt>
              <Dd>{new Date(ceremony.reveal_deadline).toLocaleString()}</Dd>
            </>
          )}
          {ceremony.non_participation_policy && (
            <>
              <Dt>Non-participation</Dt>
              <Dd>{ceremony.non_participation_policy}</Dd>
            </>
          )}
        </dl>
      </div>

      {(ceremony.committed_participants ?? []).length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <h3 className="font-semibold mb-2">
            Participants ({ceremony.commitment_count}/{ceremony.required_parties})
          </h3>
          <ul className="space-y-1 text-sm">
            {ceremony.committed_participants.map((p) => (
              <li key={p.participant_id} className="text-gray-700">
                {p.display_name || `Anonymous (${p.participant_id.slice(0, 8)}...)`}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Phase-appropriate action */}
      {ceremony.phase === 'Pending' && (
        <CommitForm
          ceremonyId={id}
          entropyMethod={ceremony.entropy_method}
          onCommitted={refetch}
        />
      )}

      {ceremony.phase === 'AwaitingReveals' && (
        <RevealForm ceremonyId={id} onRevealed={refetch} />
      )}

      {ceremony.phase === 'AwaitingBeacon' && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
          <p className="text-yellow-800 text-sm">
            Waiting for external beacon value...
          </p>
        </div>
      )}

      {ceremony.phase === 'Finalized' && (
        <OutcomeDisplay ceremonyId={id} ceremonyType={ceremony.ceremony_type} />
      )}

      {(ceremony.phase === 'Expired' || ceremony.phase === 'Cancelled' || ceremony.phase === 'Disputed') && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <p className="text-red-800 text-sm">
            This ceremony has been {ceremony.phase.toLowerCase()}.
          </p>
        </div>
      )}

      <AuditLog ceremonyId={id} participants={ceremony.committed_participants ?? []} />
    </div>
  )
}

function Dt({ children }: { children: React.ReactNode }) {
  return <dt className="text-gray-500">{children}</dt>
}

function Dd({ children }: { children: React.ReactNode }) {
  return <dd className="text-gray-900">{children}</dd>
}
