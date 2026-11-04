import { describe, expect, it } from 'vitest'
import {
  DEMO_DATA_NOTICE,
  IS_DEMO_DATA,
  appointments,
  bookingQueue,
  doctorStats,
  navItems,
  patients,
  prescriptions,
  schedule,
} from './demoData'

describe('demo data integrity (L-07 acceptance criteria)', () => {
  it('is explicitly flagged as synthetic demo data', () => {
    expect(IS_DEMO_DATA).toBe(true)
    expect(DEMO_DATA_NOTICE).toMatch(/synthetic demo data/i)
    expect(DEMO_DATA_NOTICE).toMatch(/not for clinical use/i)
  })

  it('keeps the original clinical demo values unchanged', () => {
    // Values must match the pre-refactor monolith exactly (audit F-13 rule).
    expect(prescriptions).toEqual([
      { patient: 'Olivia Green', medicine: 'Amlodipine', dosage: '5mg', note: 'Take after breakfast' },
      { patient: 'Daniel Scott', medicine: 'Metformin', dosage: '500mg', note: 'Twice daily' },
      { patient: 'Emma Wright', medicine: 'Sumatriptan', dosage: '50mg', note: 'As needed' },
    ])
  })

  it('preserves record counts and required fields', () => {
    expect(doctorStats).toHaveLength(4)
    expect(appointments).toHaveLength(4)
    expect(patients).toHaveLength(4)
    expect(schedule).toHaveLength(6)
    expect(bookingQueue).toHaveLength(3)
    expect(navItems).toHaveLength(5)

    for (const patient of patients) {
      expect(patient).toHaveProperty('name')
      expect(patient).toHaveProperty('age')
      expect(patient).toHaveProperty('condition')
      expect(patient).toHaveProperty('risk')
    }
    for (const item of appointments) {
      expect(item).toHaveProperty('time')
      expect(item).toHaveProperty('patient')
      expect(item).toHaveProperty('status')
    }
  })
})
