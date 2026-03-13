import { test, expect } from '@playwright/test'

test.describe('Home page', () => {
  test('renders the home page with correct heading and cards', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'Veritas' })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Verify Output' })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Pools' })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Cache' })).toBeVisible()
  })

  test('shows "How it works" section', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByText('How it works')).toBeVisible()
    await expect(page.getByText('1. Submit')).toBeVisible()
    await expect(page.getByText('2. Validate')).toBeVisible()
    await expect(page.getByText('3. Verify')).toBeVisible()
  })

  test('shows Advanced section with links', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('link', { name: 'Create Ceremony' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Random Tools' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Verification Guide' })).toBeVisible()
  })
})

test.describe('Navigation bar', () => {
  test('has all nav links', async ({ page }) => {
    await page.goto('/')
    const nav = page.locator('nav')
    await expect(nav.getByRole('link', { name: 'Veritas' })).toBeVisible()
    await expect(nav.getByRole('link', { name: 'Verify' })).toBeVisible()
    await expect(nav.getByRole('link', { name: 'Pools' })).toBeVisible()
    await expect(nav.getByRole('link', { name: 'Cache' })).toBeVisible()
    await expect(nav.getByRole('link', { name: 'Advanced' })).toBeVisible()
  })

  test('Verify link navigates to /verify/new', async ({ page }) => {
    await page.goto('/')
    await page.locator('nav').getByRole('link', { name: 'Verify' }).click()
    await expect(page).toHaveURL('/verify/new')
    await expect(page.getByRole('heading', { name: 'Submit for Verification' })).toBeVisible()
  })

  test('Pools link navigates to /pools', async ({ page }) => {
    await page.goto('/')
    await page.locator('nav').getByRole('link', { name: 'Pools' }).click()
    await expect(page).toHaveURL('/pools')
    await expect(page.getByRole('heading', { name: 'Volunteer Pools' })).toBeVisible()
  })

  test('Cache link navigates to /cache', async ({ page }) => {
    await page.goto('/')
    await page.locator('nav').getByRole('link', { name: 'Cache' }).click()
    await expect(page).toHaveURL('/cache')
    await expect(page.getByRole('heading', { name: 'Verified Cache' })).toBeVisible()
  })

  test('Advanced link navigates to /advanced', async ({ page }) => {
    await page.goto('/')
    await page.locator('nav').getByRole('link', { name: 'Advanced' }).click()
    await expect(page).toHaveURL('/advanced')
    await expect(page.getByRole('heading', { name: 'Advanced' })).toBeVisible()
  })
})

