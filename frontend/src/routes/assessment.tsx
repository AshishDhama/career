import { useEffect, useRef, useState, useCallback } from 'react'
import { useParams } from '@tanstack/react-router'
import { useAuth } from '../lib/auth-context'

type ConnectionState = 'idle' | 'connecting' | 'connected' | 'disconnected'
type ChatMessage = { sender: string; text: string; ts: number }

const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
]

export function AssessmentPage() {
  const { id } = useParams({ from: '/assessment/$id' })
  const { user } = useAuth()

  const [connState, setConnState] = useState<ConnectionState>('idle')
  const [peerJoined, setPeerJoined] = useState(false)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [videoEnabled, setVideoEnabled] = useState(false)

  const wsRef = useRef<WebSocket | null>(null)
  const pcRef = useRef<RTCPeerConnection | null>(null)
  const localStreamRef = useRef<MediaStream | null>(null)
  const localVideoRef = useRef<HTMLVideoElement>(null)
  const remoteVideoRef = useRef<HTMLVideoElement>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  const role = user?.role ?? 'professional'

  // --- Send a signaling message ---
  const send = useCallback((msg: object) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(msg))
    }
  }, [])

  // --- Handle incoming signaling messages ---
  const handleSignal = useCallback(async (data: Record<string, unknown>) => {
    const pc = pcRef.current
    if (!pc) return

    if (data.type === 'offer') {
      await pc.setRemoteDescription(new RTCSessionDescription({ type: 'offer', sdp: data.sdp as string }))
      const answer = await pc.createAnswer()
      await pc.setLocalDescription(answer)
      send({ type: 'answer', room: id, sdp: answer.sdp })

    } else if (data.type === 'answer') {
      await pc.setRemoteDescription(new RTCSessionDescription({ type: 'answer', sdp: data.sdp as string }))

    } else if (data.type === 'ice-candidate') {
      await pc.addIceCandidate(new RTCIceCandidate({
        candidate: data.candidate as string,
        sdpMid: data.sdpMid as string,
        sdpMLineIndex: data.sdpMLineIndex as number,
      })).catch(() => {})

    } else if (data.type === 'chat') {
      setMessages(prev => [...prev, {
        sender: data.sender as string,
        text: data.text as string,
        ts: Date.now(),
      }])

    } else if (data.type === 'peer-joined') {
      setPeerJoined(true)
      addSystemMsg(`${data.role} joined the session`)
      // Caller (professional) creates the offer
      if (role === 'professional' && pc) {
        const offer = await pc.createOffer()
        await pc.setLocalDescription(offer)
        send({ type: 'offer', room: id, sdp: offer.sdp })
      }

    } else if (data.type === 'peer-left') {
      setPeerJoined(false)
      addSystemMsg('Peer left the session')
    }
  }, [id, role, send])

  const addSystemMsg = (text: string) => {
    setMessages(prev => [...prev, { sender: 'System', text, ts: Date.now() }])
  }

  // --- Set up PeerConnection ---
  const createPeerConnection = useCallback(() => {
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })

    pc.onicecandidate = (e) => {
      if (e.candidate) {
        send({
          type: 'ice-candidate',
          room: id,
          candidate: e.candidate.candidate,
          sdpMid: e.candidate.sdpMid,
          sdpMLineIndex: e.candidate.sdpMLineIndex,
        })
      }
    }

    pc.ontrack = (e) => {
      if (remoteVideoRef.current) {
        remoteVideoRef.current.srcObject = e.streams[0]
      }
    }

    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'connected') addSystemMsg('Video call connected ✓')
      if (pc.connectionState === 'disconnected') addSystemMsg('Video call disconnected')
    }

    pcRef.current = pc
    return pc
  }, [id, send])

  // --- Connect to signaling server ---
  const connect = useCallback(() => {
    if (!user) return
    setConnState('connecting')

    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${protocol}//${location.host}/ws/assessment/${id}`)
    wsRef.current = ws

    ws.onopen = () => {
      setConnState('connected')
      createPeerConnection()
      // Join the room
      send({ type: 'join', room: id, peer_id: user.id, role: user.role })
      addSystemMsg('Connected to session')
    }

    ws.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data)
        handleSignal(data)
      } catch {}
    }

    ws.onclose = () => {
      setConnState('disconnected')
      addSystemMsg('Disconnected from session')
    }

    ws.onerror = () => {
      setConnState('disconnected')
    }
  }, [id, user, send, createPeerConnection, handleSignal])

  // --- Start video ---
  const startVideo = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      localStreamRef.current = stream
      if (localVideoRef.current) localVideoRef.current.srcObject = stream
      setVideoEnabled(true)

      // Add tracks to peer connection
      if (pcRef.current) {
        stream.getTracks().forEach(track => pcRef.current!.addTrack(track, stream))
      }
    } catch (err) {
      addSystemMsg('Could not access camera/microphone')
    }
  }

  // --- Stop video ---
  const stopVideo = () => {
    localStreamRef.current?.getTracks().forEach(t => t.stop())
    localStreamRef.current = null
    if (localVideoRef.current) localVideoRef.current.srcObject = null
    setVideoEnabled(false)
  }

  // --- Send chat message ---
  const sendChat = () => {
    if (!input.trim() || !user) return
    const text = input.trim()
    send({ type: 'chat', room: id, text, sender: user.name })
    setMessages(prev => [...prev, { sender: 'You', text, ts: Date.now() }])
    setInput('')
  }

  // --- Cleanup ---
  useEffect(() => {
    return () => {
      send({ type: 'leave', room: id })
      wsRef.current?.close()
      pcRef.current?.close()
      localStreamRef.current?.getTracks().forEach(t => t.stop())
    }
  }, [id, send])

  // --- Auto-scroll chat ---
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const stateColor = {
    idle: '#6b7280',
    connecting: '#f59e0b',
    connected: '#10b981',
    disconnected: '#ef4444',
  }[connState]

  return (
    <div style={{ maxWidth: '1100px', margin: '0 auto' }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
        <div>
          <h2 style={{ margin: 0 }}>Assessment Session</h2>
          <small style={{ color: '#666' }}>ID: {id}</small>
        </div>
        <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.85rem' }}>
            <span style={{ width: 8, height: 8, borderRadius: '50%', background: stateColor, display: 'inline-block' }} />
            {peerJoined ? 'Peer connected' : connState}
          </span>
          {connState === 'idle' || connState === 'disconnected' ? (
            <button onClick={connect} style={btnStyle('#0070f3')}>Join Session</button>
          ) : null}
        </div>
      </div>

      {/* Video */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1rem' }}>
        <div>
          <div style={{ background: '#0f0f0f', borderRadius: '8px', aspectRatio: '16/9', overflow: 'hidden', position: 'relative' }}>
            <video ref={localVideoRef} autoPlay muted playsInline style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            {!videoEnabled && (
              <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#555', fontSize: '0.9rem' }}>
                Camera off
              </div>
            )}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.4rem' }}>
            <span style={{ color: '#666', fontSize: '0.85rem' }}>You ({role})</span>
            <button
              onClick={videoEnabled ? stopVideo : startVideo}
              style={btnStyle(videoEnabled ? '#ef4444' : '#10b981', '0.4rem 1rem', '0.85rem')}
            >
              {videoEnabled ? 'Stop Video' : 'Start Video'}
            </button>
          </div>
        </div>
        <div>
          <div style={{ background: '#0f0f0f', borderRadius: '8px', aspectRatio: '16/9', overflow: 'hidden', position: 'relative' }}>
            <video ref={remoteVideoRef} autoPlay playsInline style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            {!peerJoined && (
              <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#555', fontSize: '0.9rem' }}>
                Waiting for peer…
              </div>
            )}
          </div>
          <p style={{ color: '#666', fontSize: '0.85rem', marginTop: '0.4rem' }}>
            {role === 'professional' ? 'Calibrator' : 'Professional'}
          </p>
        </div>
      </div>

      {/* Chat */}
      <div style={{ border: '1px solid #e5e7eb', borderRadius: '8px', overflow: 'hidden' }}>
        <div style={{ padding: '0.5rem 1rem', background: '#f9fafb', borderBottom: '1px solid #e5e7eb', fontSize: '0.85rem', fontWeight: 600, color: '#374151' }}>
          Session Chat
        </div>
        <div style={{ height: '180px', overflowY: 'auto', padding: '0.75rem 1rem' }}>
          {messages.map((m, i) => (
            <div key={i} style={{ marginBottom: '0.4rem', fontSize: '0.9rem' }}>
              <span style={{ fontWeight: 600, color: m.sender === 'System' ? '#9ca3af' : m.sender === 'You' ? '#0070f3' : '#374151' }}>
                {m.sender}:
              </span>{' '}
              <span style={{ color: m.sender === 'System' ? '#9ca3af' : '#1f2937' }}>{m.text}</span>
            </div>
          ))}
          <div ref={messagesEndRef} />
        </div>
        <div style={{ display: 'flex', gap: '0.5rem', padding: '0.75rem', borderTop: '1px solid #e5e7eb' }}>
          <input
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && sendChat()}
            placeholder="Type a message…"
            disabled={connState !== 'connected'}
            style={{ flex: 1, padding: '0.5rem 0.75rem', borderRadius: '6px', border: '1px solid #d1d5db', fontSize: '0.9rem' }}
          />
          <button onClick={sendChat} disabled={connState !== 'connected'} style={btnStyle('#0070f3')}>
            Send
          </button>
        </div>
      </div>
    </div>
  )
}

function btnStyle(bg: string, padding = '0.5rem 1.25rem', fontSize = '0.9rem') {
  return {
    padding,
    fontSize,
    background: bg,
    color: 'white',
    border: 'none',
    borderRadius: '6px',
    cursor: 'pointer',
    fontWeight: 500,
  } as const
}
