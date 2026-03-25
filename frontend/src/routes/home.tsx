import { Link } from '@tanstack/react-router'

export function HomePage() {
  return (
    <div style={{ maxWidth: '800px', margin: '0 auto', textAlign: 'center', paddingTop: '4rem' }}>
      <h1 style={{ fontSize: '3rem', marginBottom: '1rem' }}>Skill Assessment Platform</h1>
      <p style={{ fontSize: '1.2rem', color: '#666', marginBottom: '2rem' }}>
        AI is changing the job landscape. Stay ahead with verified skill assessments
        from real industry calibrators.
      </p>
      <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center' }}>
        <Link to="/login">
          <button style={{ padding: '0.75rem 2rem', fontSize: '1rem', background: '#0070f3', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer' }}>
            Get Assessed
          </button>
        </Link>
        <Link to="/login">
          <button style={{ padding: '0.75rem 2rem', fontSize: '1rem', background: 'white', color: '#0070f3', border: '1px solid #0070f3', borderRadius: '6px', cursor: 'pointer' }}>
            Become a Calibrator
          </button>
        </Link>
      </div>
    </div>
  )
}
