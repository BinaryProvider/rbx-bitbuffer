interface BitBuffer {
  toBase(n: number, b: number): string;
  resetPtr(): void;
  reset(): void;
  setDebug(state: boolean): void;
  fromString(str: string): void;
  toString(): string;
  fromBase64(str: string): void;
  toBase64(): string;
  dump(): void;
  writeUnsigned(w: number, value: number, printoff?: boolean): void;
  readUnsigned(w: number, printoff?: boolean): number;
  writeSigned(w: number, value: number): void;
  readSigned(w: number): number;
  writeString(s: string): void;
  readString(): string;
  writeBool(v: boolean): void;
  readBool(): boolean;
  writeFloat(wfrac: number, wexp: number, f: number): void;
  readFloat(wfrac: number, wexp: number): number;
  writeFloat32(f: number): void;
  readFloat32(): number;
  writeFloat64(f: number): void;
  readFloat64(): number;
  writeBrickColor(b: BrickColor): void;
  readBrickColor(): BrickColor;
  writeRotation(cf: CFrame): void;
  readRotation(): CFrame;
}
interface BitBufferCreator {
  create(): BitBuffer;
}
declare const BitBuffer: BitBufferCreator;
export default BitBuffer;
