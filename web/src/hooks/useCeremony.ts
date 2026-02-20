import { useEffect, useState } from 'react'
import { api } from '../api/client'
import type { CeremonyResponse } from '../api/types'

const TERMINAL_PHASES = new Set(['Finalized', 'Expired', 'Cancelled', 'Disputed'])

export function useCeremony(id: string | undefined, pollMs = 3000) {
  const [ceremony, setCeremony] = useState<CeremonyResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!id) return
    let cancelled = false

    async function fetchOnce() {
      try {
        const data = await api.getCeremony(id!)
        if (!cancelled) {
          setCeremony(data)
          setError(null)
          setLoading(false)
        }
        return data
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Failed to load ceremony')
          setLoading(false)
        }
        return null
      }
    }

    // Initial fetch
    fetchOnce().then((data) => {
      if (cancelled || !data || TERMINAL_PHASES.has(data.phase)) return
      // Poll while ceremony is not in a terminal phase
      const interval = setInterval(async () => {
        const updated = await fetchOnce()
        if (cancelled) { clearInterval(interval); return }
        if (updated && TERMINAL_PHASES.has(updated.phase)) {
          clearInterval(interval)
        }
      }, pollMs)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ;(fetchOnce as any)._interval = interval
    })

    return () => {
      cancelled = true
    }
  }, [id, pollMs])

  const refetch = async () => {
    if (!id) return
    try {
      const data = await api.getCeremony(id)
      setCeremony(data)
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load ceremony')
    }
  }

  return { ceremony, error, loading, refetch }
}
