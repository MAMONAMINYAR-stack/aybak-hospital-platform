import { useState } from 'react'
import {
  BrowserRouter,
  NavLink,
  Navigate,
  Outlet,
  Route,
  Routes,
} from 'react-router-dom'

const doctorStats = [
  { label: 'Appointments', value: '148', trend: '+12%' },
  { label: 'Patients', value: '82', trend: '+8%' },
  { label: 'Earnings', value: '$12.4K', trend: '+15%' },
  { label: 'Satisfaction', value: '96%', trend: '+3%' },
]

const appointments = [
  { time: '09:00 AM', patient: 'Sophia Johnson', issue: 'General Checkup', status: 'Confirmed', color: 'bg-emerald-500/15 text-emerald-300' },
  { time: '10:30 AM', patient: 'James Lee', issue: 'Cardiology Review', status: 'Waiting', color: 'bg-amber-500/15 text-amber-300' },
  { time: '12:00 PM', patient: 'Ava Martin', issue: 'Dermatology', status: 'Consulting', color: 'bg-sky-500/15 text-sky-300' },
  { time: '02:15 PM', patient: 'Noah Patel', issue: 'Follow-up', status: 'Confirmed', color: 'bg-emerald-500/15 text-emerald-300' },
]

const patients = [
  { name: 'Olivia Green', age: 32, condition: 'Hypertension', risk: 'Low', accent: 'bg-emerald-500/15 text-emerald-300' },
  { name: 'Daniel Scott', age: 47, condition: 'Diabetes', risk: 'Medium', accent: 'bg-amber-500/15 text-amber-300' },
  { name: 'Emma Wright', age: 28, condition: 'Migraine', risk: 'Low', accent: 'bg-sky-500/15 text-sky-300' },
  { name: 'Lucas Hall', age: 56, condition: 'Post-op Recovery', risk: 'High', accent: 'bg-rose-500/15 text-rose-300' },
]

const schedule = [
  { day: 'Mon', active: false },
  { day: 'Tue', active: true },
  { day: 'Wed', active: false },
  { day: 'Thu', active: false },
  { day: 'Fri', active: false },
  { day: 'Sat', active: false },
]

const bookingQueue = [
  { title: 'MRI Scan', patient: 'Liam Chen', time: '09:30 AM', room: 'Room 12', status: 'Ready' },
  { title: 'Lab Review', patient: 'Mila Davis', time: '11:15 AM', room: 'Lab 3', status: 'Pending' },
  { title: 'Follow-up Visit', patient: 'Ethan Brooks', time: '02:00 PM', room: 'Ward B', status: 'Scheduled' },
]

const prescriptions = [
  { patient: 'Olivia Green', medicine: 'Amlodipine', dosage: '5mg', note: 'Take after breakfast' },
  { patient: 'Daniel Scott', medicine: 'Metformin', dosage: '500mg', note: 'Twice daily' },
  { patient: 'Emma Wright', medicine: 'Sumatriptan', dosage: '50mg', note: 'As needed' },
]

const navItems = [
  { label: 'Dashboard', path: '/' },
  { label: 'Appointments', path: '/appointments' },
  { label: 'Patients', path: '/patients' },
  { label: 'Prescriptions', path: '/prescriptions' },
  { label: 'Settings', path: '/settings' },
]

function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false)
  const [form, setForm] = useState({ email: 'doctor@aybak.com', password: 'admin123' })

  const handleLogin = (event) => {
    event.preventDefault()
    if (form.email && form.password) {
      setIsLoggedIn(true)
    }
  }

  const handleLogout = () => {
    setIsLoggedIn(false)
  }

  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={
            isLoggedIn ? <Navigate to="/" replace /> : <LoginPage form={form} setForm={setForm} onLogin={handleLogin} />
          }
        />

        <Route
          element={isLoggedIn ? <ProtectedLayout onLogout={handleLogout} /> : <Navigate to="/login" replace />}
        >
          <Route index element={<DoctorDashboardPage />} />
          <Route path="/appointments" element={<AppointmentsPage />} />
          <Route path="/patients" element={<PatientsPage />} />
          <Route path="/prescriptions" element={<PrescriptionsPage />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Route>

        <Route path="*" element={<Navigate to={isLoggedIn ? '/' : '/login'} replace />} />
      </Routes>
    </BrowserRouter>
  )
}

