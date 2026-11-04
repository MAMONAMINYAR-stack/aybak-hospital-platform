import { useState } from 'react'
import { useDemoAuth } from '../auth/DemoAuthContext'
import DemoActionButton from '../components/DemoActionButton'

/**
 * L-03 (handoff/02-repair.md): login page extracted from the monolith.
 * R-02 repairs preserved: no prefilled credentials, honest demo notice,
 * autoComplete attributes. Login logic unchanged (demo-only).
 */
export default function LoginPage() {
  const { login } = useDemoAuth()
  const [form, setForm] = useState({ email: '', password: '' })

  const handleChange = (event) => {
    const { name, value } = event.target
    setForm((current) => ({ ...current, [name]: value }))
  }

  const handleSubmit = (event) => {
    event.preventDefault()
    login(form.email, form.password)
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-10 text-slate-100">
      <div className="grid w-full max-w-6xl overflow-hidden rounded-[32px] border border-slate-800 bg-slate-900 shadow-2xl shadow-cyan-950/30 lg:grid-cols-2">
        <div className="relative hidden overflow-hidden bg-gradient-to-br from-cyan-500 via-blue-600 to-slate-950 p-10 lg:flex lg:flex-col lg:justify-between">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,_rgba(255,255,255,0.2),transparent_35%)]" />
          <div className="relative z-10">
            <div className="mb-6 inline-flex items-center gap-3 rounded-full border border-white/20 bg-white/10 px-3 py-1.5 backdrop-blur-sm">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-slate-950/60 text-sm font-bold text-cyan-300">A</span>
              AYBAK Smart Hospital
            </div>
            <h1 className="max-w-xs text-4xl font-black leading-tight text-white">
              Healthcare operations, simplified.
            </h1>
          </div>

          <div className="relative z-10 space-y-4">
            {[
              'Clinical workflow management',
              'Live patient monitoring',
              'Smart scheduling & reports',
            ].map((item) => (
              <div key={item} className="flex items-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 backdrop-blur-sm">
                <span className="flex h-7 w-7 items-center justify-center rounded-full bg-emerald-400/20 text-sm text-emerald-300">✓</span>
                <span className="text-sm text-slate-100">{item}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="flex items-center justify-center p-6 md:p-10">
          <div className="w-full max-w-md">
            <div className="mb-8">
              <p className="text-sm uppercase tracking-[0.25em] text-cyan-300">Doctor portal</p>
              <h2 className="mt-3 text-3xl font-bold text-white">Welcome back</h2>
              <p className="mt-2 text-sm text-slate-400">Access your patient dashboard and clinical data.</p>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              <div>
                <label htmlFor="email" className="mb-2 block text-sm font-medium text-slate-200">
                  Email address
                </label>
                <input
                  id="email"
                  name="email"
                  type="email"
                  value={form.email}
                  onChange={handleChange}
                  autoComplete="email"
                  className="w-full rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition focus:border-cyan-500"
                  placeholder="doctor@aybak.com"
                />
              </div>

              <div>
                <label htmlFor="password" className="mb-2 block text-sm font-medium text-slate-200">
                  Password
                </label>
                <input
                  id="password"
                  name="password"
                  type="password"
                  value={form.password}
                  onChange={handleChange}
                  autoComplete="current-password"
                  className="w-full rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition focus:border-cyan-500"
                  placeholder="••••••••"
                />
              </div>

              <div className="flex items-center justify-between text-sm text-slate-400">
                <label className="flex items-center gap-2">
                  <input type="checkbox" className="h-4 w-4 rounded border-slate-600 bg-slate-950" />
                  Remember me
                </label>
                <DemoActionButton className="text-cyan-300 hover:text-cyan-200">
                  Forgot password?
                </DemoActionButton>
              </div>

              <button
                type="submit"
                className="w-full rounded-2xl bg-cyan-500 px-4 py-3 text-base font-semibold text-slate-950 shadow-lg shadow-cyan-500/30 transition hover:bg-cyan-400"
              >
                Sign in
              </button>
            </form>

            <div className="mt-6 rounded-2xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
              <span className="font-semibold">Demo mode:</span> any email and password will sign you in.
              This is not real authentication, and all data shown is synthetic. Not for clinical use.
            </div>
          </div>
        </div>
      </div>
    </main>
  )
}
