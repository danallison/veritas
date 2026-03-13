import { Link, Outlet, useLocation } from 'react-router-dom'

function NavLink({ to, activePrefix, children }: { to: string; activePrefix?: string; children: React.ReactNode }) {
  const location = useLocation()
  const prefix = activePrefix ?? to
  const isActive = location.pathname === prefix || location.pathname.startsWith(prefix + '/')
  return (
    <Link
      to={to}
      className={`text-sm ${isActive ? 'text-indigo-600 font-medium' : 'text-gray-600 hover:text-gray-900'}`}
    >
      {children}
    </Link>
  )
}

export default function Layout() {
  return (
    <div className="min-h-screen bg-gray-50 text-gray-900">
      <nav className="bg-white border-b border-gray-200 px-6 py-3 flex items-center gap-6">
        <Link to="/" className="text-lg font-bold text-indigo-600">Veritas</Link>
        <NavLink to="/verify/new" activePrefix="/verify">Verify</NavLink>
        <NavLink to="/pools">Pools</NavLink>
        <NavLink to="/cache">Cache</NavLink>
        <div className="flex-1" />
        <NavLink to="/advanced">Advanced</NavLink>
      </nav>
      <main className="max-w-3xl mx-auto px-4 py-8">
        <Outlet />
      </main>
    </div>
  )
}
