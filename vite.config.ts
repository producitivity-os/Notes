import path from "path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import type { Plugin } from "vite";

const host = process.env.TAURI_DEV_HOST;
const disabledSpeechWorkerModule = "\0notes-mathjax-sre-lab-disabled";

const disableUnusedMathJaxSpeechWorker = (): Plugin => ({
  name: "notes-disable-unused-mathjax-speech-worker",
  enforce: "pre",
  resolveId(source, importer) {
    if (
      source === "./sre-lab.js" &&
      importer?.includes("/mathjax/sre/speech-worker.js")
    ) {
      return disabledSpeechWorkerModule;
    }
    return null;
  },
  load(id) {
    return id === disabledSpeechWorkerModule ? "export default {};" : null;
  },
});

export default defineConfig({
  plugins: [disableUnusedMathJaxSpeechWorker(), react(), tailwindcss()],
  clearScreen: false,
  server: {
    port: 1440,
    strictPort: true,
    host: host || false,
    hmr: host ? { protocol: "ws", host, port: 1441 } : undefined,
    fs: { allow: [path.resolve(import.meta.dirname, "../..")] },
    watch: { ignored: ["**/src-tauri/**"] },
  },
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "./src"),
      "@notes/plugin-api": path.resolve(
        import.meta.dirname,
        "./src/plugins/plugin-api.tsx",
      ),
    },
  },
});
