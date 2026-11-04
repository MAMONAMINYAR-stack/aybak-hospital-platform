import { act, renderHook } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { DemoAuthProvider, useDemoAuth } from './DemoAuthContext'

const wrapper = ({ children }) => <DemoAuthProvider>{children}</DemoAuthProvider>

describe('demo auth (L-03 acceptance criteria — behavior preserved)', () => {
  it('starts logged out', () => {
    const { result } = renderHook(() => useDemoAuth(), { wrapper })
    expect(result.current.isLoggedIn).toBe(false)
  })

  it('rejects empty credentials', () => {
    const { result } = renderHook(() => useDemoAuth(), { wrapper })
    act(() => {
      expect(result.current.login('', '')).toBe(false)
      expect(result.current.login('demo@example.com', '')).toBe(false)
      expect(result.current.login('', 'secret')).toBe(false)
    })
    expect(result.current.isLoggedIn).toBe(false)
  })

  it('accepts any non-empty credentials (demo only) and logs out', () => {
    const { result } = renderHook(() => useDemoAuth(), { wrapper })
    act(() => {
      expect(result.current.login('demo@example.com', 'anything')).toBe(true)
    })
    expect(result.current.isLoggedIn).toBe(true)
    act(() => result.current.logout())
    expect(result.current.isLoggedIn).toBe(false)
  })

  it('throws when used outside the provider', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {})
    expect(() => renderHook(() => useDemoAuth())).toThrow(/DemoAuthProvider/)
    spy.mockRestore()
  })
})
