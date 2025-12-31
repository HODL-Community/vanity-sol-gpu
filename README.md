# Vanity ETH GPU

A GPU-accelerated Ethereum vanity address generator that runs entirely in your browser.

## Features

- **Full GPU Acceleration** - secp256k1 + Keccak-256 computed entirely on GPU via WebGPU
- **Privacy First** - All computations run locally in your browser, no server communication
- **Custom Prefix/Suffix** - Find addresses starting or ending with your desired characters
- **Case Sensitive** - Optional EIP-55 checksum matching
- **Keystore Export** - Download encrypted keystore JSON files

## Requirements

- A modern browser with WebGPU support (Chrome 113+, Edge 113+, or Firefox Nightly)
- A dedicated GPU is recommended for best performance

## Usage

1. Enter your desired prefix and/or suffix (hex characters: 0-9, a-f)
2. Toggle case-sensitive if you want exact case matching (slower)
3. Click Generate and wait for a match
4. Once found, reveal the private key or download as encrypted keystore

## Security

- Disconnect from the internet before generating for maximum security
- Never share your private key
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
- WebGPU / WGSL
- Web Workers (CPU fallback)

## License

MIT
