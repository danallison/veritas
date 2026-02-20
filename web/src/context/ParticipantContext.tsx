import { createContext, useCallback, useState, type ReactNode } from 'react'

const ID_STORAGE_KEY = 'veritas_participant_id'
const NAME_STORAGE_KEY = 'veritas_display_name'

export interface ParticipantContextValue {
  participantId: string
  displayName: string
  setDisplayName: (name: string) => void
}

export const ParticipantContext = createContext<ParticipantContextValue>({
  participantId: '',
  displayName: '',
  setDisplayName: () => {},
})

export function ParticipantProvider({ children }: { children: ReactNode }) {
  const [participantId] = useState<string>(() => {
    const stored = localStorage.getItem(ID_STORAGE_KEY)
    if (stored) return stored
    const id = crypto.randomUUID()
    localStorage.setItem(ID_STORAGE_KEY, id)
    return id
  })

  const [displayName, setDisplayNameState] = useState<string>(
    () => localStorage.getItem(NAME_STORAGE_KEY) ?? ''
  )

  const setDisplayName = useCallback((name: string) => {
    setDisplayNameState(name)
    localStorage.setItem(NAME_STORAGE_KEY, name)
  }, [])

  return (
    <ParticipantContext.Provider value={{ participantId, displayName, setDisplayName }}>
      {children}
    </ParticipantContext.Provider>
  )
}
