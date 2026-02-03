import {
  __initializeContext,
  pointFromScalar,
  pointAdd,
  privateAdd
} from 'tiny-secp256k1'
import { keccak_256 } from '@noble/hashes/sha3.js'

/**
 * WASM-accelerated vanity address worker.
 *
 * Uses tiny-secp256k1 (Rust → WASM) for EC point operations,
 * which is significantly faster than pure-JS @noble/secp256k1 BigInt math.
 *
 * Initialization is deferred until the first 'init' message to avoid
 * multiple workers all calling __initializeContext() simultaneously
 * (which can hang the browser).
 */

type WorkerMessage =
  | { type: 'init' }
  | { type: 'search'; id: number; batchSize: number; prefixLower: string; suffixLower: string }

type WorkerResult =
  | { type: 'ready' }
  | { type: 'init-failed'; error: string }
  | { type: 'result'; id: number; checked: number; found: { privHex: string; address: string } | null }

// Precomputed hex lookup table
const hexTable: string[] = new Array(256)
for (let i = 0; i < 256; i++) {
  hexTable[i] = i.toString(16).padStart(2, '0')
}

let initialized = false
let G_UNCOMPRESSED: Uint8Array
const ONE = new Uint8Array(32)
ONE[31] = 1

function pubkeyToAddress(pubkey64: Uint8Array): string {
  const hash = keccak_256(pubkey64)
  let addr = ''
  for (let i = 12; i < 32; i++) {
    addr += hexTable[hash[i]]
  }
  return addr
}

function bytesToHex(bytes: Uint8Array): string {
  let out = ''
  for (let i = 0; i < bytes.length; i++) {
    out += hexTable[bytes[i]]
  }
  return out
}

function generateRandomKey(): Uint8Array {
  const key = new Uint8Array(32)
  crypto.getRandomValues(key)
  let allZero = true
  for (let i = 0; i < 32; i++) {
    if (key[i] !== 0) { allZero = false; break }
  }
  if (allZero) key[31] = 1
  return key
}

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const msg = e.data

  if (msg.type === 'init') {
    try {
      __initializeContext()
      G_UNCOMPRESSED = pointFromScalar(ONE, false)!
      initialized = true
      self.postMessage({ type: 'ready' } as WorkerResult)
    } catch (err: any) {
      self.postMessage({ type: 'init-failed', error: err?.message || 'unknown' } as WorkerResult)
    }
    return
  }

  if (msg.type !== 'search' || !initialized) return

  const { id, batchSize, prefixLower, suffixLower } = msg

  let privKey = generateRandomKey()
  let pubKey = pointFromScalar(privKey, false)
  if (!pubKey) {
    privKey = generateRandomKey()
    pubKey = pointFromScalar(privKey, false)!
  }

  for (let i = 0; i < batchSize; i++) {
    const pub64 = pubKey.subarray(1)
    const addr = pubkeyToAddress(pub64)

    if (addr.startsWith(prefixLower) && addr.endsWith(suffixLower)) {
      const verifyPub = pointFromScalar(privKey, false)
      if (verifyPub) {
        const verifyAddr = pubkeyToAddress(verifyPub.subarray(1))
        if (verifyAddr === addr) {
          const result: WorkerResult = {
            type: 'result',
            id,
            checked: i + 1,
            found: { privHex: bytesToHex(privKey), address: '0x' + addr }
          }
          self.postMessage(result)
          return
        }
      }
    }

    const nextPub = pointAdd(pubKey, G_UNCOMPRESSED, false)
    const nextPriv = privateAdd(privKey, ONE)

    if (!nextPub || !nextPriv) {
      privKey = generateRandomKey()
      pubKey = pointFromScalar(privKey, false)!
      continue
    }

    pubKey = nextPub
    privKey = nextPriv
  }

  const result: WorkerResult = {
    type: 'result',
    id,
    checked: batchSize,
    found: null
  }
  self.postMessage(result)
}
