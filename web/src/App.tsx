import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import HomePage from './pages/HomePage'
import CreateCeremonyPage from './pages/CreateCeremonyPage'
import CeremonyDetailPage from './pages/CeremonyDetailPage'
import RandomToolsPage from './pages/RandomToolsPage'
import VerifyBeaconPage from './pages/VerifyBeaconPage'
import NotFoundPage from './pages/NotFoundPage'

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<HomePage />} />
        <Route path="/create" element={<CreateCeremonyPage />} />
        <Route path="/ceremonies/:id" element={<CeremonyDetailPage />} />
        <Route path="/random" element={<RandomToolsPage />} />
        <Route path="/verify" element={<VerifyBeaconPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}
