import { useContext } from 'react'
import { ParticipantContext, type ParticipantContextValue } from '../context/ParticipantContext'

export function useParticipant(): ParticipantContextValue {
  return useContext(ParticipantContext)
}
