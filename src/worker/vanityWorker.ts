import { ed25519 } from '@noble/curves/ed25519.js'
import { bytesToHex } from '../utils/hex'
import { bytesToBase58, matchesVanityTarget } from '../wallet/solanaAddress'
import type { SearchTarget } from '../searchTarget'

type WorkerMessage = {
  type: 'search'
  id: number
  batchSize: number
  prefix: string
  suffix: string
  caseSensitive: boolean
  target: SearchTarget
}

type WorkerResult = {
  type: 'result'
  id: number
  checked: number
  found: { privHex: string; address: string } | null
}

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const { type, id, batchSize, prefix, suffix, caseSensitive, target } = e.data

  if (type !== 'search') return

  const randomBytes = new Uint8Array(batchSize * 32)
  crypto.getRandomValues(randomBytes)

  for (let i = 0; i < batchSize; i++) {
    const offset = i * 32
    const seed = randomBytes.subarray(offset, offset + 32)
    const pubkey = ed25519.getPublicKey(seed)
    const address = bytesToBase58(pubkey)

    // Program ID and wallet addresses are both Solana ed25519 pubkeys.
    const targetAddress = target === 'program' ? address : address

    if (!matchesVanityTarget(targetAddress, prefix, suffix, caseSensitive)) continue

    const verifyAddress = bytesToBase58(ed25519.getPublicKey(seed))
    if (verifyAddress !== targetAddress) continue

    const result: WorkerResult = {
      type: 'result',
      id,
      checked: i + 1,
      found: {
        privHex: bytesToHex(seed),
        address: targetAddress,
      }
    }
    self.postMessage(result)
    return
  }

  const result: WorkerResult = {
    type: 'result',
    id,
    checked: batchSize,
    found: null
  }
  self.postMessage(result)
}
