import { useCallback } from 'react'

interface CeremonySecrets {
  entropy?: string   // hex-encoded entropy value (present for commit-reveal methods)
  seal?: string      // hex-encoded seal hash (present for commit-reveal methods)
  committed: boolean // whether this participant has committed
}

function storageKey(ceremonyId: string): string {
  return `veritas_secret_${ceremonyId}`
}

export function useCeremonySecrets(ceremonyId: string) {
  const getSecrets = useCallback((): CeremonySecrets | null => {
    const raw = sessionStorage.getItem(storageKey(ceremonyId))
    if (!raw) return null
    return JSON.parse(raw) as CeremonySecrets
  }, [ceremonyId])

  const saveSecrets = useCallback((secrets: CeremonySecrets) => {
    sessionStorage.setItem(storageKey(ceremonyId), JSON.stringify(secrets))
  }, [ceremonyId])

  const clearSecrets = useCallback(() => {
    sessionStorage.removeItem(storageKey(ceremonyId))
  }, [ceremonyId])

  return { getSecrets, saveSecrets, clearSecrets }
}
