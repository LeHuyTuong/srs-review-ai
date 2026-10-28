// Chỉ chạy bản sao để Vite không ghi cache vào source React chỉ đọc.
import { createServer } from 'file:///D:/UI%20AI%20Review/node_modules/vite/dist/node/index.js';
import react from 'file:///D:/UI%20AI%20Review/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from 'file:///D:/UI%20AI%20Review/node_modules/@tailwindcss/vite/dist/index.mjs';
import path from 'node:path';

const root = path.resolve('.local/react-reference');
const server = await createServer({
  configFile: false,
  root,
  cacheDir: path.resolve('.local/vite-cache'),
  plugins: [react(), tailwind()],
  resolve: { alias: { '@': path.join(root, 'src') } },
  server: { host: '127.0.0.1', port: 4173, strictPort: true },
});
await server.listen();
server.printUrls();
