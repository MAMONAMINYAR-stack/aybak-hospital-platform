import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { DemoAuthProvider, useDemoAuth } from './auth/DemoAuthContext'
import ErrorBoundary from './components/ErrorBoundary'
import ProtectedLayout from './components/ProtectedLayout'
import AppointmentsPage from './pages/AppointmentsPage'
import DashboardPage from './pages/DashboardPage'
import LoginPage from './pages/LoginPage'
import PatientsPage from './pages/PatientsPage'
import PrescriptionsPage from './pages/PrescriptionsPage'
import SettingsPage from './pages/SettingsPage'

/**
 * L-03 (handoff/02-repair.md): App is now routing + providers only.
 * Routes and behavior are preserved from the original monolith.
 * DEMO auth only — see handoff/01-audit.md F-02 (real auth needs approval).
 */
function AppRoutes() {
  const { isLoggedIn } = useDemoAuth()

  return (
    <Routes>
      <Route path="/login" element={isLoggedIn ? <Navigate to="/" replace /> : <LoginPage />} />

      <Route element={isLoggedIn ? <ProtectedLayout /> : <Navigate to="/login" replace />}>
        <Route index element={<DashboardPage />} />
        <Route path="/appointments" element={<AppointmentsPage />} />
        <Route path="/patients" element={<PatientsPage />} />
        <Route path="/prescriptions" element={<PrescriptionsPage />} />
        <Route path="/settings" element={<SettingsPage />} />
      </Route>

      <Route path="*" element={<Navigate to={isLoggedIn ? '/' : '/login'} replace />} />
    </Routes>
  )
}

function App() {
  return (
    <ErrorBoundary>
      <DemoAuthProvider>
        <BrowserRouter>
          <AppRoutes />
        </BrowserRouter>
      </DemoAuthProvider>
    </ErrorBoundary>
  )
}

export default App
