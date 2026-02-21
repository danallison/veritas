import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { within } from '@testing-library/dom'
import PhaseIndicator from './PhaseIndicator'
import type { Phase } from '../api/types'

describe('PhaseIndicator', () => {
  it('renders 4 step indicators for Pending phase', () => {
    const { container } = render(<PhaseIndicator phase="Pending" />)
    const steps = container.querySelectorAll('.rounded-full')
    expect(steps.length).toBe(4)
  })

  it('highlights step 1 as active for Pending', () => {
    const { container } = render(<PhaseIndicator phase="Pending" />)
    const steps = container.querySelectorAll('.rounded-full')
    expect(steps[0].className).toContain('ring-2')
  })

  it('highlights step 2 as active for AwaitingReveals', () => {
    const { container } = render(<PhaseIndicator phase="AwaitingReveals" />)
    const steps = container.querySelectorAll('.rounded-full')
    expect(steps[0].className).toContain('bg-indigo-600')
    expect(steps[1].className).toContain('ring-2')
  })

  it('maps AwaitingBeacon to same step index as AwaitingReveals', () => {
    const { container: c1 } = render(<PhaseIndicator phase="AwaitingBeacon" />)
    const { container: c2 } = render(<PhaseIndicator phase="AwaitingReveals" />)
    const steps1 = c1.querySelectorAll('.rounded-full')
    const steps2 = c2.querySelectorAll('.rounded-full')
    expect(steps1[1].className).toContain('ring-2')
    expect(steps2[1].className).toContain('ring-2')
  })

  it('shows all steps done except last for Resolving', () => {
    const { container } = render(<PhaseIndicator phase="Resolving" />)
    const steps = container.querySelectorAll('.rounded-full')
    expect(steps[0].className).toContain('bg-indigo-600')
    expect(steps[1].className).toContain('bg-indigo-600')
    expect(steps[2].className).toContain('ring-2')
  })

  it('renders red terminal badge for Expired', () => {
    const { container } = render(<PhaseIndicator phase="Expired" />)
    const badge = within(container).getByText('Expired')
    expect(badge.className).toContain('bg-red-100')
  })

  it('renders red terminal badge for Cancelled', () => {
    const { container } = render(<PhaseIndicator phase="Cancelled" />)
    const badge = within(container).getByText('Cancelled')
    expect(badge.className).toContain('bg-red-100')
  })

  it('renders red terminal badge for Disputed', () => {
    const { container } = render(<PhaseIndicator phase="Disputed" />)
    const badge = within(container).getByText('Disputed')
    expect(badge.className).toContain('bg-red-100')
  })

  it('shows correct label text for each phase', () => {
    const labels: Record<Phase, string> = {
      Pending: 'Commitments',
      AwaitingReveals: 'Reveals',
      AwaitingBeacon: 'Beacon',
      Resolving: 'Determining outcome',
      Finalized: 'Done',
      Expired: 'Expired',
      Cancelled: 'Cancelled',
      Disputed: 'Disputed',
    }
    for (const [phase, label] of Object.entries(labels)) {
      const { container, unmount } = render(<PhaseIndicator phase={phase as Phase} />)
      expect(within(container).getByText(label)).toBeDefined()
      unmount()
    }
  })
})
