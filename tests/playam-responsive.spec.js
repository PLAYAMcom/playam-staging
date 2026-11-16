const { test, expect } = require('@playwright/test');

const viewports = [
  { name: 'small phone', width: 360, height: 800, mobile: true },
  { name: 'standard phone', width: 390, height: 844, mobile: true },
  { name: 'tablet', width: 768, height: 1024, mobile: false },
  { name: 'desktop', width: 1440, height: 900, mobile: false },
];

async function expectNoHorizontalOverflow(page, label) {
  const dimensions = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    document: document.documentElement.scrollWidth,
    body: document.body.scrollWidth,
  }));
  expect(dimensions.document, label + ' document overflow: ' + JSON.stringify(dimensions)).toBeLessThanOrEqual(dimensions.viewport + 1);
  expect(dimensions.body, label + ' body overflow: ' + JSON.stringify(dimensions)).toBeLessThanOrEqual(dimensions.viewport + 1);
}

test.describe('PLAYAM responsive Staging browser checks', () => {
  for (const viewport of viewports) {
    test('main app fits and primary navigation works at ' + viewport.name, async ({ page }) => {
      await page.setViewportSize({ width: viewport.width, height: viewport.height });
      const pageErrors = [];
      page.on('pageerror', error => pageErrors.push(error.message));

      await page.goto('/index.html', { waitUntil: 'domcontentloaded' });
      await expect(page).toHaveTitle(/PLAYAM/i);
      await expect(page.locator('#authScreen')).toBeVisible();
      await expect(page.locator('#email')).toBeVisible();
      await expect(page.locator('#password')).toBeVisible();
      await expectNoHorizontalOverflow(page, viewport.name + ' auth');

      // Reveal the authenticated shell without creating an account or contacting
      // authentication/payment services. This tests layout and local navigation only.
      await page.evaluate(() => {
        document.querySelector('#authScreen').classList.add('hidden');
        document.querySelector('#app').classList.remove('hidden');
      });

      if (viewport.mobile) {
        await expect(page.locator('#bottomNav')).toBeVisible();
        await page.locator('[data-bottom-nav="navGames"]').click();
      } else {
        await expect(page.locator('#bottomNav')).toBeHidden();
        await page.locator('#navGamesDesktop').click();
      }
      await expect(page.locator('#gamesScreen')).toBeVisible();
      await expect(page.locator('#playamCatalogueGrid')).toBeVisible();
      await expectNoHorizontalOverflow(page, viewport.name + ' games');
      expect(pageErrors, 'uncaught browser errors at ' + viewport.name).toEqual([]);
    });
  }

  const surfaces = [
    { path: '/site/admin-playam-staging.html', title: /PLAYAM Staging Admin/i, selector: '#login' },
    { path: '/site/flow.html', title: /PLAYAM Flow/i, selector: '#auth' },
    { path: '/site/game-catalogue.html', title: /PLAYAM Game Catalogue/i, selector: 'body' },
  ];

  for (const surface of surfaces) {
    for (const viewport of [
      { name: 'phone', width: 360, height: 800 },
      { name: 'tablet', width: 768, height: 1024 },
      { name: 'desktop', width: 1440, height: 900 },
    ]) {
      test(surface.path + ' fits ' + viewport.name, async ({ page }) => {
        await page.setViewportSize({ width: viewport.width, height: viewport.height });
        await page.goto(surface.path, { waitUntil: 'domcontentloaded' });
        await expect(page).toHaveTitle(surface.title);
        await expect(page.locator(surface.selector)).toBeVisible();
        await expectNoHorizontalOverflow(page, surface.path + ' ' + viewport.name);
      });
    }
  }
});
