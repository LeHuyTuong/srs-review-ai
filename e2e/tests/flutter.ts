import { expect, type Page } from '@playwright/test';

/**
 * Flutter web paints on a canvas; Playwright only sees widgets once the
 * semantics tree is on. Flutter puts an off-screen "Enable accessibility"
 * placeholder in the DOM — clicking it builds `flt-semantics` nodes with roles
 * and labels, which getByRole/getByText can then find.
 */
export async function openFlutterApp(page: Page, url = '/'): Promise<string[]> {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });

  await page.goto(url);
  await page.locator('flutter-view, flt-glass-pane').first().waitFor({ state: 'attached', timeout: 60_000 });
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({ state: 'attached', timeout: 60_000 });
  await placeholder.evaluate((el: HTMLElement) => el.click());
  await expect(page.locator('flt-semantics').first()).toBeAttached();
  return errors;
}

/** Uncaught Dart errors are fatal for a smoke test; network noise is not. */
export function dartErrors(errors: string[]): string[] {
  return errors.filter((e) => /DartError|Bad state|Unhandled Exception|TypeError/.test(e));
}
