import { loadJSON, saveJSON } from "../persist";

const STORAGE_KEY = "hart:display";

export type RegisterNaming = "abi" | "numeric";
export type Endianness = "little" | "big";
export type ByteWidth = 1 | 2 | 4 | 8;

export interface DisplayPrefs {
  registerNaming: RegisterNaming;
  endianness: Endianness;
  memBytesPerGroup: ByteWidth;
  flashChanges: boolean;
  followMemoryWrites: boolean;
  hexMode: boolean;
  signedMode: boolean;
}

export const DEFAULT_DISPLAY: DisplayPrefs = {
  registerNaming: "abi",
  endianness: "little",
  memBytesPerGroup: 1,
  flashChanges: true,
  followMemoryWrites: true,
  hexMode: true,
  signedMode: true,
};

class DisplayStore {
  registerNaming = $state<RegisterNaming>(DEFAULT_DISPLAY.registerNaming);
  endianness = $state<Endianness>(DEFAULT_DISPLAY.endianness);
  memBytesPerGroup = $state<ByteWidth>(DEFAULT_DISPLAY.memBytesPerGroup);
  flashChanges = $state(DEFAULT_DISPLAY.flashChanges);
  followMemoryWrites = $state(DEFAULT_DISPLAY.followMemoryWrites);
  hexMode = $state(DEFAULT_DISPLAY.hexMode);
  signedMode = $state(DEFAULT_DISPLAY.signedMode);

  constructor() {
    const stored = loadJSON<Partial<DisplayPrefs>>(STORAGE_KEY, {});
    Object.assign(this, { ...DEFAULT_DISPLAY, ...stored });

    $effect.root(() => {
      $effect(() => saveJSON(STORAGE_KEY, this.snapshot()));
    });
  }

  private snapshot(): DisplayPrefs {
    return {
      registerNaming: this.registerNaming,
      endianness: this.endianness,
      memBytesPerGroup: this.memBytesPerGroup,
      flashChanges: this.flashChanges,
      followMemoryWrites: this.followMemoryWrites,
      hexMode: this.hexMode,
      signedMode: this.signedMode,
    };
  }

  public reset() {
    Object.assign(this, DEFAULT_DISPLAY);
  }
}

export const displayStore = new DisplayStore();
