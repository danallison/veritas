import { defineConfig } from '@playwright/test'

const PORT = 3099 // dedicated port for e2e tests, avoids conflicts

export default defineConfig({
  testDir: './e2e',
  use: {
    baseURL: `http://localhost:${PORT}`,
  },
  webServer: {
    command: `npx vite --port ${PORT}`,
    port: PORT,
    reuseExistingServer: true,
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
})
