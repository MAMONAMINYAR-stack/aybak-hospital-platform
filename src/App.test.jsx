import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import App from './App'

async function login(user) {
  await user.type(screen.getByLabelText(/email address/i), 'demo@example.com')
  await user.type(screen.getByLabelText(/^password$/i), 'demo-password')
  await user.click(screen.getByRole('button', { name: /sign in/i }))
}

describe('App routing and demo login flow (L-03 acceptance criteria)', () => {
  it('redirects unauthenticated visitors to the login page with empty fields', () => {
    window.history.pushState({}, '', '/patients')
    render(<App />)

    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument()
    expect(screen.getByLabelText(/email address/i)).toHaveValue('')
    expect(screen.getByLabelText(/^password$/i)).toHaveValue('')
    expect(screen.queryByText('Patient Registry')).not.toBeInTheDocument()
  })

  it('never displays hardcoded credentials', () => {
    render(<App />)
    expect(screen.queryByText(/admin123/)).not.toBeInTheDocument()
    expect(screen.getByText(/demo mode:/i)).toBeInTheDocument()
  })

  it('does not sign in with empty credentials', async () => {
    const user = userEvent.setup()
    render(<App />)
    await user.click(screen.getByRole('button', { name: /sign in/i }))
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument()
    expect(screen.queryByText('AYBAK Hospital')).not.toBeInTheDocument()
  })

  it('signs in with any non-empty credentials and shows the dashboard with DEMO banner', async () => {
    const user = userEvent.setup()
    render(<App />)
    await login(user)

    expect(screen.getByText('AYBAK Hospital')).toBeInTheDocument()
    expect(screen.getByText(/DEMO — synthetic data only/i)).toBeInTheDocument()
    expect(screen.getByText('Today’s Schedule')).toBeInTheDocument()
  })

  it('navigates between all pages via the accessible nav', async () => {
    const user = userEvent.setup()
    render(<App />)
    await login(user)

    const nav = screen.getByRole('navigation', { name: /main navigation/i })

    await user.click(within(nav).getByRole('link', { name: /appointments/i }))
    expect(screen.getByText('Scheduling Overview')).toBeInTheDocument()

    await user.click(within(nav).getByRole('link', { name: /patients/i }))
    expect(screen.getByText('Patient Registry')).toBeInTheDocument()

    await user.click(within(nav).getByRole('link', { name: /prescriptions/i }))
    expect(screen.getByText('Medication Orders')).toBeInTheDocument()
    expect(screen.getByText(/synthetic demo data — not real patient records/i)).toBeInTheDocument()

    await user.click(within(nav).getByRole('link', { name: /settings/i }))
    expect(screen.getByText('Notifications')).toBeInTheDocument()

    await user.click(within(nav).getByRole('link', { name: /dashboard/i }))
    expect(screen.getByText('Today’s Schedule')).toBeInTheDocument()
  })

  it('logs out and protects the inner pages again', async () => {
    const user = userEvent.setup()
    render(<App />)
    await login(user)

    await user.click(screen.getByRole('button', { name: /log out/i }))
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument()
    expect(screen.queryByText('AYBAK Hospital')).not.toBeInTheDocument()
  })

  it('redirects unknown routes to login when logged out', () => {
    window.history.pushState({}, '', '/no-such-page')
    render(<App />)
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument()
  })
})
