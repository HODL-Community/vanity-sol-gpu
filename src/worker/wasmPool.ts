import WasmVanityWorker from './wasmVanityWorker?worker'

type SearchResult = {
  checked: number
  found: { privHex: string; address: string } | null
}

type PendingTask = {
  resolve: (result: SearchResult) => void
}

export type WasmWorkerPool = {
  search(prefixLower: string, suffixLower: string, batchSize: number): Promise<SearchResult>
  destroy(): void
  workerCount: number
}

/**
 * Initialize a single WASM worker: send 'init', wait for 'ready' or timeout.
 * Returns the worker if successful, null if init failed/timed out.
 */
function initWorker(timeoutMs: number): Promise<Worker | null> {
  return new Promise((resolve) => {
    const worker = new WasmVanityWorker()
    const timer = setTimeout(() => {
      worker.terminate()
      resolve(null)
    }, timeoutMs)

    worker.onmessage = (e) => {
      if (e.data.type === 'ready') {
        clearTimeout(timer)
        resolve(worker)
      } else if (e.data.type === 'init-failed') {
        clearTimeout(timer)
        worker.terminate()
        resolve(null)
      }
    }

    worker.postMessage({ type: 'init' })
  })
}

/**
 * Create a WASM worker pool with sequential initialization.
 * Workers are initialized one at a time to avoid __initializeContext() contention.
 * Returns null if no workers could be initialized.
 */
export async function createWasmWorkerPool(initTimeoutMs = 10000): Promise<WasmWorkerPool | null> {
  const targetCount = Math.max(1, navigator.hardwareConcurrency || 4)
  const workers: Worker[] = []
  const pending = new Map<number, PendingTask>()
  let nextId = 0
  let destroyed = false

  // Initialize workers sequentially to avoid contention
  for (let i = 0; i < targetCount; i++) {
    if (destroyed) break
    const worker = await initWorker(initTimeoutMs)
    if (worker) {
      worker.onmessage = (e) => {
        const { id, checked, found } = e.data
        const task = pending.get(id)
        if (task) {
          pending.delete(id)
          task.resolve({ checked, found })
        }
      }
      workers.push(worker)
    } else {
      // If the first worker fails, WASM isn't going to work
      if (workers.length === 0) {
        return null
      }
    }
  }

  if (workers.length === 0) return null

  let workerIndex = 0

  function search(prefixLower: string, suffixLower: string, batchSize: number): Promise<SearchResult> {
    if (destroyed) return Promise.reject(new Error('Pool destroyed'))

    return new Promise((resolve) => {
      const id = nextId++
      pending.set(id, { resolve })

      const worker = workers[workerIndex]
      workerIndex = (workerIndex + 1) % workers.length

      worker.postMessage({
        type: 'search',
        id,
        batchSize,
        prefixLower,
        suffixLower
      })
    })
  }

  function destroy() {
    destroyed = true
    workers.forEach(w => w.terminate())
    workers.length = 0
    pending.clear()
  }

  return { search, destroy, workerCount: workers.length }
}
