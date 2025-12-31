import * as secp from '@noble/secp256k1'
import { keccak_256 } from '@noble/hashes/sha3.js'

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

// Precomputed hex lookup table for fast conversion
const hexTable: string[] = new Array(256)
for (let i = 0; i < 256; i++) {
  hexTable[i] = i.toString(16).padStart(2, '0')
}

function bytesToHex(bytes: Uint8Array): string {
  let hex = ''
  for (let i = 0; i < bytes.length; i++) {
    hex += hexTable[bytes[i]]
  }
  return hex
}

function pubkeyToAddress(pubkey64: Uint8Array): string {
  const hash = keccak_256(pubkey64)
  // Only convert last 20 bytes to hex (the address)
  let addr = ''
  for (let i = 12; i < 32; i++) {
    addr += hexTable[hash[i]]
  }
  return addr
}

// Get generator point for incremental key generation
const G = secp.ProjectivePoint.BASE

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const { type, id, batchSize, prefixLower, suffixLower } = e.data

  if (type !== 'search') return

  // Generate random starting private key
  const privBytes = secp.utils.randomSecretKey()
  let privBigInt = bytesToBigInt(privBytes)

  // Get initial public key point
  let pubPoint = secp.ProjectivePoint.fromPrivateKey(privBytes)

  for (let i = 0; i < batchSize; i++) {
    // Convert point to uncompressed public key bytes (skip 04 prefix)
    const pubAffine = pubPoint.toAffine()
    const pub64 = new Uint8Array(64)
    const xBytes = bigIntToBytes(pubAffine.x)
    const yBytes = bigIntToBytes(pubAffine.y)
    pub64.set(xBytes, 32 - xBytes.length)
    pub64.set(yBytes, 64 - yBytes.length)

    const addr = pubkeyToAddress(pub64)

    if (addr.startsWith(prefixLower) && addr.endsWith(suffixLower)) {
      const result: WorkerResult = {
        type: 'result',
        id,
        checked: i + 1,
        found: { privHex: bigIntToHex(privBigInt), address: '0x' + addr }
      }
      self.postMessage(result)
      return
    }

    // Increment private key and add G to public key (much faster than full multiplication)
    privBigInt = (privBigInt + 1n) % secp.CURVE.n
    pubPoint = pubPoint.add(G)
  }

  const result: WorkerResult = {
    type: 'result',
    id,
    checked: batchSize,
    found: null
  }
  self.postMessage(result)
}

function bytesToBigInt(bytes: Uint8Array): bigint {
  let result = 0n
  for (let i = 0; i < bytes.length; i++) {
    result = (result << 8n) | BigInt(bytes[i])
  }
  return result
}

function bigIntToBytes(n: bigint): Uint8Array {
  const bytes = new Uint8Array(32)
  let temp = n
  for (let i = 31; i >= 0; i--) {
    bytes[i] = Number(temp & 0xffn)
    temp >>= 8n
  }
  // Trim leading zeros
  let start = 0
  while (start < 31 && bytes[start] === 0) start++
  return bytes.slice(start)
}

function bigIntToHex(n: bigint): string {
  return n.toString(16).padStart(64, '0')
}
