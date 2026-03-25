import { useState } from 'react'
import { useNavigate } from '@tanstack/react-router'

export function LoginPage() {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [role, setRole] = useState<'professional' | 'calibrator'>('professional')
  const navigate = useNavigate()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    // TODO: call /api/auth/login or /api/auth/register
    navigate({ to: '/dashboard' })
  }

  return (
    <div style={{ maxWidth: '400px', margin: '2rem auto' }}>
      <h2>{mode === 'login' ? 'Sign In' : 'Create Account'}</h2>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
        <input type="email" placeholder="Email" required style={{ padding: '0.75rem', borderRadius: '6px', border: '1px solid #ddd' }} />
        <input type="password" placeholder="Password" required style={{ padding: '0.75rem', borderRadius: '6px', border: '1px solid #ddd' }} />
        {mode === 'register' && (
          <select value={role} onChange={e => setRole(e.target.value as typeof role)} style={{ padding: '0.75rem', borderRadius: '6px', border: '1px solid #ddd' }}>
            <option value="professional">Professional (get assessed)</option>
            <option value="calibrator">Calibrator (assess others)</option>
          </select>
        )}
        <button type="submit" style={{ padding: '0.75rem', background: '#0070f3', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer', fontSize: '1rem' }}>
          {mode === 'login' ? 'Sign In' : 'Create Account'}
        </button>
      </form>
      <p style={{ textAlign: 'center', marginTop: '1rem', color: '#666' }}>
        {mode === 'login' ? "Don't have an account? " : 'Already have an account? '}
        <span style={{ color: '#0070f3', cursor: 'pointer' }} onClick={() => setMode(mode === 'login' ? 'register' : 'login')}>
          {mode === 'login' ? 'Register' : 'Sign In'}
        </span>
      </p>
    </div>
  )
}
