import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, cleanup } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import VerificationData from './VerificationData'

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
  cleanup()
  vi.restoreAllMocks()
})

function wrap(ui: React.ReactElement) {
  return <MemoryRouter>{ui}</MemoryRouter>
}

const beaconAnchoredEntry = {
  sequence_num: 3,
  event_type: 'beacon_anchored',
  event_data: {
    tag: 'BeaconAnchored',
    anchor: {
      baNetwork: 'dbd506d6ef76e5f386f41c651dcb808c5bcbd75471cc4eafa3f4df7ad4e4c493',
      baRound: 12345,
      baValue: 'aabbccdd',
      baSignature: '11223344',
      baFetchedAt: '2026-01-15T12:00:00Z',
    },
  },
  prev_hash: 'prev2',
  entry_hash: 'hash3',
  created_at: '2026-01-15T12:00:00Z',
}

const resolvedEntry = {
  sequence_num: 4,
  event_type: 'ceremony_resolved',
  event_data: {
    tag: 'CeremonyResolved',
    outcome: {
      outcomeValue: { tag: 'CoinFlipResult', contents: 'Heads' },
      combinedEntropy: 'deadbeef01234567',
      outcomeProof: {
        proofEntropyInputs: [
          {
            ecCeremony: 'c1',
            ecSource: { tag: 'ParticipantEntropy', participant: 'p1-uuid-1234' },
            ecValue: 'aa11bb22',
          },
          {
            ecCeremony: 'c1',
            ecSource: {
              tag: 'BeaconEntropy',
              anchor: {
                baNetwork: 'dbd506d6ef76e5f386f41c651dcb808c5bcbd75471cc4eafa3f4df7ad4e4c493',
                baRound: 12345,
                baValue: 'aabbccdd',
                baSignature: '11223344',
                baFetchedAt: '2026-01-15T12:00:00Z',
              },
            },
            ecValue: 'ccddee00',
          },
        ],
        proofDerivation: 'Concatenation in canonical order, SHA-256 hash, HKDF-SHA256 derivation',
      },
    },
  },
  prev_hash: 'prev3',
  entry_hash: 'hash4',
  created_at: '2026-01-15T12:00:01Z',
}

describe('VerificationData', () => {
  it('renders nothing while loading', () => {
    mockGetAuditLog.mockReturnValue(new Promise(() => {}))
    const { container } = render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    expect(container.innerHTML).toBe('')
  })

  it('renders nothing when no ceremony_resolved event exists', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [
        {
          sequence_num: 1,
          event_type: 'ceremony_created',
          event_data: { tag: 'CeremonyCreated' },
          prev_hash: '',
          entry_hash: 'hash1',
          created_at: '2026-01-15T12:00:00Z',
        },
      ],
    })
    const { container } = render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => expect(container.querySelector('.space-y-5')).toBeNull())
  })

  it('shows beacon section for Combined entropy method', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [beaconAnchoredEntry, resolvedEntry],
    })
    const { container } = render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => expect(screen.getByText('12345')).toBeDefined())
    // Beacon section heading exists
    const h4s = container.querySelectorAll('h4')
    const beaconHeading = Array.from(h4s).find((h) => h.textContent === 'Beacon')
    expect(beaconHeading).toBeDefined()
    expect(screen.getByText('aabbccdd')).toBeDefined()
  })

  it('hides beacon section for ParticipantReveal method', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [resolvedEntry],
    })
    const { container } = render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="ParticipantReveal"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => expect(screen.getByText('Entropy Inputs')).toBeDefined())
    // No Beacon heading (though "Beacon" may appear as a source type in the table)
    const h4s = container.querySelectorAll('h4')
    const beaconHeading = Array.from(h4s).find((h) => h.textContent === 'Beacon')
    expect(beaconHeading).toBeUndefined()
  })

  it('shows entropy inputs from audit log', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [beaconAnchoredEntry, resolvedEntry],
    })
    render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => expect(screen.getByText('aa11bb22')).toBeDefined())
    expect(screen.getByText('ccddee00')).toBeDefined()
    expect(screen.getByText('Participant')).toBeDefined()
  })

  it('shows combined entropy and outcome', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [resolvedEntry],
    })
    render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => expect(screen.getByText('deadbeef01234567')).toBeDefined())
    expect(screen.getByText('Heads')).toBeDefined()
  })

  it('builds correct curl command with chain hash and round', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [beaconAnchoredEntry, resolvedEntry],
    })
    render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    const expected = 'curl -s https://api.drand.sh/dbd506d6ef76e5f386f41c651dcb808c5bcbd75471cc4eafa3f4df7ad4e4c493/public/12345 | jq'
    await waitFor(() => expect(screen.getByText(expected)).toBeDefined())
  })

  it('shows link to verification guide', async () => {
    mockGetAuditLog.mockResolvedValue({
      entries: [resolvedEntry],
    })
    render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => {
      expect(screen.getByText('step-by-step verification guide')).toBeDefined()
    })
  })

  it('handles fetch errors', async () => {
    mockGetAuditLog.mockRejectedValue(new Error('Network error'))
    render(
      wrap(
        <VerificationData
          ceremonyId="c1"
          entropyMethod="Combined"
          ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }}
        />,
      ),
    )
    await waitFor(() => expect(screen.getByText('Network error')).toBeDefined())
  })
})
