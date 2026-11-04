/**
 * SYNTHETIC DEMO DATA — not real patient data.
 * داده ساختگی نمایشی — داده واقعی بیمار نیست.
 *
 * L-07 (handoff/02-repair.md): extracted verbatim from the former monolithic
 * src/App.jsx (audit F-13). Clinical values (medicines, dosages, risk levels)
 * are intentionally UNCHANGED — modifying them requires approval.
 */
export const IS_DEMO_DATA = true

export const DEMO_DATA_NOTICE =
  'Synthetic demo data — not real patient records. Not for clinical use.'

export const doctorStats = [
  { label: 'Appointments', value: '148', trend: '+12%' },
  { label: 'Patients', value: '82', trend: '+8%' },
  { label: 'Earnings', value: '$12.4K', trend: '+15%' },
  { label: 'Satisfaction', value: '96%', trend: '+3%' },
]

export const appointments = [
  { time: '09:00 AM', patient: 'Sophia Johnson', issue: 'General Checkup', status: 'Confirmed', color: 'bg-emerald-500/15 text-emerald-300' },
  { time: '10:30 AM', patient: 'James Lee', issue: 'Cardiology Review', status: 'Waiting', color: 'bg-amber-500/15 text-amber-300' },
  { time: '12:00 PM', patient: 'Ava Martin', issue: 'Dermatology', status: 'Consulting', color: 'bg-sky-500/15 text-sky-300' },
  { time: '02:15 PM', patient: 'Noah Patel', issue: 'Follow-up', status: 'Confirmed', color: 'bg-emerald-500/15 text-emerald-300' },
]

export const patients = [
  { name: 'Olivia Green', age: 32, condition: 'Hypertension', risk: 'Low', accent: 'bg-emerald-500/15 text-emerald-300' },
  { name: 'Daniel Scott', age: 47, condition: 'Diabetes', risk: 'Medium', accent: 'bg-amber-500/15 text-amber-300' },
  { name: 'Emma Wright', age: 28, condition: 'Migraine', risk: 'Low', accent: 'bg-sky-500/15 text-sky-300' },
  { name: 'Lucas Hall', age: 56, condition: 'Post-op Recovery', risk: 'High', accent: 'bg-rose-500/15 text-rose-300' },
]

export const schedule = [
  { day: 'Mon', active: false },
  { day: 'Tue', active: true },
  { day: 'Wed', active: false },
  { day: 'Thu', active: false },
  { day: 'Fri', active: false },
  { day: 'Sat', active: false },
]

export const bookingQueue = [
  { title: 'MRI Scan', patient: 'Liam Chen', time: '09:30 AM', room: 'Room 12', status: 'Ready' },
  { title: 'Lab Review', patient: 'Mila Davis', time: '11:15 AM', room: 'Lab 3', status: 'Pending' },
  { title: 'Follow-up Visit', patient: 'Ethan Brooks', time: '02:00 PM', room: 'Ward B', status: 'Scheduled' },
]

export const prescriptions = [
  { patient: 'Olivia Green', medicine: 'Amlodipine', dosage: '5mg', note: 'Take after breakfast' },
  { patient: 'Daniel Scott', medicine: 'Metformin', dosage: '500mg', note: 'Twice daily' },
  { patient: 'Emma Wright', medicine: 'Sumatriptan', dosage: '50mg', note: 'As needed' },
]

export const navItems = [
  { label: 'Dashboard', path: '/' },
  { label: 'Appointments', path: '/appointments' },
  { label: 'Patients', path: '/patients' },
  { label: 'Prescriptions', path: '/prescriptions' },
  { label: 'Settings', path: '/settings' },
]
