import type * as monaco from "monaco-editor";

export function buildRiscvLanguageDef(
  keywords: string[],
  registers: string[],
  csrs: string[] = [],
): monaco.languages.IMonarchLanguage {
  return <monaco.languages.IMonarchLanguage>{
    ignoreCase: false,

    keywords,
    registers,
    csrs,

    tokenizer: {
      root: [
        // Directives
        [/\.[a-zA-Z_]\w*/, "custom-directive"],

        // Identifiers (could be keywords, registers or CSR names)
        [
          /[a-zA-Z_]\w*/,
          {
            cases: {
              "@keywords": "custom-keyword",
              "@registers": "custom-register",
              "@csrs": "custom-csr",
              "@default": "identifier",
            },
          },
        ],

        // Comments
        [/#.*/, "custom-comment"],
        [/\/\/.*/, "custom-comment"],
        [/\/\*/, "custom-comment", "@blockComment"],

        // Numbers
        [/\b0[xX][0-9a-fA-F]+\b/, "custom-number"],
        [/\b-?\d+\b/, "custom-number"],

        // Strings
        [/"([^"\\]|\\.)*$/, "string.invalid"],
        [
          /"/,
          { token: "custom-string.quote", bracket: "@open", next: "@string" },
        ],
      ],

      blockComment: [
        [/[^/*]+/, "custom-comment"],
        [/\*\//, "custom-comment", "@pop"],
        [/[/*]/, "custom-comment"],
      ],

      string: [
        [/[^\\"]+/, "custom-string"],
        [/\\./, "custom-string.escape"],
        [
          /"/,
          { token: "custom-string.quote", bracket: "@close", next: "@pop" },
        ],
      ],
    },
  };
}

export const riscvLanguageConfig: monaco.languages.LanguageConfiguration = {
  comments: {
    lineComment: "#",
    blockComment: ["/*", "*/"],
  },
  autoClosingPairs: [
    { open: "/*", close: "*/" },
    { open: '"', close: '"' },
    { open: "(", close: ")" },
  ],
};
