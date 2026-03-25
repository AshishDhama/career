import { useParams } from '@tanstack/react-router'

export function ProfilePage() {
  const { userId } = useParams({ from: '/profile/$userId' })

  return (
    <div style={{ maxWidth: '700px', margin: '0 auto' }}>
      <h2>Profile</h2>
      <p style={{ color: '#666' }}>User ID: {userId}</p>
      {/* TODO: fetch and display profile from /api/profile/:userId */}
      <div style={{ padding: '2rem', border: '1px solid #eee', borderRadius: '8px', textAlign: 'center', color: '#999' }}>
        Profile loading...
      </div>
    </div>
  )
}
