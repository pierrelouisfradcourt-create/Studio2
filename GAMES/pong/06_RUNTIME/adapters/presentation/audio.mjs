// PONG — adaptateur AUDIO (ADAPTATEUR, jamais importe par la logique). Mappe les
// evenements de jeu emis par le loop pur en cues sonores et TRACE chaque
// declenchement. Le retour sonore reel (lecture du WAV) vit dans le backend
// navigateur ; ici, la partie mecaniquement verifiable = le mapping + la trace.
//
// BUG CORRIGE (2026-07-26, test navigateur reel) : les imports Node (node:fs/
// node:path/node:url) etaient statiques en tete de fichier, alors que ce module
// est importe DIRECTEMENT par browser/main.mjs pour cueFor() (pure, zero
// dependance Node). Un navigateur ne resout pas ces specifiers -> l'import
// ECHOUE -> tout le graphe de modules du jeu refuse de charger -> le jeu ne
// demarre JAMAIS en navigateur (aucune erreur console visible, juste un canvas
// vide). Preuve : network log, 3 requetes node:fs/node:path/node:url en FAILED.
// Fix : imports Node en dynamic import(), guardes par la meme detection
// browser/node deja utilisee par exit.mjs (detectHost). Cote Node, rien ne
// change (traceAudio() et le CLI runner restent synchrones a l'usage).
import { boot, step } from '../../../05_SYSTEMS/game_loop/loop.mjs';
import { translate } from '../../../05_SYSTEMS/input/input.mjs';

const IS_BROWSER = typeof window !== 'undefined' && typeof document !== 'undefined';

let existsSync, readFileSync, ASSET_DIR_VALUE, BOUNCE_ASSET_VALUE;
if (!IS_BROWSER) {
  ({ existsSync, readFileSync } = await import('node:fs'));
  const { dirname, join } = await import('node:path');
  const { fileURLToPath } = await import('node:url');
  const HERE = dirname(fileURLToPath(import.meta.url));
  // Assets audio deplaces vers 04_ASSETS/audio/ (repo_map: asset.audio). Depuis
  // 06_RUNTIME/adapters/presentation/ : remonter 3 niveaux jusqu'a la racine du jeu.
  ASSET_DIR_VALUE = join(HERE, '..', '..', '..', '04_ASSETS', 'audio');
  BOUNCE_ASSET_VALUE = join(ASSET_DIR_VALUE, 'bounce.wav');
}
export const ASSET_DIR = ASSET_DIR_VALUE;
export const BOUNCE_ASSET = BOUNCE_ASSET_VALUE;

// Vocabulaire de cue FERME : quel son declenche quel evenement.
export function cueFor(event) {
  if (event?.type === 'bounce') return 'bounce';
  if (event?.type === 'score') return 'score';
  return null;
}

// Adaptateur : consomme un flux d'evenements, produit une trace de cues. Le backend
// navigateur surchargerait play() pour jouer reellement le WAV (new Audio(...).play()).
export class AudioAdapter {
  constructor(assetPath = BOUNCE_ASSET) {
    this.assetPath = assetPath;
    this.trace = [];
  }

  onEvents(events) {
    for (const e of events || []) {
      const cue = cueFor(e);
      if (cue === 'bounce') this.trace.push({ cue, asset: 'bounce.wav', event: e });
      else if (cue) this.trace.push({ cue, event: e });
    }
  }

  bounceCount() {
    return this.trace.filter((t) => t.cue === 'bounce').length;
  }
}

// Preuve `artifact` (core.audio) : l'asset existe, et son declenchement AU REBOND
// est trace. Joue une partie jusqu'a obtenir un rebond et verifie la trace.
export function traceAudio(seed = 1, maxTicks = 5000) {
  const adapter = new AudioAdapter();
  let s = boot(seed);
  for (let i = 0; i < maxTicks && adapter.bounceCount() === 0; i += 1) {
    const raw = { p1: s.ball.y > s.p1.y + 12 ? 'down' : 'up', p2: s.ball.y > s.p2.y + 12 ? 'down' : 'up' };
    const { state: ns, events } = step(s, translate(raw));
    adapter.onEvents(events);
    s = ns;
  }
  const assetExists = existsSync(BOUNCE_ASSET);
  const assetBytes = assetExists ? readFileSync(BOUNCE_ASSET).length : 0;
  const bounces = adapter.bounceCount();
  return {
    passed: assetExists && assetBytes > 0 && bounces > 0,
    assetExists, assetBytes, bounceCuesTraced: bounces,
    firstTrace: adapter.trace[0] || null,
  };
}

if (typeof process !== 'undefined' && process.argv[1]?.endsWith('audio.mjs')) {
  const r = traceAudio(1);
  process.stdout.write(JSON.stringify(r, null, 1) + '\n');
  process.exit(r.passed ? 0 : 1);
}
