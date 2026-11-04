import { NavLink } from 'react-router-dom'
import { appointments, doctorStats, patients, schedule } from '../data/demoData'

/** L-03 (handoff/02-repair.md): dashboard extracted from the monolith; UI preserved. */
export default function DashboardPage() {
  return (
    <>
      <section className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {doctorStats.map((stat) => (
          <div key={stat.label} className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
            <div className="flex items-center justify-between">
              <p className="text-sm text-slate-400">{stat.label}</p>
              <span className="rounded-full bg-emerald-500/15 px-2 py-1 text-[10px] font-semibold text-emerald-300">
                {stat.trend}
              </span>
            </div>
            <p className="mt-4 text-3xl font-bold text-white">{stat.value}</p>
          </div>
        ))}
      </section>

      <section className="mt-6 grid gap-6 xl:grid-cols-[1.4fr_0.9fr]">
        <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Appointments</p>
              <h3 className="mt-1 text-2xl font-bold text-white">Today’s Schedule</h3>
            </div>
            <NavLink to="/appointments" className="rounded-full border border-slate-700 bg-slate-950 px-3 py-1.5 text-xs font-medium text-slate-200">
              View all
            </NavLink>
          </div>

          <div className="mt-5 space-y-4">
            {appointments.map((item) => (
              <div key={item.time} className="flex flex-col gap-3 rounded-2xl border border-slate-800 bg-slate-950 p-4 md:flex-row md:items-center md:justify-between">
                <div className="flex items-center gap-4">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-cyan-500/10 text-sm font-semibold text-cyan-300">
                    {item.patient.charAt(0)}
                  </div>
                  <div>
                    <p className="font-semibold text-white">{item.patient}</p>
                    <p className="text-sm text-slate-400">{item.issue}</p>
                  </div>
                </div>

                <div className="flex items-center gap-3 md:gap-4">
                  <span className="text-sm text-slate-300">{item.time}</span>
                  <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${item.color}`}>
                    {item.status}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Overview</p>
              <h3 className="mt-1 text-2xl font-bold text-white">Weekly Load</h3>
            </div>
          </div>

          <div className="mt-6 flex items-end justify-between gap-3">
            {[52, 68, 74, 55, 84, 92, 61].map((value, index) => (
              <div key={index} className="flex flex-1 flex-col items-center gap-2">
                <div
                  className={`w-full rounded-t-2xl ${index === 5 ? 'bg-cyan-500' : 'bg-slate-700'}`}
                  style={{ height: `${value}px` }}
                />
                <span className="text-xs text-slate-400">{schedule[index]?.day}</span>
              </div>
            ))}
          </div>

          <div className="mt-8 space-y-3">
            <div className="flex items-center justify-between rounded-2xl bg-slate-950 p-3">
              <span className="text-sm text-slate-300">Emergency Cases</span>
              <span className="font-semibold text-white">14</span>
            </div>
            <div className="flex items-center justify-between rounded-2xl bg-slate-950 p-3">
              <span className="text-sm text-slate-300">Lab Results</span>
              <span className="font-semibold text-white">27</span>
            </div>
          </div>
        </div>
      </section>

      <section className="mt-6 rounded-3xl border border-slate-800 bg-slate-900 p-5">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Patients</p>
            <h3 className="mt-1 text-2xl font-bold text-white">Recent Records</h3>
          </div>
          <NavLink to="/patients" className="rounded-full border border-slate-700 bg-slate-950 px-3 py-1.5 text-xs font-medium text-slate-200">
            Manage
          </NavLink>
        </div>

        <div className="mt-5 overflow-hidden rounded-2xl border border-slate-800">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-slate-950 text-slate-400">
              <tr>
                <th className="px-4 py-3 font-medium">Patient</th>
                <th className="px-4 py-3 font-medium">Age</th>
                <th className="px-4 py-3 font-medium">Condition</th>
                <th className="px-4 py-3 font-medium">Risk</th>
              </tr>
            </thead>
            <tbody>
              {patients.map((patient) => (
                <tr key={patient.name} className="border-t border-slate-800 text-slate-200">
                  <td className="px-4 py-3 font-medium text-white">{patient.name}</td>
                  <td className="px-4 py-3">{patient.age}</td>
                  <td className="px-4 py-3">{patient.condition}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${patient.accent}`}>
                      {patient.risk}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </>
  )
}
