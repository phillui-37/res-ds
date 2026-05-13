import { defineConfig } from "vite";

export default defineConfig({
  build: {
    target: "es2020",
    lib: {
      entry: "src/ResDs.res.mjs",
      name: "ResDs",
      formats: ["es"],
      fileName: "res-ds",
    },
    sourcemap: true,
  },
  test: {
    include: ["tests/**/*_test.res.mjs"],
    environment: "node",
    globals: true,
  },
});
