import DemoActionButton from '../components/DemoActionButton'
import { DEMO_DATA_NOTICE, patients } from '../data/demoData'

/** L-03/L-04/L-07 (handoff/02-repair.md): patients page; demo-labeled data and actions. */
export default function PatientsPage() {
  return (
    <section className="mt-6 rounded-3xl border border-slate-800 bg-slate-900 p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Patients</p>
          <h3 className="mt-1 text-2xl font-bold text-white">Patient Registry</h3>
        </div>
        <DemoActionButton className="rounded-full border border-slate-700 bg-slate-950 px-4 py-2 text-sm font-medium text-slate-200 hover:border-slate-500">
          Add Patient
        </DemoActionButton>
      </div>

      <p className="mt-3 text-xs font-medium text-amber-200/90">{DEMO_DATA_NOTICE}</p>

      <div className="mt-5 overflow-hidden rounded-2xl border border-slate-800">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-slate-950 text-slate-400">
            <tr>
              <th className="px-4 py-3 font-medium">Patient</th>
              <th className="px-4 py-3 font-medium">Age</th>
              <th className="px-4 py-3 font-medium">Condition</th>
              <th className="px-4 py-3 font-medium">Risk</th>
              <th className="px-4 py-3 font-medium">Status</th>
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
                <td className="px-4 py-3 text-cyan-300">Active</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}
