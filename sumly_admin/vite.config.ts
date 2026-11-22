import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

function resolveApiProxy(rawTarget: string) {
  const fallback = 'http://127.0.0.1:8080';
  const trimmed = rawTarget.trim() || fallback;

  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    parsed = new URL(fallback);
  }

  // Normalize optional deployment prefix (e.g. "/sumly" for https://oryjk.cn/sumly,
  // or "" for local Go server http://127.0.0.1:8080).
  const basePath = parsed.pathname.replace(/\/+$/, '').replace(/\/api(?:\/v1)?$/, '');

  return {
    target: parsed.origin,
    changeOrigin: true,
    rewrite: (path: string) => `${basePath}${path.replace(/^\/sumly/, '')}`,
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const apiTarget = env.VITE_API_TARGET || 'http://127.0.0.1:8080';
  const proxy = {
    '/sumly/api': resolveApiProxy(apiTarget),
  };

  return {
    base: '/sumly/admin/',
    plugins: [react(), tailwindcss()],
    server: {
      port: 5173,
      host: true,
      proxy,
    },
    preview: {
      port: 4173,
      host: true,
      proxy,
    },
  };
});
