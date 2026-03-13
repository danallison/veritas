import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import HomePage from './pages/HomePage'
import VerifyPage from './pages/VerifyPage'
import VerificationDetailPage from './pages/VerificationDetailPage'
import PoolsPage from './pages/PoolsPage'
import PoolDetailPage from './pages/PoolDetailPage'
import CachePage from './pages/CachePage'
import CreateCeremonyPage from './pages/CreateCeremonyPage'
import CeremonyDetailPage from './pages/CeremonyDetailPage'
import RandomToolsPage from './pages/RandomToolsPage'
import VerificationGuidePage from './pages/VerificationGuidePage'
import AdvancedPage from './pages/AdvancedPage'
import PoolDemoPage from './pages/PoolDemoPage'
import NotFoundPage from './pages/NotFoundPage'

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        {/* Primary: Verification */}
        <Route path="/" element={<HomePage />} />
        <Route path="/verify/new" element={<VerifyPage />} />
        <Route path="/verify/:id" element={<VerificationDetailPage />} />

        {/* Pools */}
        <Route path="/pools" element={<PoolsPage />} />
        <Route path="/pools/:id" element={<PoolDetailPage />} />

        {/* Cache */}
        <Route path="/cache" element={<CachePage />} />

        {/* Advanced: Ceremony & Random (demoted) */}
        <Route path="/advanced" element={<AdvancedPage />} />
        <Route path="/advanced/ceremonies/new" element={<CreateCeremonyPage />} />
        <Route path="/advanced/ceremonies/:id" element={<CeremonyDetailPage />} />
        <Route path="/advanced/random" element={<RandomToolsPage />} />
        <Route path="/advanced/demo" element={<PoolDemoPage />} />
        <Route path="/advanced/guide" element={<VerificationGuidePage />} />
        <Route path="/advanced/guide/:ceremonyId" element={<VerificationGuidePage />} />

        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}
