import DemoActionButton from '../components/DemoActionButton'
import { DEMO_DATA_NOTICE, prescriptions } from '../data/demoData'

/**
 * L-03/L-04/L-07 (handoff/02-repair.md): prescriptions page.
 * Clinical values (medicines/dosages) are UNCHANGED demo data — any real
 * prescription logic is a needs-approval item (handoff/01-audit.md).
 */
export default function PrescriptionsPage() {
  return (
    <section className="mt-6 rounded-3xl border border-slate-800 bg-slate-900 p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Prescriptions</p>
          <h3 className="mt-1 text-2xl font-bold text-white">Medication Orders</h3>
        </div>
        <DemoActionButton className="rounded-full bg-cyan-500 px-4 py-2 text-sm font-semibold text-slate-950 hover:bg-cyan-400">
          + New Prescription
        </DemoActionButton>
      </div>

      <p className="mt-3 text-xs font-medium text-amber-200/90">{DEMO_DATA_NOTICE}</p>

      <div className="mt-5 space-y-4">
        {prescriptions.map((item) => (
          <div key={item.patient} className="rounded-2xl border border-slate-800 bg-slate-950 p-4">
            <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="text-lg font-semibold text-white">{item.patient}</p>
                <p className="text-sm text-slate-400">{item.medicine}</p>
              </div>
              <span className="rounded-full bg-emerald-500/15 px-2.5 py-1 text-xs font-semibold text-emerald-300">
                {item.dosage}
              </span>
            </div>
            <p className="mt-3 text-sm text-slate-300">{item.note}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
