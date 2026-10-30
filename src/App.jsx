const stats = [
  { label: 'Beds Available', value: '128' },
  { label: 'Doctors Online', value: '34' },
  { label: 'Patients Today', value: '1,482' },
  { label: 'Avg. Response', value: '4.2 min' },
]

const services = [
  'Emergency coordination',
  'Patient intake & triage',
  'Lab diagnostics',
  'Medication tracking',
  'Hospital operations',
  'Smart reporting',
]

const queue = [
  { name: 'Surgery Ward', count: '12 active', accent: 'bg-cyan-500/15 text-cyan-300' },
  { name: 'ICU', count: '7 active', accent: 'bg-emerald-500/15 text-emerald-300' },
  { name: 'Radiology', count: '9 active', accent: 'bg-violet-500/15 text-violet-300' },
]

export default function App() {
  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="mx-auto max-w-7xl px-6 py-10 lg:px-8">
        <header className="flex items-center justify-between rounded-full border border-slate-800 bg-slate-900/70 px-5 py-3 backdrop-blur-sm">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-cyan-500/15 text-lg font-bold text-cyan-300">
              A
            </div>
            <div>
              <p className="text-sm font-medium text-slate-400">AYBAK</p>
              <h1 className="text-base font-semibold text-white">Smart Hospital</h1>
            </div>
          </div>

          <nav className="hidden gap-8 text-sm text-slate-300 md:flex">
            <a href="#overview" className="hover:text-white">Overview</a>
            <a href="#services" className="hover:text-white">Services</a>
            <a href="#operations" className="hover:text-white">Operations</a>
          </nav>

          <button className="rounded-full bg-cyan-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-cyan-400">
            Access Portal
          </button>
        </header>

        <section className="mt-10 grid gap-6 lg:grid-cols-[1.2fr_0.8fr] lg:items-center">
          <div>
            <span className="inline-flex rounded-full border border-cyan-500/30 bg-cyan-500/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-cyan-300">
              Live operations dashboard
            </span>
            <h2 className="mt-6 text-4xl font-black tracking-tight text-white md:text-6xl">
              Better care starts with <span className="text-cyan-400">smarter coordination</span>.
            </h2>
            <p className="mt-5 max-w-xl text-lg text-slate-300">
              A unified hospital operations platform for patient flow, staff coordination, diagnostics,
              and decision support.
            </p>

            <div className="mt-8 flex flex-wrap gap-4">
              <button className="rounded-full bg-cyan-500 px-5 py-3 font-semibold text-slate-950 shadow-lg shadow-cyan-500/30 transition hover:bg-cyan-400">
                Launch Dashboard
              </button>
              <button className="rounded-full border border-slate-700 bg-slate-900 px-5 py-3 font-semibold text-white transition hover:border-slate-500 hover:bg-slate-800">
                View Reports
              </button>
            </div>
          </div>

          <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5 shadow-2xl shadow-cyan-950/30">
            <div className="rounded-2xl border border-slate-800 bg-slate-950 p-4">
              <div className="mb-4 flex items-center justify-between">
                <div>
                  <p className="text-sm text-slate-400">System health</p>
                  <p className="text-2xl font-bold text-white">98.6%</p>
                </div>
                <span className="rounded-full bg-emerald-500/15 px-2 py-1 text-xs font-semibold text-emerald-300">
                  Stable
                </span>
              </div>

              <div className="space-y-4">
                {queue.map((item) => (
                  <div key={item.name} className="flex items-center justify-between rounded-xl bg-slate-900 p-3">
                    <div className="flex items-center gap-3">
                      <span className={`inline-flex h-2.5 w-2.5 rounded-full ${item.accent.includes('cyan') ? 'bg-cyan-400' : item.accent.includes('emerald') ? 'bg-emerald-400' : 'bg-violet-400'}`} />
                      <span className="font-medium text-slate-200">{item.name}</span>
                    </div>
                    <span className="text-sm text-slate-400">{item.count}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        <section id="overview" className="mt-12 grid gap-5 md:grid-cols-4">
          {stats.map((stat) => (
            <div key={stat.label} className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
              <p className="text-sm text-slate-400">{stat.label}</p>
              <p className="mt-3 text-3xl font-bold text-white">{stat.value}</p>
            </div>
          ))}
        </section>

        <section id="services" className="mt-12 grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
          <div className="rounded-3xl border border-slate-800 bg-slate-900 p-6">
            <p className="text-sm uppercase tracking-[0.2em] text-cyan-300">Core capabilities</p>
            <h3 className="mt-4 text-3xl font-bold text-white">Healthcare intelligence built for daily operations</h3>
            <ul className="mt-6 space-y-4">
              {services.map((item) => (
                <li key={item} className="flex items-center gap-3 text-slate-200">
                  <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-cyan-500/15 text-cyan-300">
                    ✓
                  </span>
                  {item}
                </li>
              ))}
            </ul>
          </div>

          <div id="operations" className="rounded-3xl border border-slate-800 bg-gradient-to-br from-slate-900 to-slate-950 p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-400">Department summary</p>
                <h3 className="text-2xl font-bold text-white">Today’s performance</h3>
              </div>
              <span className="rounded-full border border-emerald-500/30 bg-emerald-500/10 px-3 py-1 text-xs font-semibold text-emerald-300">
                +12.4%
              </span>
            </div>

            <div className="mt-8 space-y-6">
              {[
                { label: 'Patient throughput', value: '86%', width: '86%' },
                { label: 'Staff utilization', value: '75%', width: '75%' },
                { label: 'Digital workflow adoption', value: '92%', width: '92%' },
              ].map((item) => (
                <div key={item.label}>
                  <div className="mb-2 flex items-center justify-between text-sm text-slate-300">
                    <span>{item.label}</span>
                    <span>{item.value}</span>
                  </div>
                  <div className="h-2.5 w-full overflow-hidden rounded-full bg-slate-800">
                    <div className="h-full rounded-full bg-gradient-to-r from-cyan-400 to-blue-500" style={{ width: item.width }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>
      </div>
    </main>
  )
}
