# Vanity SOL GPU

A fast Solana vanity address generator that runs entirely in your browser.

## Features

- **Multi-threaded** - Uses Web Workers for parallel keypair generation
- **GPU-accelerated matching** - Uses WebGPU to parallelize Base58 vanity matching when available
- **Privacy First** - All computations run locally in your browser, no server communication
- **Custom Prefix/Suffix** - Find addresses starting or ending with your desired Base58 characters
- **Wallet + Program ID Targets** - Scan either wallet addresses or program IDs
- **Keypair Export** - Download Solana-compatible keypair JSON files

## Requirements

- A modern browser (Chrome, Firefox, Edge, Safari)

## Usage

1. Choose target: wallet address or program ID
2. Enter your desired prefix and/or suffix (Base58 characters)
3. Click Generate and wait for a match
4. Once found, reveal the secret key or download keypair JSON

## Security

- Disconnect from the internet before generating for maximum security
- Never share your secret key
- Always verify the address matches your requirements before use

## Development

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Build for production
npm run build
```

## Tech Stack

- TypeScript
- Vite
- Web Workers
- WebGPU
- @noble/curves (ed25519)

## Notes

- Runtime auto-benchmarks GPU hybrid mode vs CPU mode and picks the faster backend.
- If WebGPU is unavailable, the app falls back to CPU-only search.

## License

MIT
