import { Component } from 'react'

/**
 * L-05 (handoff/02-repair.md): app-level error boundary so a render error
 * shows a readable fallback instead of a blank page (audit F-08).
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError() {
    return { hasError: true }
  }

  componentDidCatch(error, info) {
    // Log to console only — no external telemetry, no patient data leaves the app.
    console.error('AYBAK demo app crashed:', error, info)
  }

  render() {
    if (this.state.hasError) {
      return (
        <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 text-slate-100">
          <div className="max-w-md rounded-3xl border border-rose-500/30 bg-slate-900 p-8 text-center">
            <h1 className="text-2xl font-bold text-white">Something went wrong</h1>
            <p className="mt-3 text-sm text-slate-400">
              An unexpected error occurred in this demo. Reload the page to continue.
            </p>
            <button
              type="button"
              onClick={() => window.location.reload()}
              className="mt-6 rounded-full bg-cyan-500 px-5 py-2 text-sm font-semibold text-slate-950 hover:bg-cyan-400"
            >
              Reload
            </button>
          </div>
        </main>
      )
    }

    return this.props.children
  }
}
