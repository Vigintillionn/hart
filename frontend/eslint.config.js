import js from "@eslint/js";
import ts from "typescript-eslint";
import svelte from "eslint-plugin-svelte";
import globals from "globals";
import prettier from "eslint-config-prettier";
import svelteConfig from "./svelte.config.js";

export default [
  js.configs.recommended,
  ...ts.configs.recommended,
  ...svelte.configs.recommended,
  prettier,
  ...svelte.configs.prettier,
  {
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
    },
    rules: {
      // allow intentionally-unused args/vars when prefixed with `_`
      "@typescript-eslint/no-unused-vars": [
        "warn",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
          caughtErrors: "none",
        },
      ],
      // We use plain Map/Set: either non-reactive
      // imperative caches (e.g. Monaco models) or reassignment-based
      // reactivity (createChangeFlasher reassigns a new Set, which IS
      // reactive). SvelteMap/SvelteSet are only needed for mutation-based
      // reactivity, so this rule fires only false positives here.
      "svelte/prefer-svelte-reactivity": "off",
    },
  },
  {
    // let the Svelte parser hand <script lang="ts"> blocks to the TS parser
    files: ["**/*.svelte", "**/*.svelte.ts"],
    languageOptions: {
      parserOptions: {
        parser: ts.parser,
        extraFileExtensions: [".svelte"],
        svelteConfig,
      },
    },
  },
  {
    ignores: [
      "build/",
      ".svelte-kit/",
      "src-tauri/",
      "src/bindings/",
      "node_modules/",
      "static/",
    ],
  },
];
