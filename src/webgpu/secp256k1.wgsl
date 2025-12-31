// Full secp256k1 + Keccak-256 vanity address generation on GPU
// 256-bit integers represented as 8 x u32 (little-endian limbs)

// secp256k1 prime: p = 2^256 - 2^32 - 977
const P0: u32 = 0xFFFFFC2Fu;
const P1: u32 = 0xFFFFFFFEu;
const P2: u32 = 0xFFFFFFFFu;
const P3: u32 = 0xFFFFFFFFu;
const P4: u32 = 0xFFFFFFFFu;
const P5: u32 = 0xFFFFFFFFu;
const P6: u32 = 0xFFFFFFFFu;
const P7: u32 = 0xFFFFFFFFu;

// Generator point G
const GX0: u32 = 0x16F81798u; const GX1: u32 = 0x59F2815Bu; const GX2: u32 = 0x2DCE28D9u; const GX3: u32 = 0x029BFCDBu;
const GX4: u32 = 0xCE870B07u; const GX5: u32 = 0x55A06295u; const GX6: u32 = 0xF9DCBBACu; const GX7: u32 = 0x79BE667Eu;
const GY0: u32 = 0xFB10D4B8u; const GY1: u32 = 0x9C47D08Fu; const GY2: u32 = 0xA6855419u; const GY3: u32 = 0xFD17B448u;
const GY4: u32 = 0x0E1108A8u; const GY5: u32 = 0x5DA4FBFCu; const GY6: u32 = 0x26A3C465u; const GY7: u32 = 0x483ADA77u;

// Keccak round constants (lo, hi pairs)
const RC: array<u32, 48> = array<u32, 48>(
  0x00000001u, 0x00000000u, 0x00008082u, 0x00000000u,
  0x0000808au, 0x80000000u, 0x80008000u, 0x80000000u,
  0x0000808bu, 0x00000000u, 0x80000001u, 0x00000000u,
  0x80008081u, 0x80000000u, 0x00008009u, 0x80000000u,
  0x0000008au, 0x00000000u, 0x00000088u, 0x00000000u,
  0x80008009u, 0x00000000u, 0x8000000au, 0x00000000u,
  0x8000808bu, 0x80000000u, 0x0000008bu, 0x80000000u,
  0x00008089u, 0x80000000u, 0x00008003u, 0x80000000u,
  0x00008002u, 0x80000000u, 0x00000080u, 0x80000000u,
  0x0000800au, 0x00000000u, 0x8000000au, 0x80000000u,
  0x80008081u, 0x80000000u, 0x00008080u, 0x80000000u,
  0x80000001u, 0x00000000u, 0x80008008u, 0x80000000u
);

const ROTC: array<u32, 24> = array<u32, 24>(1u,3u,6u,10u,15u,21u,28u,36u,45u,55u,2u,14u,27u,41u,56u,8u,25u,43u,62u,18u,39u,61u,20u,44u);
const PILN: array<u32, 24> = array<u32, 24>(10u,7u,11u,17u,18u,3u,5u,16u,8u,21u,24u,4u,15u,23u,19u,13u,12u,2u,20u,14u,22u,9u,6u,1u);

@group(0) @binding(0) var<storage, read> seeds: array<u32>;
@group(0) @binding(1) var<storage, read> params: array<u32>;
@group(0) @binding(2) var<storage, read_write> results: array<atomic<u32>>;

// 64-bit add with carry: (a_lo, a_hi) + (b_lo, b_hi) -> (sum_lo, sum_hi)
fn add64(a_lo: u32, a_hi: u32, b_lo: u32, b_hi: u32) -> vec2<u32> {
  let sum_lo = a_lo + b_lo;
  let carry = select(0u, 1u, sum_lo < a_lo);
  let sum_hi = a_hi + b_hi + carry;
  return vec2<u32>(sum_lo, sum_hi);
}

// 32x32 -> 64 multiplication
fn mul32x32(a: u32, b: u32) -> vec2<u32> {
  let a_lo = a & 0xFFFFu;
  let a_hi = a >> 16u;
  let b_lo = b & 0xFFFFu;
  let b_hi = b >> 16u;

  let p0 = a_lo * b_lo;
  let p1 = a_lo * b_hi;
  let p2 = a_hi * b_lo;
  let p3 = a_hi * b_hi;

  let mid = p1 + p2;
  let mid_carry = select(0u, 0x10000u, mid < p1);

  let lo = p0 + (mid << 16u);
  let lo_carry = select(0u, 1u, lo < p0);
  let hi = p3 + (mid >> 16u) + mid_carry + lo_carry;

  return vec2<u32>(lo, hi);
}

