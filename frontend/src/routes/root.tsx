import { Outlet, Link } from '@tanstack/react-router'

export function RootLayout() {
  return (
    <div style={{ fontFamily: 'system-ui, sans-serif' }}>
      <nav style={{ padding: '1rem 2rem', borderBottom: '1px solid #eee', display: 'flex', gap: '1.5rem', alignItems: 'center' }}>
        <Link to="/" style={{ fontWeight: 'bold', fontSize: '1.2rem', textDecoration: 'none', color: '#1a1a1a' }}>
          Career
        </Link>
        <Link to="/dashboard">Dashboard</Link>
        <Link to="/login" style={{ marginLeft: 'auto' }}>Login</Link>
      </nav>
      <main style={{ padding: '2rem' }}>
        <Outlet />
      </main>
    </div>
  )
}
