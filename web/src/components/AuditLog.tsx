import { useEffect, useState } from 'react'
import { api } from '../api/client'
import type { AuditLogResponse, AuditLogEntryResponse, CommittedParticipant } from '../api/types'

function extractParticipantId(eventData: unknown): string | null {
  const data = eventData as Record<string, unknown>
  const commitment = data?.commitment as Record<string, unknown> | undefined
  if (commitment?.commitParty) return commitment.commitParty as string
  // entropy_revealed, non_participation events could have participant ids too
  if (data?.participantId) return data.participantId as string
  return null
}

function participantLabel(
  participantId: string,
  participants: CommittedParticipant[],
): string {
  const p = participants.find((p) => p.participant_id === participantId)
  if (p?.display_name) return p.display_name
  return participantId.slice(0, 8) + '...'
}

function eventDescription(
  entry: AuditLogEntryResponse,
  participants: CommittedParticipant[],
): string {
  const pid = extractParticipantId(entry.event_data)
  const who = pid ? participantLabel(pid, participants) : null

  switch (entry.event_type) {
    case 'ceremony_created':
      return 'Ceremony created'
    case 'participant_committed':
      return who ? `${who} committed` : 'Participant committed'
    case 'entropy_revealed':
      return who ? `${who} revealed entropy` : 'Entropy revealed'
    case 'reveals_published':
      return 'Reveals published'
    case 'non_participation_applied':
      return 'Non-participation policy applied'
    case 'beacon_anchored':
      return 'Beacon anchored'
    case 'vrf_generated':
      return 'Server randomness generated'
    case 'ceremony_resolved':
      return 'Outcome determined'
    case 'ceremony_finalized':
      return 'Ceremony finalized'
    case 'ceremony_expired':
      return 'Ceremony expired'
    case 'ceremony_cancelled':
      return 'Ceremony cancelled'
    case 'ceremony_disputed':
      return 'Ceremony disputed'
    default:
      return entry.event_type
  }
}

export default function AuditLog({
  ceremonyId,
  participants,
}: {
  ceremonyId: string
  participants: CommittedParticipant[]
}) {
  const [log, setLog] = useState<AuditLogResponse | null>(null)
  const [expanded, setExpanded] = useState(false)

  useEffect(() => {
    if (expanded && !log) {
      api.getAuditLog(ceremonyId).then(setLog)
    }
  }, [expanded, ceremonyId, log])

  return (
    <div className="border border-gray-200 rounded-lg">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full px-4 py-3 text-left text-sm font-medium text-gray-700 hover:bg-gray-50 flex justify-between items-center"
      >
        <span>Audit Log</span>
        <span className="text-gray-400">{expanded ? '\u25B2' : '\u25BC'}</span>
      </button>

      {expanded && (
        <div className="border-t border-gray-200 p-4">
          {log ? (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="text-left py-1 pr-2">#</th>
                    <th className="text-left py-1 pr-2">Event</th>
                    <th className="text-left py-1 pr-2">Hash</th>
                    <th className="text-left py-1">Time</th>
                  </tr>
                </thead>
                <tbody>
                  {log.entries.map((entry, i) => (
                    <tr key={entry.sequence_num} className="border-b border-gray-100">
                      <td className="py-1 pr-2 text-gray-400">{i + 1}</td>
                      <td className="py-1 pr-2">{eventDescription(entry, participants)}</td>
                      <td className="py-1 pr-2 font-mono text-gray-500" title={entry.entry_hash}>
                        {entry.entry_hash.slice(0, 12)}...
                      </td>
                      <td className="py-1 text-gray-500">
                        {new Date(entry.created_at).toLocaleTimeString()}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-sm text-gray-500">Loading...</p>
          )}
        </div>
      )}
    </div>
  )
}