// 256-bit addition mod p (simplified - just add and reduce once)
fn add256_mod(a: ptr<function, array<u32, 8>>, b: ptr<function, array<u32, 8>>, out: ptr<function, array<u32, 8>>) {
  var carry = 0u;
  for (var i = 0u; i < 8u; i++) {
    let sum = (*a)[i] + (*b)[i] + carry;
    carry = select(0u, 1u, sum < (*a)[i] || (carry == 1u && sum == (*a)[i]));
    (*out)[i] = sum;
  }

  // Reduce mod p if needed (simple subtract)
  var gte_p = true;
  let p = array<u32, 8>(P0, P1, P2, P3, P4, P5, P6, P7);
  for (var i = 7i; i >= 0i; i--) {
    if ((*out)[i] > p[i]) { break; }
    if ((*out)[i] < p[i]) { gte_p = false; break; }
  }

  if (gte_p || carry == 1u) {
    var borrow = 0u;
    for (var i = 0u; i < 8u; i++) {
      let diff = (*out)[i] - p[i] - borrow;
      borrow = select(0u, 1u, (*out)[i] < p[i] + borrow);
      (*out)[i] = diff;
    }
  }
}

// 256-bit subtraction mod p
fn sub256_mod(a: ptr<function, array<u32, 8>>, b: ptr<function, array<u32, 8>>, out: ptr<function, array<u32, 8>>) {
  var borrow = 0u;
  for (var i = 0u; i < 8u; i++) {
    let b_plus_borrow = (*b)[i] + borrow;
    borrow = select(0u, 1u, (*a)[i] < b_plus_borrow || (borrow == 1u && (*b)[i] == 0xFFFFFFFFu));
    (*out)[i] = (*a)[i] - b_plus_borrow;
  }

  // If borrow, add p back
  if (borrow == 1u) {
    let p = array<u32, 8>(P0, P1, P2, P3, P4, P5, P6, P7);
    var carry = 0u;
    for (var i = 0u; i < 8u; i++) {
      let sum = (*out)[i] + p[i] + carry;
      carry = select(0u, 1u, sum < (*out)[i]);
      (*out)[i] = sum;
    }
  }
}

// Multiply 256-bit by 256-bit, reduce mod p (Barrett reduction simplified for secp256k1)
fn mul256_mod(a: ptr<function, array<u32, 8>>, b: ptr<function, array<u32, 8>>, out: ptr<function, array<u32, 8>>) {
  // Full 512-bit product
  var product: array<u32, 16>;
  for (var i = 0u; i < 16u; i++) { product[i] = 0u; }

  for (var i = 0u; i < 8u; i++) {
    var carry = 0u;
    for (var j = 0u; j < 8u; j++) {
      let m = mul32x32((*a)[i], (*b)[j]);
      let sum1 = add64(product[i+j], 0u, m.x, m.y);
      let sum2 = add64(sum1.x, sum1.y, carry, 0u);
      product[i+j] = sum2.x;
      carry = sum2.y;
    }
    product[i + 8u] = carry;
  }

  // secp256k1 reduction: p = 2^256 - 2^32 - 977
  // high * 2^256 ≡ high * (2^32 + 977) mod p
  for (var i = 0u; i < 8u; i++) {
    (*out)[i] = product[i];
  }

  for (var k = 8u; k < 16u; k++) {
    let hi = product[k];
    if (hi == 0u) { continue; }

    let pos = k - 8u;

    // Add hi * 977 at position pos
    let m = mul32x32(hi, 977u);
    var carry = 0u;
    let sum0 = add64((*out)[pos], 0u, m.x, 0u);
    (*out)[pos] = sum0.x;
    carry = sum0.y + m.y;

    // Add hi at position pos+1 (for the 2^32 factor)
    if (pos + 1u < 8u) {
      let sum1 = add64((*out)[pos + 1u], 0u, hi + carry, 0u);
      (*out)[pos + 1u] = sum1.x;
      carry = sum1.y;
    } else {
      carry = carry + hi;
    }

    // Propagate carry
    for (var c = pos + 2u; c < 8u && carry > 0u; c++) {
      let sum = (*out)[c] + carry;
      carry = select(0u, 1u, sum < (*out)[c]);
      (*out)[c] = sum;
    }
  }

  // Final reduction
  let p = array<u32, 8>(P0, P1, P2, P3, P4, P5, P6, P7);
  var gte = true;
  for (var i = 7i; i >= 0i; i--) {
    if ((*out)[i] > p[i]) { break; }
    if ((*out)[i] < p[i]) { gte = false; break; }
  }
  if (gte) {
    var borrow = 0u;
    for (var i = 0u; i < 8u; i++) {
      let diff = (*out)[i] - p[i] - borrow;
      borrow = select(0u, 1u, (*out)[i] < p[i] + borrow);
      (*out)[i] = diff;
    }
  }
}

