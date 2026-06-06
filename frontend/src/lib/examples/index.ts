import welcome from "./welcome.s?raw";
import fibonacci from "./fibonacci.s?raw";
import factorial from "./factorial.s?raw";
import interactive from "./interactive.s?raw";

export type Example = { name: string; content: string };

export const EXAMPLES: Example[] = [
  { name: "welcome.s", content: welcome },
  { name: "fibonacci.s", content: fibonacci },
  { name: "factorial.s", content: factorial },
  { name: "interactive.s", content: interactive },
];
