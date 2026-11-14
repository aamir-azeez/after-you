/**
 * The few nodejs_compat modules the Worker uses (wrangler.jsonc turns nodejs_compat on), typed here since the
 * project carries no Node types: synchronous zlib for blob-codec.ts and Buffer's native base64 and byte
 * counting for v2/row-codec.ts.
 */
declare module "node:zlib" {
  export function deflateSync(data: Uint8Array): Uint8Array;
  export function inflateSync(data: Uint8Array, options?: { maxOutputLength?: number }): Uint8Array;
}
declare module "node:buffer" {
  export class Buffer extends Uint8Array {
    static from(data: Uint8Array | ArrayBuffer): Buffer;
    static from(data: string, encoding: "base64" | "utf8"): Buffer;
    static byteLength(data: string, encoding: "utf8"): number;
    toString(encoding: "base64" | "utf8"): string;
  }
}
