import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, fireEvent, waitFor } from '@testing-library/react'
import { within } from '@testing-library/dom'
import AuditLog, { eventDescription, participantLabel } from './AuditLog'
import type { AuditLogEntryResponse, CommittedParticipant } from '../api/types'

vi.mock('../api/client', () => ({
  api: {
    getAuditLog: vi.fn(),
  },
}))

import { api } from '../api/client'

const mockGetAuditLog = vi.mocked(api.getAuditLog)

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  vi.restoreAllMocks()
})

const participants: CommittedParticipant[] = [
  { participant_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', display_name: 'Alice' },
  { participant_id: '11111111-2222-3333-4444-555555555555', display_name: null },
]

function makeEntry(event_type: string, event_data: unknown = {}): AuditLogEntryResponse {
  return {
    sequence_num: 0,
    event_type,
    event_data,
    prev_hash: '0000',
    entry_hash: 'abcd1234abcd1234',
    created_at: '2026-01-15T12:00:00Z',
  }
}

describe('participantLabel', () => {
  it('returns display name when available', () => {
    expect(participantLabel('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', participants))
      .toBe('Alice')
  })

  it('returns truncated UUID when no display name', () => {
    expect(participantLabel('11111111-2222-3333-4444-555555555555', participants))
      .toBe('11111111...')
  })

  it('returns truncated UUID for unknown participant', () => {
    expect(participantLabel('99999999-0000-0000-0000-000000000000', participants))
      .toBe('99999999...')
  })
})

describe('eventDescription', () => {
  const allEventTypes: [string, string][] = [
    ['ceremony_created', 'Ceremony created'],
    ['reveals_published', 'Reveals published'],
    ['non_participation_applied', 'Non-participation policy applied'],
    ['beacon_anchored', 'Beacon anchored'],
    ['vrf_generated', 'Server randomness generated'],
    ['ceremony_resolved', 'Outcome determined'],
    ['ceremony_finalized', 'Ceremony finalized'],
    ['ceremony_expired', 'Ceremony expired'],
    ['ceremony_cancelled', 'Ceremony cancelled'],
    ['ceremony_disputed', 'Ceremony disputed'],
  ]

  for (const [eventType, expected] of allEventTypes) {
    it(`maps "${eventType}" to "${expected}"`, () => {
      expect(eventDescription(makeEntry(eventType), [])).toBe(expected)
    })
  }

  it('includes participant name for participant_committed', () => {
    const entry = makeEntry('participant_committed', {
      commitment: { commitParty: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' },
    })
    expect(eventDescription(entry, participants)).toBe('Alice committed')
  })

  it('includes participant name for entropy_revealed', () => {
    const entry = makeEntry('entropy_revealed', {
      participantId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    })
    expect(eventDescription(entry, participants)).toBe('Alice revealed entropy')
  })

  it('falls back to raw event_type for unknown types', () => {
    expect(eventDescription(makeEntry('some_future_event'), [])).toBe('some_future_event')
  })
})

describe('AuditLog component', () => {
  it('starts collapsed', () => {
    const { container } = render(<AuditLog ceremonyId="c1" participants={[]} phase="Pending" />)
    expect(container.querySelector('table')).toBeNull()
  })

  it('expands on click and fetches log', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [
        makeEntry('ceremony_created'),
        makeEntry('ceremony_finalized'),
      ],
    })

    const { container } = render(<AuditLog ceremonyId="c1" participants={[]} phase="Finalized" />)
    fireEvent.click(within(container).getByText('Audit Log'))

    await waitFor(() => {
      expect(mockGetAuditLog).toHaveBeenCalledWith('c1')
      expect(within(container).getByText('Ceremony created')).toBeDefined()
      expect(within(container).getByText('Ceremony finalized')).toBeDefined()
    })
  })
})
