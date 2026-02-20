import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { ParticipantProvider } from './context/ParticipantContext'
import './index.css'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <ParticipantProvider>
        <App />
      </ParticipantProvider>
    </BrowserRouter>
  </StrictMode>,
)
