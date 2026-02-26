import { Link, Outlet } from 'react-router-dom'

export default function Layout() {
  return (
    <div className="min-h-screen bg-gray-50 text-gray-900">
      <nav className="bg-white border-b border-gray-200 px-6 py-3 flex items-center gap-6">
        <Link to="/" className="text-lg font-bold text-indigo-600">Veritas</Link>
        <Link to="/create" className="text-sm text-gray-600 hover:text-gray-900">Create Ceremony</Link>
        <Link to="/random" className="text-sm text-gray-600 hover:text-gray-900">Random Tools</Link>
        <Link to="/pools/demo" className="text-sm text-gray-600 hover:text-gray-900">Pool Demo</Link>
        <Link to="/verify" className="text-sm text-gray-600 hover:text-gray-900">Verify</Link>
      </nav>
      <main className="max-w-3xl mx-auto px-4 py-8">
        <Outlet />
      </main>
    </div>
  )
}
