import { useState } from 'react'
import { useNavigate } from '@tanstack/react-router'
import { useAuth } from '../lib/auth-context'

export function LoginPage() {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [role, setRole] = useState<'professional' | 'calibrator'>('professional')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { login, register } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      if (mode === 'login') {
        await login(email, password)
      } else {
        await register(email, password, name, role)
      }
      navigate({ to: '/dashboard' })
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Something went wrong')
    } finally {
      setLoading(false)
    }
  }

  const inputStyle = {
    padding: '0.75rem',
    borderRadius: '6px',
    border: '1px solid #ddd',
    fontSize: '1rem',
    width: '100%',
    boxSizing: 'border-box' as const,
  }

  return (
    <div style={{ maxWidth: '400px', margin: '2rem auto' }}>
      <h2 style={{ marginBottom: '1.5rem' }}>
        {mode === 'login' ? 'Sign In' : 'Create Account'}
      </h2>

      {error && (
        <div style={{ background: '#fef2f2', border: '1px solid #fca5a5', color: '#b91c1c', padding: '0.75rem', borderRadius: '6px', marginBottom: '1rem', fontSize: '0.9rem' }}>
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
        {mode === 'register' && (
          <input
            type="text"
            placeholder="Full Name"
            value={name}
            onChange={e => setName(e.target.value)}
            required
            style={inputStyle}
          />
        )}
        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          required
          style={inputStyle}
        />
        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={e => setPassword(e.target.value)}
          required
          minLength={8}
          style={inputStyle}
        />
        {mode === 'register' && (
          <select
            value={role}
            onChange={e => setRole(e.target.value as typeof role)}
            style={inputStyle}
          >
            <option value="professional">Professional — get my skills assessed</option>
            <option value="calibrator">Calibrator — assess others</option>
          </select>
        )}
        <button
          type="submit"
          disabled={loading}
          style={{
            padding: '0.75rem',
            background: loading ? '#93c5fd' : '#0070f3',
            color: 'white',
            border: 'none',
            borderRadius: '6px',
            cursor: loading ? 'not-allowed' : 'pointer',
            fontSize: '1rem',
            fontWeight: 600,
          }}
        >
          {loading ? 'Please wait...' : mode === 'login' ? 'Sign In' : 'Create Account'}
        </button>
      </form>

      <p style={{ textAlign: 'center', marginTop: '1.5rem', color: '#666' }}>
        {mode === 'login' ? "Don't have an account? " : 'Already have an account? '}
        <span
          style={{ color: '#0070f3', cursor: 'pointer', fontWeight: 500 }}
          onClick={() => { setMode(mode === 'login' ? 'register' : 'login'); setError('') }}
        >
          {mode === 'login' ? 'Register' : 'Sign In'}
        </span>
      </p>
    </div>
  )
}