function ProtectedLayout({ onLogout }) {
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

          <nav className="mt-8 space-y-2">
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
                <button className="rounded-full border border-slate-700 bg-slate-950 px-4 py-2 text-sm font-medium text-slate-200 hover:border-slate-500">
                  Export
                </button>
                <button
                  type="button"
                  onClick={onLogout}
                  className="rounded-full bg-slate-800 px-4 py-2 text-sm font-semibold text-slate-100 hover:bg-slate-700"
                >
                  Log out
                </button>
              </div>
            </div>
          </header>

          <Outlet />
        </div>
      </div>
    </main>
  )
}

function LoginPage({ form, setForm, onLogin }) {
  const handleChange = (event) => {
    const { name, value } = event.target
    setForm((current) => ({ ...current, [name]: value }))
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

            <form onSubmit={onLogin} className="space-y-5">
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
                  className="w-full rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition focus:border-cyan-500"
                  placeholder="••••••••"
                />
              </div>

              <div className="flex items-center justify-between text-sm text-slate-400">
                <label className="flex items-center gap-2">
                  <input type="checkbox" className="h-4 w-4 rounded border-slate-600 bg-slate-950" />
                  Remember me
                </label>
                <button type="button" className="text-cyan-300 hover:text-cyan-200">
                  Forgot password?
                </button>
              </div>

              <button
                type="submit"
                className="w-full rounded-2xl bg-cyan-500 px-4 py-3 text-base font-semibold text-slate-950 shadow-lg shadow-cyan-500/30 transition hover:bg-cyan-400"
              >
                Sign in
              </button>
            </form>

            <div className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/60 p-4 text-sm text-slate-400">
              Demo credentials: <span className="font-medium text-slate-200">doctor@aybak.com</span> / <span className="font-medium text-slate-200">admin123</span>
            </div>
          </div>
        </div>
      </div>
    </main>
  )
}

function DoctorDashboardPage() {
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
                <span className="text-xs text-slate-400">{schedule[index].day}</span>
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

function AppointmentsPage() {
  return (
    <section className="mt-6 space-y-6">
      <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Appointments</p>
            <h3 className="mt-1 text-2xl font-bold text-white">Scheduling Overview</h3>
          </div>
          <button className="rounded-full bg-cyan-500 px-4 py-2 text-sm font-semibold text-slate-950 hover:bg-cyan-400">
            + New Booking
          </button>
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

function PatientsPage() {
  return (
    <section className="mt-6 rounded-3xl border border-slate-800 bg-slate-900 p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Patients</p>
          <h3 className="mt-1 text-2xl font-bold text-white">Patient Registry</h3>
        </div>
        <button className="rounded-full border border-slate-700 bg-slate-950 px-4 py-2 text-sm font-medium text-slate-200 hover:border-slate-500">
          Add Patient
        </button>
      </div>

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

function PrescriptionsPage() {
  return (
    <section className="mt-6 rounded-3xl border border-slate-800 bg-slate-900 p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm uppercase tracking-[0.2em] text-slate-400">Prescriptions</p>
          <h3 className="mt-1 text-2xl font-bold text-white">Medication Orders</h3>
        </div>
        <button className="rounded-full bg-cyan-500 px-4 py-2 text-sm font-semibold text-slate-950 hover:bg-cyan-400">
          + New Prescription
        </button>
      </div>

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

function SettingsPage() {
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
          {['Email alerts', 'SMS reminders', 'Appointment confirmations', 'Weekly reports'].map((item) => (
            <label key={item} className="flex items-center justify-between rounded-2xl bg-slate-950 p-3">
              <span>{item}</span>
              <input type="checkbox" defaultChecked className="h-4 w-4 rounded border-slate-600 bg-slate-950" />
            </label>
          ))}
        </div>
      </div>
    </section>
  )
}

export default App
