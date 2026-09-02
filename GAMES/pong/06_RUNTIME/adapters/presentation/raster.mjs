// PONG — adaptateur presentation : SURFACE logicielle + encodeur PNG (ADAPTATEUR,
// jamais importe par la logique). Sert de capture HEADLESS de l'adaptateur navigateur :
// la meme fonction drawState() dessine ici sur un buffer RGBA plutot que sur un
// <canvas>, ce qui permet de produire un PNG deterministe sans navigateur reel.
import zlib from 'node:zlib';

// Surface RGBA minimale, API alignee sur un contexte 2D (fillRect / clear).
export class Surface {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.buf = new Uint8Array(w * h * 4);   // RGBA, 0 par defaut (transparent noir)
  }

  clear(r, g, b) {
    for (let i = 0; i < this.w * this.h; i += 1) {
      this.buf[i * 4] = r; this.buf[i * 4 + 1] = g; this.buf[i * 4 + 2] = b; this.buf[i * 4 + 3] = 255;
    }
  }

  fillRect(x, y, w, h, r, g, b) {
    const x0 = Math.max(0, Math.round(x));
    const y0 = Math.max(0, Math.round(y));
    const x1 = Math.min(this.w, Math.round(x + w));
    const y1 = Math.min(this.h, Math.round(y + h));
    for (let py = y0; py < y1; py += 1) {
      for (let px = x0; px < x1; px += 1) {
        const i = (py * this.w + px) * 4;
        this.buf[i] = r; this.buf[i + 1] = g; this.buf[i + 2] = b; this.buf[i + 3] = 255;
      }
    }
  }

  // Nombre de couleurs RGBA distinctes — sert au critere "aucune capture monochrome".
  distinctColors() {
    const seen = new Set();
    for (let i = 0; i < this.w * this.h; i += 1) {
      const j = i * 4;
      seen.add(`${this.buf[j]},${this.buf[j + 1]},${this.buf[j + 2]}`);
      if (seen.size > 8) break;
    }
    return seen.size;
  }

  toPNG() {
    return encodePNG(this.w, this.h, this.buf);
  }
}

// --- CRC32 (table paresseuse) ---
let CRC_TABLE = null;
function crcTable() {
  if (CRC_TABLE) return CRC_TABLE;
  CRC_TABLE = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    CRC_TABLE[n] = c >>> 0;
  }
  return CRC_TABLE;
}
function crc32(buf) {
  const t = crcTable();
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) c = t[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

// Encodeur PNG 8-bit RGBA (color type 6), filtre 0 par scanline.
export function encodePNG(w, h, rgba) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;    // bit depth
  ihdr[9] = 6;    // color type RGBA
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

  const raw = Buffer.alloc(h * (1 + w * 4));
  for (let y = 0; y < h; y += 1) {
    raw[y * (1 + w * 4)] = 0;   // filtre None
    for (let x = 0; x < w * 4; x += 1) {
      raw[y * (1 + w * 4) + 1 + x] = rgba[y * w * 4 + x];
    }
  }
  const idat = zlib.deflateSync(raw);
  return Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
