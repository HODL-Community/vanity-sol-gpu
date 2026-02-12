export type SearchTarget = 'wallet' | 'first-contract'

export function searchTargetToGpuMode(target: SearchTarget): number {
  return target === 'first-contract' ? 1 : 0
}

