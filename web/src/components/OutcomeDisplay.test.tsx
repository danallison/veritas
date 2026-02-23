import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import OutcomeDisplay from './OutcomeDisplay'

vi.mock('../api/client', () => ({
  api: {
    getOutcome: vi.fn(),
  },
}))

import { api } from '../api/client'

const mockGetOutcome = vi.mocked(api.getOutcome)

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  vi.restoreAllMocks()
})

function makeOutcome(outcome: unknown) {
  return {
    outcome,
    combined_entropy: 'aabbcc',
    resolved_at: '2026-01-15T12:00:00Z',
  }
}

describe('OutcomeDisplay', () => {
  it('shows loading state before fetch resolves', () => {
    mockGetOutcome.mockReturnValue(new Promise(() => {})) // never resolves
    render(<OutcomeDisplay ceremonyId="c1" ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }} />)
    expect(screen.getByText('Loading outcome...')).toBeDefined()
  })

  it('renders the winning label for CoinFlipResult', async () => {
    mockGetOutcome.mockResolvedValue(
      makeOutcome({ tag: 'CoinFlipResult', contents: 'Heads' })
    )
    render(<OutcomeDisplay ceremonyId="c1" ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }} />)
    await waitFor(() => expect(screen.getByText('Heads')).toBeDefined())
  })

  it('renders custom label for CoinFlipResult', async () => {
    mockGetOutcome.mockResolvedValue(
      makeOutcome({ tag: 'CoinFlipResult', contents: 'Alice wins' })
    )
    render(<OutcomeDisplay ceremonyId="c1" ceremonyType={{ tag: 'CoinFlip', contents: ['Alice wins', 'Bob wins'] }} />)
    await waitFor(() => expect(screen.getByText('Alice wins')).toBeDefined())
  })

  it('renders chosen item for ChoiceResult', async () => {
    mockGetOutcome.mockResolvedValue(
      makeOutcome({ tag: 'ChoiceResult', contents: 'Pizza' })
    )
    render(
      <OutcomeDisplay
        ceremonyId="c1"
        ceremonyType={{ tag: 'UniformChoice', contents: ['Pizza', 'Tacos'] }}
      />
    )
    await waitFor(() => expect(screen.getByText('Pizza')).toBeDefined())
  })

  it('renders ordered list for ShuffleResult', async () => {
    mockGetOutcome.mockResolvedValue(
      makeOutcome({ tag: 'ShuffleResult', contents: ['Alice', 'Bob', 'Carol'] })
    )
    render(
      <OutcomeDisplay
        ceremonyId="c1"
        ceremonyType={{ tag: 'Shuffle', contents: ['Alice', 'Bob', 'Carol'] }}
      />
    )
    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeDefined()
      expect(screen.getByText('Bob')).toBeDefined()
      expect(screen.getByText('Carol')).toBeDefined()
    })
  })

  it('renders number for IntRangeResult', async () => {
    mockGetOutcome.mockResolvedValue(
      makeOutcome({ tag: 'IntRangeResult', contents: 42 })
    )
    render(
      <OutcomeDisplay ceremonyId="c1" ceremonyType={{ tag: 'IntRange', contents: [1, 100] }} />
    )
    await waitFor(() => expect(screen.getByText('42')).toBeDefined())
  })

  it('shows error state when fetch fails', async () => {
    mockGetOutcome.mockRejectedValue(new Error('Network error'))
    render(<OutcomeDisplay ceremonyId="c1" ceremonyType={{ tag: 'CoinFlip', contents: ['Heads', 'Tails'] }} />)
    await waitFor(() => expect(screen.getByText('Network error')).toBeDefined())
  })
})
