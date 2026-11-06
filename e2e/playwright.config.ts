import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

/**
 * E2E for the WEB builds of the three Flutter apps (Playwright cannot drive the
 * native Windows desktop app or the Android app — those stay on `flutter test`
 * and a device).
 *
 * Build first (from the repo root, keys come from the root .env):
 *   python tools/flutter_env.py desktop   build web
 *   python tools/flutter_env.py mobile    build web
 *   python tools/flutter_env.py admin_web build web
 *
 * Each build is served on the SAME port as its `web_dev_config.yaml`, because
 * the Firebase/OAuth origins are registered per port.
 */
const root = path.resolve(__dirname, '..');
const python = process.env.PYTHON ?? 'python';
const serverPython = path.join(root, 'server', '.venv', 'Scripts', 'python.exe');

const PORTS = { desktop: 54613, mobile: 54614, admin: 54615, api: 8000 } as const;

function staticServer(app: string, port: number) {
  return {
    command: `${python} -m http.server ${port} --bind 127.0.0.1 --directory "${path.join(root, app, 'build', 'web')}"`,
    url: `http://localhost:${port}/`,
    reuseExistingServer: true,
    timeout: 30_000,
  };
}

export default defineConfig({
  testDir: './tests',
  timeout: 120_000,
  expect: { timeout: 30_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    ...devices['Desktop Chrome'],
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    locale: 'vi-VN',
  },
  webServer: [
    {
      // FastAPI proxy: /assets (Cloudinary + Firestore) for the desktop upload test.
      command: `"${serverPython}" -m uvicorn app.main:app --host 127.0.0.1 --port ${PORTS.api}`,
      cwd: path.join(root, 'server'),
      url: `http://localhost:${PORTS.api}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
    },
    staticServer('desktop', PORTS.desktop),
    staticServer('mobile', PORTS.mobile),
    staticServer('admin_web', PORTS.admin),
  ],
  projects: [
    { name: 'desktop-web', testMatch: /desktop\/.*\.spec\.ts/, use: { baseURL: `http://localhost:${PORTS.desktop}` } },
    { name: 'mobile-web', testMatch: /mobile\/.*\.spec\.ts/, use: { baseURL: `http://localhost:${PORTS.mobile}` } },
    { name: 'admin-web', testMatch: /admin\/.*\.spec\.ts/, use: { baseURL: `http://localhost:${PORTS.admin}` } },
  ],
});
