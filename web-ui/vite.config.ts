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
  server: { host: "127.0.0.1", port: 5173 },
})
