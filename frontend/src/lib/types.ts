type Handler = () => Promise<void> | void;

export type CpuHandlers = {
  handleLoadProgram: Handler;
  handleRun: Handler;
  handleStepFwd: Handler;
  handleStepBack: Handler;
  handleRewind: Handler;
  submitInput: (input: string) => void;
};

export type FileHandlers = {
  handleOpenFile: Handler;
  handleSaveFile: Handler;
  closeFile: (id: string, e: Event) => void;
};

export type OpenFile = {
  id: string;
  name: string;
  path: string | null;
  content: string;
};

export type SourceMap = [number, number][];