// Square mod p
fn sqr256_mod(a: ptr<function, array<u32, 8>>, out: ptr<function, array<u32, 8>>) {
  mul256_mod(a, a, out);
}

// Check if 256-bit number is zero
fn is_zero(a: ptr<function, array<u32, 8>>) -> bool {
  for (var i = 0u; i < 8u; i++) {
    if ((*a)[i] != 0u) { return false; }
  }
  return true;
}

// Modular inverse using Fermat: a^(p-2) mod p
fn inv256_mod(a: ptr<function, array<u32, 8>>, out: ptr<function, array<u32, 8>>) {
  // p-2 for secp256k1
  var exp = array<u32, 8>(
    0xFFFFFC2Du, 0xFFFFFFFEu, 0xFFFFFFFFu, 0xFFFFFFFFu,
    0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu
  );

  var result = array<u32, 8>(1u, 0u, 0u, 0u, 0u, 0u, 0u, 0u);
  var base = *a;

  for (var i = 0u; i < 256u; i++) {
    let limb = i / 32u;
    let bit = i % 32u;
    if ((exp[limb] & (1u << bit)) != 0u) {
      var tmp: array<u32, 8>;
      mul256_mod(&result, &base, &tmp);
      result = tmp;
    }
    var sq: array<u32, 8>;
    sqr256_mod(&base, &sq);
    base = sq;
  }

  *out = result;
}

// Keccak-256 on 64 bytes (public key)
fn keccak256(data: ptr<function, array<u32, 16>>) -> array<u32, 8> {
  var state: array<u32, 50>;
  for (var i = 0u; i < 50u; i++) { state[i] = 0u; }

  // Absorb 64 bytes
  for (var i = 0u; i < 16u; i++) {
    state[i] = (*data)[i];
  }

  // Padding for 64-byte message with rate=136
  state[16u] ^= 0x01u;
  state[33u] ^= 0x80000000u;

  // 24 rounds of Keccak-f
  for (var round = 0u; round < 24u; round++) {
    // Theta
    var c: array<u32, 10>;
    for (var x = 0u; x < 5u; x++) {
      c[x*2u] = state[x*2u] ^ state[10u+x*2u] ^ state[20u+x*2u] ^ state[30u+x*2u] ^ state[40u+x*2u];
      c[x*2u+1u] = state[x*2u+1u] ^ state[10u+x*2u+1u] ^ state[20u+x*2u+1u] ^ state[30u+x*2u+1u] ^ state[40u+x*2u+1u];
    }

    for (var x = 0u; x < 5u; x++) {
      let x1 = (x + 1u) % 5u;
      let x4 = (x + 4u) % 5u;
      // rotl64 by 1
      let rot_lo = (c[x1*2u] << 1u) | (c[x1*2u+1u] >> 31u);
      let rot_hi = (c[x1*2u+1u] << 1u) | (c[x1*2u] >> 31u);
      let d_lo = c[x4*2u] ^ rot_lo;
      let d_hi = c[x4*2u+1u] ^ rot_hi;

      for (var y = 0u; y < 5u; y++) {
        let idx = (y * 5u + x) * 2u;
        state[idx] ^= d_lo;
        state[idx+1u] ^= d_hi;
      }
    }

    // Rho + Pi
    var temp: array<u32, 50>;
    temp[0u] = state[0u];
    temp[1u] = state[1u];

    var t_lo = state[2u];
    var t_hi = state[3u];
    for (var i = 0u; i < 24u; i++) {
      let j = PILN[i];
      let new_lo = state[j * 2u];
      let new_hi = state[j * 2u + 1u];

      let r = ROTC[i];
      var rot_lo: u32;
      var rot_hi: u32;
      if (r == 0u) {
        rot_lo = t_lo; rot_hi = t_hi;
      } else if (r < 32u) {
        rot_lo = (t_lo << r) | (t_hi >> (32u - r));
        rot_hi = (t_hi << r) | (t_lo >> (32u - r));
      } else {
        let m = r - 32u;
        rot_lo = (t_hi << m) | (t_lo >> (32u - m));
        rot_hi = (t_lo << m) | (t_hi >> (32u - m));
      }

      temp[j * 2u] = rot_lo;
      temp[j * 2u + 1u] = rot_hi;
      t_lo = new_lo;
      t_hi = new_hi;
    }

    // Chi
    for (var y = 0u; y < 5u; y++) {
      for (var x = 0u; x < 5u; x++) {
        let idx = (y * 5u + x) * 2u;
        let idx1 = (y * 5u + ((x + 1u) % 5u)) * 2u;
        let idx2 = (y * 5u + ((x + 2u) % 5u)) * 2u;
        state[idx] = temp[idx] ^ ((~temp[idx1]) & temp[idx2]);
        state[idx+1u] = temp[idx+1u] ^ ((~temp[idx1+1u]) & temp[idx2+1u]);
      }
    }

    // Iota
    state[0u] ^= RC[round * 2u];
    state[1u] ^= RC[round * 2u + 1u];
  }

  var hash: array<u32, 8>;
  for (var i = 0u; i < 8u; i++) {
    hash[i] = state[i];
  }
  return hash;
}

