import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import DemoActionButton from './DemoActionButton'

describe('DemoActionButton (L-04 acceptance criteria)', () => {
  it('shows a visible demo notice when clicked', async () => {
    const user = userEvent.setup()
    render(<DemoActionButton>Export</DemoActionButton>)

    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Export' }))

    expect(screen.getByRole('status')).toHaveTextContent(/demo only — no data was changed/i)
  })

  it('hides the notice again after a short delay', () => {
    vi.useFakeTimers()
    render(<DemoActionButton>Export</DemoActionButton>)

    fireEvent.click(screen.getByRole('button', { name: 'Export' }))
    expect(screen.getByRole('status')).toBeInTheDocument()

    act(() => {
      vi.advanceTimersByTime(3100)
    })
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    vi.useRealTimers()
  })
})
