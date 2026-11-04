import { useEffect, useRef, useState } from 'react'

/**
 * L-04 (handoff/02-repair.md): honest feedback for demo-only actions
 * (audit F-07). Clicking shows a visible notice instead of silently doing
 * nothing. No data is created or modified by these buttons.
 */
export default function DemoActionButton({ children, className = '', label }) {
  const [showNotice, setShowNotice] = useState(false)
  const timerRef = useRef(null)

  useEffect(() => () => clearTimeout(timerRef.current), [])

  const handleClick = () => {
    setShowNotice(true)
    clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => setShowNotice(false), 3000)
  }

  return (
    <>
      <button
        type="button"
        onClick={handleClick}
        className={className}
        aria-label={label}
        title="Demo only — this action is not implemented"
      >
        {children}
      </button>
      {showNotice && (
        <span
          role="status"
          className="rounded-full border border-amber-500/30 bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-200"
        >
          Demo only — no data was changed.
        </span>
      )}
    </>
  )
}
