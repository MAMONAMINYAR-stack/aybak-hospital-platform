import DemoActionButton from '../components/DemoActionButton'
import { bookingQueue } from '../data/demoData'

/** L-03/L-04 (handoff/02-repair.md): appointments page; New Booking is an honest demo action. */
export default function AppointmentsPage() {
  return (
    <section className="mt-6 space-y-6">
      <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Appointments</p>
            <h3 className="mt-1 text-2xl font-bold text-white">Scheduling Overview</h3>
          </div>
          <DemoActionButton className="rounded-full bg-cyan-500 px-4 py-2 text-sm font-semibold text-slate-950 hover:bg-cyan-400">
            + New Booking
          </DemoActionButton>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        {bookingQueue.map((item) => (
          <div key={item.title} className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
            <div className="flex items-center justify-between">
              <p className="text-lg font-semibold text-white">{item.title}</p>
              <span className="rounded-full bg-sky-500/15 px-2 py-1 text-[10px] font-semibold text-sky-300">{item.status}</span>
            </div>
            <div className="mt-6 space-y-3 text-sm text-slate-300">
              <p><span className="text-slate-400">Patient:</span> {item.patient}</p>
              <p><span className="text-slate-400">Time:</span> {item.time}</p>
              <p><span className="text-slate-400">Location:</span> {item.room}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
