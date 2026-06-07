export type OpenFile = {
  id: string;
  name: string;
  path: string | null;
  content: string;
  savedContent: string;
};

export type SourceMap = [number, number][];
export type DisasmMap = [number, string][];
export type CodeMap = [number, number][];

export type TextRow = {
  addr: number;
  code: number;
  basic: string;
  line: number;
  source: string | null;
};

export type IconName =
  | "play"
  | "pause"
  | "stepFwd"
  | "stepBack"
  | "rewind"
  | "search"
  | "trash"
  | "term"
  | "logs"
  | "lock"
  | "pencil"
  | "build"
  | "folder"
  | "save"
  | "sliders"
  | "panels"
  | "chip"
  | "sun"
  | "moon"
  | "keyboard"
  | "memory"
  | "book"
  | "chevron"
  | "check"
  | "reset"
  | "min"
  | "max"
  | "restore"
  | "close"
  | "bug"
  | "info";
