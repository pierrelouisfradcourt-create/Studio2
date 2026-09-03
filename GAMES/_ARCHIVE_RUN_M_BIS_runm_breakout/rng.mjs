// RNG seedé déterministe — substrat de reproductibilité (socle N1)
export class RNG {
  constructor(seed = 1) {
    this.seed = seed;
    this.state = seed >>> 0;
  }

  next() {
    this.state = ((this.state * 1103515245 + 12345) >>> 0) % (2 ** 31);
    return this.state / (2 ** 31);
  }

  nextInt(min, max) {
    return Math.floor(this.next() * (max - min)) + min;
  }
}

export function makeRng(seed = 1) {
  return new RNG(seed);
}
