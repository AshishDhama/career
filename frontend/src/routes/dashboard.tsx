import { Link } from '@tanstack/react-router'

export function DashboardPage() {
  // TODO: fetch from /api/dashboard based on user role
  const mockAssessments = [
    { id: '1', skill: 'React Development', status: 'pending', calibrator: 'Jane Smith' },
    { id: '2', skill: 'System Design', status: 'completed', score: 87, calibrator: 'Bob Chen' },
  ]

  return (
    <div style={{ maxWidth: '900px', margin: '0 auto' }}>
      <h2>Your Dashboard</h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '1rem', marginBottom: '2rem' }}>
        <div style={{ padding: '1.5rem', border: '1px solid #eee', borderRadius: '8px', textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 'bold' }}>2</div>
          <div style={{ color: '#666' }}>Assessments</div>
        </div>
        <div style={{ padding: '1.5rem', border: '1px solid #eee', borderRadius: '8px', textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 'bold' }}>87</div>
          <div style={{ color: '#666' }}>Avg Score</div>
        </div>
        <div style={{ padding: '1.5rem', border: '1px solid #eee', borderRadius: '8px', textAlign: 'center' }}>
          <div style={{ fontSize: '2rem', fontWeight: 'bold' }}>1</div>
          <div style={{ color: '#666' }}>Pending</div>
        </div>
      </div>
      <h3>Assessments</h3>
      {mockAssessments.map(a => (
        <div key={a.id} style={{ padding: '1rem', border: '1px solid #eee', borderRadius: '8px', marginBottom: '0.75rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <strong>{a.skill}</strong>
            <div style={{ color: '#666', fontSize: '0.9rem' }}>Calibrator: {a.calibrator}</div>
          </div>
          <div style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
            {a.score && <span style={{ fontWeight: 'bold', color: '#0070f3' }}>{a.score}/100</span>}
            <span style={{ padding: '0.25rem 0.75rem', background: a.status === 'completed' ? '#d4edda' : '#fff3cd', borderRadius: '12px', fontSize: '0.85rem' }}>
              {a.status}
            </span>
            <Link to="/assessment/$id" params={{ id: a.id }}>
              <button style={{ padding: '0.4rem 1rem', background: '#0070f3', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer' }}>
                {a.status === 'pending' ? 'Join' : 'Review'}
              </button>
            </Link>
          </div>
        </div>
      ))}
    </div>
  )
}
