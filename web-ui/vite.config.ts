import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"
import path from "node:path"

// Plain Vite config. The Figma Make platform plugins that came with the export
// were dropped: they only serve Figma's own preview and need its .figma/ files.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    // The API lives on another port in development, and the session is an
    // `HttpOnly` cookie — so the browser must see ONE origin or the cookie is
    // never sent. A proxy (not CORS) is the fix: it also means production,
    // where both are served from one origin, needs no `VITE_API_BASE` at all.
    proxy: {
      "/api": {
        target: process.env.SRS_API_URL ?? "http://127.0.0.1:8000",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ""),
      },
    },
  },
})
