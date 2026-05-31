export type OpenFile = {
  id: string;
  name: string;
  path: string | null;
  content: string;
  savedContent: string;
};

export type SourceMap = [number, number][];
export type DisasmMap = [number, string][];

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
  | "min"
  | "max"
  | "restore"
  | "close";
