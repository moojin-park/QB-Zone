export interface RandomResult {
  state: number;
  value: number;
}

export const nextRandom = (state: number): RandomResult => {
  let next = state | 0;
  next ^= next << 13;
  next ^= next >>> 17;
  next ^= next << 5;
  const unsigned = next >>> 0;
  return { state: unsigned || 0x6d2b79f5, value: unsigned / 0x1_0000_0000 };
};

export const randomBetween = (state: number, minimum: number, maximum: number): RandomResult => {
  const result = nextRandom(state);
  return { state: result.state, value: minimum + (maximum - minimum) * result.value };
};

export const randomDirection = (state: number): { state: number; direction: -1 | 1 } => {
  const result = nextRandom(state);
  return { state: result.state, direction: result.value < 0.5 ? -1 : 1 };
};
