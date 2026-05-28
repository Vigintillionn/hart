
export type OpenFile = {
  id: string;
  name: string;
  path: string | null;
  content: string;
};

export type SourceMap = [number, number][];
