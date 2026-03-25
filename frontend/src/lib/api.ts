const BASE = import.meta.env.VITE_API_URL ?? ''

export type Role = 'professional' | 'calibrator' | 'admin'

export interface User {
  id: string
  name: string
  email: string
  role: Role
}

export interface AuthResponse {
  token: string
  user: User
}

// --- Token storage ---
export const getToken = () => localStorage.getItem('token')
export const setToken = (t: string) => localStorage.setItem('token', t)
export const clearToken = () => localStorage.removeItem('token')

// --- Base fetch wrapper ---
async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken()
  const res = await fetch(`${BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.headers ?? {}),
    },
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error ?? 'Request failed')
  return data as T
}

// --- Auth ---
export const authApi = {
  register: (email: string, password: string, name: string, role: Role) =>
    api<AuthResponse>('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, password, name, role }),
    }),

  login: (email: string, password: string) =>
    api<AuthResponse>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),

  me: () => api<User>('/api/me'),
}

// --- Health ---
export const health = () => api<{ status: string }>('/api/health')
