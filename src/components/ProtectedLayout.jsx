import { NavLink, Outlet } from 'react-router-dom'
import { useDemoAuth } from '../auth/DemoAuthContext'
import { navItems } from '../data/demoData'
import DemoActionButton from './DemoActionButton'

/**
 * L-03/L-06 (handoff/02-repair.md): layout extracted from the monolith,
 * nav gets an accessible name, Export becomes an honest demo action,
 * and a persistent DEMO banner labels the whole portal (audit F-13).
 */
export default function ProtectedLayout() {
  const { logout } = useDemoAuth()

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto flex max-w-7xl gap-6 px-4 py-6 lg:px-6">
        <aside className="hidden w-72 shrink-0 rounded-3xl border border-slate-800 bg-slate-900/80 p-5 lg:block">
          <div className="flex items-center gap-3">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-cyan-500/15 text-lg font-bold text-cyan-300">
              Dr
            </div>
            <div>
              <p className="text-xs uppercase tracking-[0.25em] text-slate-400">Doctor</p>
              <h1 className="text-lg font-semibold text-white">Maya Foster</h1>
            </div>
          </div>

          <nav className="mt-8 space-y-2" aria-label="Main navigation">
            {navItems.map((item) => (
              <NavLink
                key={item.label}
                to={item.path}
                end={item.path === '/'}
                className={({ isActive }) =>
                  `flex w-full items-center justify-between rounded-2xl px-3 py-3 text-left text-sm font-medium transition ${
                    isActive ? 'bg-cyan-500/15 text-cyan-300' : 'text-slate-300 hover:bg-slate-800 hover:text-white'
                  }`
                }
              >
                {item.label}
                {item.path === '/' && <span className="rounded-full bg-cyan-500 px-2 py-0.5 text-[10px] font-bold text-slate-950">Live</span>}
              </NavLink>
            ))}
          </nav>

          <div className="mt-10 rounded-2xl border border-slate-800 bg-slate-950 p-4">
            <p className="text-xs uppercase tracking-[0.2em] text-slate-400">Today</p>
            <p className="mt-2 text-2xl font-bold text-white">8</p>
            <p className="text-sm text-slate-400">visits scheduled</p>
          </div>
        </aside>

        <div className="flex-1">
          <header className="rounded-3xl border border-slate-800 bg-slate-900/80 px-5 py-4 backdrop-blur-sm">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="text-sm uppercase tracking-[0.2em] text-cyan-300">Welcome back</p>
                <h2 className="mt-1 text-3xl font-bold text-white">AYBAK Hospital</h2>
              </div>

              <div className="flex items-center gap-3">
                <DemoActionButton className="rounded-full border border-slate-700 bg-slate-950 px-4 py-2 text-sm font-medium text-slate-200 hover:border-slate-500">
                  Export
                </DemoActionButton>
                <button
                  type="button"
                  onClick={logout}
                  className="rounded-full bg-slate-800 px-4 py-2 text-sm font-semibold text-slate-100 hover:bg-slate-700"
                >
                  Log out
                </button>
              </div>
            </div>
          </header>

          <p className="mt-3 rounded-2xl border border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs font-medium text-amber-200">
            DEMO — synthetic data only. No real authentication. Not for clinical use.
          </p>

          <Outlet />
        </div>
      </div>
    </main>
  )
}
