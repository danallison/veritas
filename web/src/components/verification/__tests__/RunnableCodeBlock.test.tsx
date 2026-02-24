// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import RunnableCodeBlock from '../RunnableCodeBlock'

// Mock crypto.subtle for jsdom (doesn't have it natively)
beforeEach(() => {
  cleanup()
  if (!globalThis.crypto?.subtle) {
    Object.defineProperty(globalThis, 'crypto', {
      value: {
        subtle: {
          digest: vi.fn().mockResolvedValue(new ArrayBuffer(32)),
          importKey: vi.fn().mockResolvedValue({}),
          deriveBits: vi.fn().mockResolvedValue(new ArrayBuffer(32)),
        },
        getRandomValues: vi.fn((arr: Uint8Array) => arr),
      },
      writable: true,
    })
  }
})

describe('RunnableCodeBlock', () => {
  it('renders the title and code', () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'ok' };"
      />,
    )
    expect(screen.getByText('Test Step')).toBeTruthy()
    // Code is syntax-highlighted into <span> tokens, so check the <code> element's text content
    const codeEl = document.querySelector('pre code')
    expect(codeEl?.textContent).toContain("return { status: 'pass', summary: 'ok' };")
  })

  it('renders the description when provided', () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'ok' };"
        description={<p>Some description</p>}
      />,
    )
    expect(screen.getByText('Some description')).toBeTruthy()
  })

  it('disables Run button when disabled prop is true', () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'ok' };"
        disabled
      />,
    )
    const runButton = screen.getByRole('button', { name: 'Run' })
    expect(runButton.hasAttribute('disabled')).toBe(true)
  })

  it('enables Run button when disabled prop is false', () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'ok' };"
      />,
    )
    const runButton = screen.getByRole('button', { name: 'Run' })
    expect(runButton.hasAttribute('disabled')).toBe(false)
  })

  it('shows result after running simple code', async () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'All good' };"
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Run' }))
    await waitFor(() => {
      expect(screen.getByText(/PASS/)).toBeTruthy()
      expect(screen.getByText('All good')).toBeTruthy()
    })
  })

  it('calls onResult callback with step output', async () => {
    const onResult = vi.fn()
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'done', data: 42 };"
        onResult={onResult}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Run' }))
    await waitFor(() => {
      expect(onResult).toHaveBeenCalledWith(
        expect.objectContaining({ status: 'pass', summary: 'done', data: 42 }),
      )
    })
  })

  it('shows error status when code throws', async () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="throw new Error('boom');"
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Run' }))
    await waitFor(() => {
      expect(screen.getByText(/ERROR/)).toBeTruthy()
      expect(screen.getByText('boom')).toBeTruthy()
    })
  })

  it('has Copy standalone button', () => {
    render(
      <RunnableCodeBlock
        title="Test Step"
        code="return { status: 'pass', summary: 'ok' };"
      />,
    )
    expect(screen.getByRole('button', { name: 'Copy standalone' })).toBeTruthy()
  })
})
