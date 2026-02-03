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
 * Same incremental search strategy as the CPU worker:
 *   - Random starting key (CSPRNG)
 *   - One full scalar multiplication for the initial pubkey
 *   - Point addition (G) for each subsequent candidate
 */

type WorkerMessage = {
  type: 'search'
  id: number
  batchSize: number
  prefixLower: string
  suffixLower: string
}

type WorkerResult = {
  type: 'result'
  id: number
  checked: number
  found: { privHex: string; address: string } | null
}

// Initialize the WASM context (precomputes tables for faster EC ops)
__initializeContext()

// Precomputed hex lookup table
const hexTable: string[] = new Array(256)
for (let i = 0; i < 256; i++) {
  hexTable[i] = i.toString(16).padStart(2, '0')
}

// Generator point G as uncompressed 65-byte key: pointFromScalar(1)
const ONE = new Uint8Array(32)
ONE[31] = 1
const G_UNCOMPRESSED = pointFromScalar(ONE, false)!

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
  // Generate 32 random bytes using CSPRNG
  const key = new Uint8Array(32)
  crypto.getRandomValues(key)
  // Ensure key is valid (not zero, less than curve order)
  // Simple check: if all zeros, set last byte to 1
  let allZero = true
  for (let i = 0; i < 32; i++) {
    if (key[i] !== 0) { allZero = false; break }
  }
  if (allZero) key[31] = 1
  return key
}

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const { type, id, batchSize, prefixLower, suffixLower } = e.data

  if (type !== 'search') return

  // Generate random starting private key
  let privKey = generateRandomKey()

  // Compute initial public key (one full scalar multiplication via WASM)
  let pubKey = pointFromScalar(privKey, false)
  if (!pubKey) {
    // Extremely unlikely - retry with different key
    privKey = generateRandomKey()
    pubKey = pointFromScalar(privKey, false)!
  }

  for (let i = 0; i < batchSize; i++) {
    // pubKey is 65 bytes: 0x04 prefix + 64 bytes (x || y)
    const pub64 = pubKey.subarray(1)
    const addr = pubkeyToAddress(pub64)

    if (addr.startsWith(prefixLower) && addr.endsWith(suffixLower)) {
      // Verify the found key
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

    // Increment: add G to public key, +1 to private key
    const nextPub = pointAdd(pubKey, G_UNCOMPRESSED, false)
    const nextPriv = privateAdd(privKey, ONE)

    if (!nextPub || !nextPriv) {
      // Wrapped around curve order (astronomically unlikely) - restart
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
