import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import SettingsPage, { PREFS_STORAGE_KEY } from './SettingsPage'

describe('SettingsPage preferences (L-04 acceptance criteria)', () => {
  it('defaults all notification preferences to on', () => {
    render(<SettingsPage />)
    const checkboxes = screen.getAllByRole('checkbox')
    expect(checkboxes).toHaveLength(4)
    for (const checkbox of checkboxes) {
      expect(checkbox).toBeChecked()
    }
  })

  it('persists a toggle to localStorage and restores it on remount', async () => {
    const user = userEvent.setup()
    const { unmount } = render(<SettingsPage />)

    const emailAlerts = screen.getByRole('checkbox', { name: /email alerts/i })
    await user.click(emailAlerts)
    expect(emailAlerts).not.toBeChecked()

    const stored = JSON.parse(window.localStorage.getItem(PREFS_STORAGE_KEY))
    expect(stored.emailAlerts).toBe(false)
    expect(stored.smsReminders).toBe(true)

    unmount()
    render(<SettingsPage />)
    expect(screen.getByRole('checkbox', { name: /email alerts/i })).not.toBeChecked()
  })

  it('survives corrupted storage without crashing', () => {
    window.localStorage.setItem(PREFS_STORAGE_KEY, '{not json')
    render(<SettingsPage />)
    expect(screen.getAllByRole('checkbox')[0]).toBeChecked()
  })

  it('stores no credentials or patient data in localStorage', async () => {
    const user = userEvent.setup()
    render(<SettingsPage />)
    await user.click(screen.getByRole('checkbox', { name: /weekly reports/i }))

    const stored = window.localStorage.getItem(PREFS_STORAGE_KEY)
    expect(stored).not.toMatch(/password|email.*@|patient/i)
    expect(Object.keys(JSON.parse(stored)).sort()).toEqual(
      ['appointmentConfirmations', 'emailAlerts', 'smsReminders', 'weeklyReports'],
    )
  })
})