test.describe('Verify page', () => {
  test('renders the submission form', async ({ page }) => {
    await page.goto('/verify/new')
    await expect(page.getByPlaceholder('UUID of the volunteer pool')).toBeVisible()
    await expect(page.getByPlaceholder('Verify: What is the capital')).toBeVisible()
    await expect(page.getByPlaceholder('sha256:abc123')).toBeVisible()
    await expect(page.getByText('Comparison Method')).toBeVisible()
    await expect(page.getByText('Validators')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Submit for Verification' })).toBeVisible()
  })

  test('pre-fills pool ID from query param', async ({ page }) => {
    await page.goto('/verify/new?pool=test-pool-123')
    await expect(page.getByPlaceholder('UUID of the volunteer pool')).toHaveValue('test-pool-123')
  })

  test('pool ID is empty without query param', async ({ page }) => {
    await page.goto('/verify/new')
    await expect(page.getByPlaceholder('UUID of the volunteer pool')).toHaveValue('')
  })
})

test.describe('Pools page', () => {
  test('renders the pools page with create button', async ({ page }) => {
    await page.goto('/pools')
    await expect(page.getByRole('heading', { name: 'Volunteer Pools' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Create Pool' })).toBeVisible()
  })

  test('toggles create pool form', async ({ page }) => {
    await page.goto('/pools')
    // Form should not be visible initially
    await expect(page.getByPlaceholder('Claude Sonnet Verification Pool')).not.toBeVisible()

    // Click Create Pool to show form
    await page.getByRole('button', { name: 'Create Pool' }).click()
    await expect(page.getByPlaceholder('Claude Sonnet Verification Pool')).toBeVisible()
    await expect(page.getByText('Task Type')).toBeVisible()

    // Click Cancel to hide form
    await page.getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByPlaceholder('Claude Sonnet Verification Pool')).not.toBeVisible()
  })
})

test.describe('Cache page', () => {
  test('renders the cache page with search', async ({ page }) => {
    await page.goto('/cache')
    await expect(page.getByRole('heading', { name: 'Verified Cache' })).toBeVisible()
    await expect(page.getByPlaceholder('Search by fingerprint')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Lookup' })).toBeVisible()
  })
})

test.describe('Advanced page', () => {
  test('renders the advanced index page with all links', async ({ page }) => {
    await page.goto('/advanced')
    await expect(page.getByRole('heading', { name: 'Advanced' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Create Ceremony' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Random Tools' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Verification Guide' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Pool Demo' })).toBeVisible()
  })

  test('Create Ceremony link navigates correctly', async ({ page }) => {
    await page.goto('/advanced')
    await page.getByRole('link', { name: 'Create Ceremony' }).click()
    await expect(page).toHaveURL('/advanced/ceremonies/new')
    await expect(page.getByRole('heading', { name: 'Create Ceremony' })).toBeVisible()
  })
})

test.describe('Home page card navigation', () => {
  test('Verify Output card navigates to /verify/new', async ({ page }) => {
    await page.goto('/')
    await page.getByRole('link', { name: /Verify Output/ }).click()
    await expect(page).toHaveURL('/verify/new')
  })

  test('Pools card navigates to /pools', async ({ page }) => {
    await page.goto('/')
    await page.getByRole('link', { name: /Pools/ }).first().click()
    await expect(page).toHaveURL('/pools')
  })

  test('Cache card navigates to /cache', async ({ page }) => {
    await page.goto('/')
    await page.getByRole('link', { name: /Cache/ }).first().click()
    await expect(page).toHaveURL('/cache')
  })
})

test.describe('404 page', () => {
  test('shows 404 for unknown routes', async ({ page }) => {
    await page.goto('/nonexistent-page')
    await expect(page.getByText('404')).toBeVisible()
    await expect(page.getByText('Page not found')).toBeVisible()
    await expect(page.getByRole('link', { name: 'Go home' })).toBeVisible()
  })
})

test.describe('Nav active states', () => {
  test('Verify nav link is active on /verify/new', async ({ page }) => {
    await page.goto('/verify/new')
    const verifyLink = page.locator('nav').getByRole('link', { name: 'Verify' })
    await expect(verifyLink).toHaveClass(/text-indigo-600/)
  })

  test('Pools nav link is active on /pools', async ({ page }) => {
    await page.goto('/pools')
    const poolsLink = page.locator('nav').getByRole('link', { name: 'Pools' })
    await expect(poolsLink).toHaveClass(/text-indigo-600/)
  })

  test('Cache nav link is active on /cache', async ({ page }) => {
    await page.goto('/cache')
    const cacheLink = page.locator('nav').getByRole('link', { name: 'Cache' })
    await expect(cacheLink).toHaveClass(/text-indigo-600/)
  })

  test('Advanced nav link is active on /advanced', async ({ page }) => {
    await page.goto('/advanced')
    const advancedLink = page.locator('nav').getByRole('link', { name: 'Advanced' })
    await expect(advancedLink).toHaveClass(/text-indigo-600/)
  })

  test('Advanced nav link is active on /advanced/ceremonies/new', async ({ page }) => {
    await page.goto('/advanced/ceremonies/new')
    const advancedLink = page.locator('nav').getByRole('link', { name: 'Advanced' })
    await expect(advancedLink).toHaveClass(/text-indigo-600/)
  })
})