// Simple scalar multiplication k*G using double-and-add
// Returns affine (x, y) coordinates
fn scalar_mult_G(k: ptr<function, array<u32, 8>>) -> array<array<u32, 8>, 2> {
  // Jacobian point (X:Y:Z) where affine = (X/Z², Y/Z³)
  // Start with point at infinity (Z=0)
  var rx = array<u32, 8>(0u,0u,0u,0u,0u,0u,0u,0u);
  var ry = array<u32, 8>(0u,0u,0u,0u,0u,0u,0u,0u);
  var rz = array<u32, 8>(0u,0u,0u,0u,0u,0u,0u,0u);

  // G point (affine)
  var gx = array<u32, 8>(GX0, GX1, GX2, GX3, GX4, GX5, GX6, GX7);
  var gy = array<u32, 8>(GY0, GY1, GY2, GY3, GY4, GY5, GY6, GY7);
  var gz = array<u32, 8>(1u, 0u, 0u, 0u, 0u, 0u, 0u, 0u);

  for (var i = 0u; i < 256u; i++) {
    let limb = i / 32u;
    let bit = i % 32u;

    if (((*k)[limb] & (1u << bit)) != 0u) {
      // Point addition: R = R + G
      if (is_zero(&rz)) {
        rx = gx; ry = gy; rz = gz;
      } else {
        // Full Jacobian point addition
        var z1z1: array<u32, 8>; sqr256_mod(&rz, &z1z1);
        var z2z2: array<u32, 8>; sqr256_mod(&gz, &z2z2);
        var u1: array<u32, 8>; mul256_mod(&rx, &z2z2, &u1);
        var u2: array<u32, 8>; mul256_mod(&gx, &z1z1, &u2);
        var t1: array<u32, 8>; mul256_mod(&gz, &z2z2, &t1);
        var s1: array<u32, 8>; mul256_mod(&ry, &t1, &s1);
        var t2: array<u32, 8>; mul256_mod(&rz, &z1z1, &t2);
        var s2: array<u32, 8>; mul256_mod(&gy, &t2, &s2);

        var h: array<u32, 8>; sub256_mod(&u2, &u1, &h);
        var r: array<u32, 8>; sub256_mod(&s2, &s1, &r);

        var h2: array<u32, 8>; sqr256_mod(&h, &h2);
        var h3: array<u32, 8>; mul256_mod(&h, &h2, &h3);
        var u1h2: array<u32, 8>; mul256_mod(&u1, &h2, &u1h2);

        var r2: array<u32, 8>; sqr256_mod(&r, &r2);
        var u1h2_2: array<u32, 8>; add256_mod(&u1h2, &u1h2, &u1h2_2);
        var t3: array<u32, 8>; add256_mod(&h3, &u1h2_2, &t3);
        sub256_mod(&r2, &t3, &rx);

        var t4: array<u32, 8>; sub256_mod(&u1h2, &rx, &t4);
        var t5: array<u32, 8>; mul256_mod(&r, &t4, &t5);
        var t6: array<u32, 8>; mul256_mod(&s1, &h3, &t6);
        sub256_mod(&t5, &t6, &ry);

        var t7: array<u32, 8>; mul256_mod(&rz, &gz, &t7);
        mul256_mod(&t7, &h, &rz);
      }
    }

    // Point doubling: G = 2*G
    if (!is_zero(&gz)) {
      var xx: array<u32, 8>; sqr256_mod(&gx, &xx);
      var yy: array<u32, 8>; sqr256_mod(&gy, &yy);
      var yyyy: array<u32, 8>; sqr256_mod(&yy, &yyyy);

      var t1: array<u32, 8>; add256_mod(&gx, &yy, &t1);
      var t2: array<u32, 8>; sqr256_mod(&t1, &t2);
      var t3: array<u32, 8>; sub256_mod(&t2, &xx, &t3);
      var t4: array<u32, 8>; sub256_mod(&t3, &yyyy, &t4);
      var s: array<u32, 8>; add256_mod(&t4, &t4, &s);

      var m: array<u32, 8>; add256_mod(&xx, &xx, &m);
      add256_mod(&m, &xx, &m); // m = 3*xx

      var m2: array<u32, 8>; sqr256_mod(&m, &m2);
      var s2: array<u32, 8>; add256_mod(&s, &s, &s2);
      sub256_mod(&m2, &s2, &gx);

      var t5: array<u32, 8>; sub256_mod(&s, &gx, &t5);
      var t6: array<u32, 8>; mul256_mod(&m, &t5, &t6);
      var yyyy8: array<u32, 8> = yyyy;
      for (var j = 0u; j < 3u; j++) { add256_mod(&yyyy8, &yyyy8, &yyyy8); }
      sub256_mod(&t6, &yyyy8, &gy);

      var yz: array<u32, 8>; mul256_mod(&gy, &gz, &yz);
      add256_mod(&yz, &yz, &gz);
    }
  }

  // Convert to affine
  if (is_zero(&rz)) {
    return array<array<u32, 8>, 2>(array<u32, 8>(0u,0u,0u,0u,0u,0u,0u,0u), array<u32, 8>(0u,0u,0u,0u,0u,0u,0u,0u));
  }

  var z_inv: array<u32, 8>; inv256_mod(&rz, &z_inv);
  var z_inv2: array<u32, 8>; sqr256_mod(&z_inv, &z_inv2);
  var z_inv3: array<u32, 8>; mul256_mod(&z_inv2, &z_inv, &z_inv3);

  var ax: array<u32, 8>; mul256_mod(&rx, &z_inv2, &ax);
  var ay: array<u32, 8>; mul256_mod(&ry, &z_inv3, &ay);

  return array<array<u32, 8>, 2>(ax, ay);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  let batch_size = params[0];
  if (idx >= batch_size) { return; }

  let prefix_len = params[1];
  let suffix_len = params[2];

  // Generate private key from seeds
  var priv: array<u32, 8>;
  let seed_base = idx * 8u;
  for (var i = 0u; i < 8u; i++) {
    priv[i] = seeds[seed_base + i] ^ (idx * 2654435761u + i * 1597334677u);
  }

  // Compute public key
  let pubkey = scalar_mult_G(&priv);

  // Pack for Keccak (64 bytes = 16 u32s)
  var pubkey_data: array<u32, 16>;
  for (var i = 0u; i < 8u; i++) {
    pubkey_data[i] = pubkey[0][i];
    pubkey_data[8u + i] = pubkey[1][i];
  }

  let hash = keccak256(&pubkey_data);

  // Check prefix/suffix matching
  // Address is bytes 12-31 of hash (last 20 bytes)
  var match = true;

  // Check prefix
  for (var i = 0u; i < prefix_len && match; i++) {
    let nibble_idx = i;
    let byte_idx = 12u + nibble_idx / 2u;
    let word_idx = byte_idx / 4u;
    let byte_in_word = byte_idx % 4u;
    let byte_val = (hash[word_idx] >> (byte_in_word * 8u)) & 0xFFu;
    let nibble = select(byte_val >> 4u, byte_val & 0xFu, nibble_idx % 2u == 1u);
    let expected = params[4u + i];
    if (nibble != expected) { match = false; }
  }

  // Check suffix
  for (var i = 0u; i < suffix_len && match; i++) {
    let nibble_from_end = suffix_len - 1u - i;
    let addr_nibble = 39u - nibble_from_end;
    let byte_idx = 12u + addr_nibble / 2u;
    let word_idx = byte_idx / 4u;
    let byte_in_word = byte_idx % 4u;
    let byte_val = (hash[word_idx] >> (byte_in_word * 8u)) & 0xFFu;
    let nibble = select(byte_val >> 4u, byte_val & 0xFu, addr_nibble % 2u == 1u);
    let expected = params[44u + i];
    if (nibble != expected) { match = false; }
  }

  if (match) {
    let slot = atomicAdd(&results[0], 1u);
    if (slot < 16u) {
      let base = 1u + slot * 17u;
      for (var i = 0u; i < 8u; i++) {
        atomicStore(&results[base + i], priv[i]);
        atomicStore(&results[base + 8u + i], hash[i]);
      }
      atomicStore(&results[base + 16u], idx);
    }
  }
}
