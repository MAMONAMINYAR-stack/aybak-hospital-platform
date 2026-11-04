import { useState } from 'react'

/**
 * L-04 (handoff/02-repair.md): non-sensitive notification preferences now
 * persist in localStorage (audit F-07). These are UI preferences only —
 * no patient data or credentials are ever stored.
 */
export const PREFS_STORAGE_KEY = 'aybak.demo.notificationPrefs.v1'

const preferenceOptions = [
  { id: 'emailAlerts', label: 'Email alerts' },
  { id: 'smsReminders', label: 'SMS reminders' },
  { id: 'appointmentConfirmations', label: 'Appointment confirmations' },
  { id: 'weeklyReports', label: 'Weekly reports' },
]

const defaultPrefs = Object.fromEntries(preferenceOptions.map((option) => [option.id, true]))

function loadPrefs() {
  try {
    const stored = window.localStorage.getItem(PREFS_STORAGE_KEY)
    if (!stored) return defaultPrefs
    const parsed = JSON.parse(stored)
    return { ...defaultPrefs, ...parsed }
  } catch {
    return defaultPrefs
  }
}

export default function SettingsPage() {
  const [prefs, setPrefs] = useState(loadPrefs)

  const handleToggle = (id) => {
    setPrefs((current) => {
      const next = { ...current, [id]: !current[id] }
      try {
        window.localStorage.setItem(PREFS_STORAGE_KEY, JSON.stringify(next))
      } catch {
        // Storage unavailable (private mode etc.) — preferences stay in memory.
      }
      return next
    })
  }

  return (
    <section className="mt-6 grid gap-6 lg:grid-cols-2">
      <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
        <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Profile</p>
        <h3 className="mt-1 text-2xl font-bold text-white">Doctor Settings</h3>

        <div className="mt-5 space-y-4 text-sm text-slate-300">
          <div className="rounded-2xl bg-slate-950 p-3">Name: Dr. Maya Foster</div>
          <div className="rounded-2xl bg-slate-950 p-3">Department: Cardiology</div>
          <div className="rounded-2xl bg-slate-950 p-3">Shift: 08:00 - 16:00</div>
        </div>
      </div>

      <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
        <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Preferences</p>
        <h3 className="mt-1 text-2xl font-bold text-white">Notifications</h3>

        <div className="mt-5 space-y-3 text-sm text-slate-300">
          {preferenceOptions.map((option) => (
            <label key={option.id} className="flex items-center justify-between rounded-2xl bg-slate-950 p-3">
              <span>{option.label}</span>
              <input
                type="checkbox"
                checked={prefs[option.id]}
                onChange={() => handleToggle(option.id)}
                className="h-4 w-4 rounded border-slate-600 bg-slate-950"
              />
            </label>
          ))}
        </div>

        <p className="mt-4 text-xs text-slate-500">
          Preferences are stored locally in your browser only (demo UI settings — no patient data).
        </p>
      </div>
    </section>
  )
}
