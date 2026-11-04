import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // F-10 (handoff/01-audit.md): allow the Arena preview proxy host in dev/preview.
  // Dev-only convenience; has no effect on the production build.
  server: {
    allowedHosts: ['.e2b.app'],
  },
  preview: {
    allowedHosts: ['.e2b.app'],
  },
  // L-01 (handoff/02-repair.md): Vitest configuration.
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.js',
    css: false,
  },
})
