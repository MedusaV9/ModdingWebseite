import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { api, onUnauthorized } from '../api/client.ts'
import { wsClient } from '../api/ws.ts'
import type { PanelMeta, SafeUser } from '../api/types.ts'
import { applyTheme } from '../themes.ts'
import { useI18n } from '../i18n/index.tsx'

interface AuthContextValue {
  user: SafeUser | null
  meta: PanelMeta | null
  loading: boolean
  refresh: () => Promise<void>
  setUser: (user: SafeUser | null) => void
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue>({
  user: null,
  meta: null,
  loading: true,
  refresh: async () => undefined,
  setUser: () => undefined,
  logout: async () => undefined,
})

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<SafeUser | null>(null)
  const [meta, setMeta] = useState<PanelMeta | null>(null)
  const [loading, setLoading] = useState(true)
  const { setLang } = useI18n()

  const refresh = useCallback(async () => {
    try {
      const metaRes = await api.get<PanelMeta>('/api/meta')
      setMeta(metaRes)
      try {
        const me = await api.get<{ user: SafeUser }>('/api/auth/me', { emit401: false })
        setUser(me.user)
      } catch {
        setUser(null)
      }
    } catch {
      setMeta(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  // Apply user prefs (theme, language) when the user changes
  useEffect(() => {
    const themeId = user?.prefs.theme ?? meta?.defaultTheme ?? 'between-dark'
    applyTheme(themeId, user?.prefs.accent ?? null)
    if (user?.prefs.language === 'de' || user?.prefs.language === 'en') setLang(user.prefs.language)
  }, [user, meta, setLang])

  // WS lifecycle follows auth state
  useEffect(() => {
    if (user) wsClient.connect()
    else wsClient.disconnect()
  }, [user])

  useEffect(() => {
    return onUnauthorized(() => setUser(null))
  }, [])

  const logout = useCallback(async () => {
    try {
      await api.post('/api/auth/logout')
    } catch {
      /* session may already be gone */
    }
    setUser(null)
  }, [])

  const value = useMemo(
    () => ({ user, meta, loading, refresh, setUser, logout }),
    [user, meta, loading, refresh, logout],
  )
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  return useContext(AuthContext)
}
