import { createContext, useContext, useMemo, useState } from 'react'

/**
 * DEMO AUTH ONLY — in-memory, no real authentication, no persistence.
 * ورود نمایشی — فقط در حافظه، بدون احراز هویت واقعی.
 *
 * L-03 (handoff/02-repair.md): behavior preserved from the original App.jsx
 * (any non-empty email + password signs in). Real authentication, sessions and
 * credential validation are NEEDS-APPROVAL items (handoff/01-audit.md F-02).
 */
const DemoAuthContext = createContext(null)

export function DemoAuthProvider({ children }) {
  const [isLoggedIn, setIsLoggedIn] = useState(false)

  const value = useMemo(
    () => ({
      isLoggedIn,
      login: (email, password) => {
        if (email && password) {
          setIsLoggedIn(true)
          return true
        }
        return false
      },
      logout: () => setIsLoggedIn(false),
    }),
    [isLoggedIn],
  )

  return <DemoAuthContext.Provider value={value}>{children}</DemoAuthContext.Provider>
}

export function useDemoAuth() {
  const context = useContext(DemoAuthContext)
  if (!context) {
    throw new Error('useDemoAuth must be used within a DemoAuthProvider')
  }
  return context
}
