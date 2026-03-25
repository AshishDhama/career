import { useEffect, useRef, useState } from 'react'
import { useParams } from '@tanstack/react-router'

export function AssessmentPage() {
  const { id } = useParams({ from: '/assessment/$id' })
  const [wsStatus, setWsStatus] = useState<'connecting' | 'connected' | 'disconnected'>('connecting')
  const [messages, setMessages] = useState<{ sender: string; text: string }[]>([])
  const [input, setInput] = useState('')
  const wsRef = useRef<WebSocket | null>(null)
  const localVideoRef = useRef<HTMLVideoElement>(null)
  const remoteVideoRef = useRef<HTMLVideoElement>(null)
  const peerRef = useRef<RTCPeerConnection | null>(null)

  useEffect(() => {
    // WebSocket connection
    const ws = new WebSocket(`ws://${location.host}/ws/assessment/${id}`)
    wsRef.current = ws

    ws.onopen = () => setWsStatus('connected')
    ws.onclose = () => setWsStatus('disconnected')
    ws.onmessage = (e) => {
      const data = JSON.parse(e.data)
      if (data.type === 'chat') {
        setMessages(prev => [...prev, { sender: data.sender, text: data.text }])
      }
      // TODO: handle WebRTC signaling messages (offer, answer, ice-candidate)
    }

    return () => ws.close()
  }, [id])

  const startVideo = async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
    if (localVideoRef.current) localVideoRef.current.srcObject = stream

    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] })
    peerRef.current = pc

    stream.getTracks().forEach(track => pc.addTrack(track, stream))

    pc.ontrack = (e) => {
      if (remoteVideoRef.current) remoteVideoRef.current.srcObject = e.streams[0]
    }

    pc.onicecandidate = (e) => {
      if (e.candidate && wsRef.current) {
        wsRef.current.send(JSON.stringify({ type: 'ice-candidate', candidate: e.candidate }))
      }
    }

    // Create offer and send via WebSocket
    const offer = await pc.createOffer()
    await pc.setLocalDescription(offer)
    wsRef.current?.send(JSON.stringify({ type: 'offer', sdp: offer }))
  }

  const sendMessage = () => {
    if (!input.trim()) return
    wsRef.current?.send(JSON.stringify({ type: 'chat', text: input }))
    setMessages(prev => [...prev, { sender: 'You', text: input }])
    setInput('')
  }

  return (
    <div style={{ maxWidth: '1100px', margin: '0 auto' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
        <h2>Assessment Session #{id}</h2>
        <span style={{ padding: '0.25rem 0.75rem', background: wsStatus === 'connected' ? '#d4edda' : '#f8d7da', borderRadius: '12px', fontSize: '0.85rem' }}>
          {wsStatus}
        </span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1rem' }}>
        <div>
          <div style={{ background: '#000', borderRadius: '8px', aspectRatio: '16/9', overflow: 'hidden' }}>
            <video ref={localVideoRef} autoPlay muted style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <p style={{ textAlign: 'center', color: '#666', fontSize: '0.85rem' }}>You</p>
        </div>
        <div>
          <div style={{ background: '#111', borderRadius: '8px', aspectRatio: '16/9', overflow: 'hidden' }}>
            <video ref={remoteVideoRef} autoPlay style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <p style={{ textAlign: 'center', color: '#666', fontSize: '0.85rem' }}>Calibrator</p>
        </div>
      </div>

      <button onClick={startVideo} style={{ padding: '0.5rem 1.5rem', background: '#28a745', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer', marginBottom: '1rem' }}>
        Start Video
      </button>

      <div style={{ border: '1px solid #eee', borderRadius: '8px', height: '200px', overflowY: 'auto', padding: '1rem', marginBottom: '0.5rem' }}>
        {messages.map((m, i) => (
          <div key={i} style={{ marginBottom: '0.5rem' }}>
            <strong>{m.sender}:</strong> {m.text}
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', gap: '0.5rem' }}>
        <input value={input} onChange={e => setInput(e.target.value)} onKeyDown={e => e.key === 'Enter' && sendMessage()} placeholder="Type a message..." style={{ flex: 1, padding: '0.5rem', borderRadius: '6px', border: '1px solid #ddd' }} />
        <button onClick={sendMessage} style={{ padding: '0.5rem 1.5rem', background: '#0070f3', color: 'white', border: 'none', borderRadius: '6px', cursor: 'pointer' }}>Send</button>
      </div>
    </div>
  )
}
