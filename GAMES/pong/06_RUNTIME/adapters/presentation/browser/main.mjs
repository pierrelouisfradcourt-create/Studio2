// PONG — adaptateur NAVIGATEUR reel (ADAPTATEUR, jamais importe par la logique).
// Importe la logique pure, la rend sur un <canvas> via le MEME drawState() que la
// capture headless, lit le clavier via input.translate(), joue le WAV au rebond, et
// cable les boutons Quitter et Rejouer. Boucle de temps reel = requestAnimationFrame ;
// elle vit ICI (adaptateur), jamais dans la logique.
//
// Delta du run (playtest-2026-07-27) :
//   - MODE SOLO (play.solo_opponent) : par defaut le joueur tient la raquette GAUCHE
//     (W/S) et l'IA (05_SYSTEMS/input/ai.mjs) tient la raquette DROITE ; un second
//     joueur peut reprendre la droite aux fleches (override humain a la volee).
//   - RELANCE (core.restart) : bouton "Rejouer" visible + touche R -> replay().
//   - SORTIE (core.exit) : le clic Quitter ARRETE la boucle (effet observable), il ne
//     se fie plus a window.close() (inerte). La logique de decision est extraite dans
//     createController() pour etre prouvee mecaniquement hors navigateur
//     (07_TESTS/unit/{restart_offer,exit_stop}.test.mjs).
import { boot, step } from '../../../../05_SYSTEMS/game_loop/loop.mjs';
import { restart, isOver } from '../../../../05_SYSTEMS/game_state/state.mjs';
import { translate } from '../../../../05_SYSTEMS/input/input.mjs';
import { soloAiDir } from '../../../../05_SYSTEMS/input/ai.mjs';
import { drawState, VIEW_W, VIEW_H } from '../draw.mjs';
import { cueFor } from '../audio.mjs';
import { requestExit } from '../exit.mjs';

// Entree brute du mode SOLO : joueur = raquette GAUCHE (p1). La raquette DROITE (p2)
// est tenue par l'IA, SAUF si un second joueur agit aux fleches (override).
export function soloRaw(humanRaw, state) {
  const p2h = humanRaw.p2 && (humanRaw.p2.up === true || humanRaw.p2.down === true);
  const p2 = p2h ? humanRaw.p2 : soloAiDir('p2', state.p2.y, state.ball);
  return { p1: humanRaw.p1, p2 };
}

// Controleur PUR (aucun DOM, aucun rAF, aucun canvas) : c'est la logique cablee que
// les tests exercent directement. Detient l'etat, le drapeau `running`, et expose
// tick/replay/stop.
export function createController(seed = 1) {
  let state = boot(seed);
  let running = true;
  return {
    get state() { return state; },
    get running() { return running; },
    // avance d'un tick en mode solo ; no-op si la boucle est arretee (sortie).
    tick(humanRaw = { p1: {}, p2: {} }) {
      if (!running) return [];
      const { state: ns, events } = step(state, translate(soloRaw(humanRaw, state)));
      state = ns;
      return events;
    },
    replay() { state = restart(seed); running = true; },   // relance offerte au joueur
    stop() { running = false; },                            // sortie : boucle arretee (observable)
  };
}

// Surface -> CanvasRenderingContext2D (backend navigateur du meme code de dessin).
function canvasSurface(ctx) {
  return {
    clear(r, g, b) { ctx.fillStyle = `rgb(${r},${g},${b})`; ctx.fillRect(0, 0, VIEW_W, VIEW_H); },
    fillRect(x, y, w, h, r, g, b) { ctx.fillStyle = `rgb(${r},${g},${b})`; ctx.fillRect(x, y, w, h); },
  };
}

export function mount(canvas, audioEl, exitBtn, replayBtn) {
  canvas.width = VIEW_W;
  canvas.height = VIEW_H;
  const ctx = canvas.getContext('2d');
  const surface = canvasSurface(ctx);

  const game = createController(1);
  const keys = new Set();
  window.addEventListener('keydown', (e) => keys.add(e.key));
  window.addEventListener('keyup', (e) => keys.delete(e.key));

  function humanRaw() {
    // W/S = joueur gauche ; fleches Haut/Bas = second joueur optionnel (droite).
    return {
      p1: { up: keys.has('w'), down: keys.has('s') },
      p2: { up: keys.has('ArrowUp'), down: keys.has('ArrowDown') },
    };
  }

  function playBounce() {
    if (!audioEl) return;
    try { audioEl.currentTime = 0; audioEl.play(); } catch { /* autoplay bloque : sans effet */ }
  }

  if (exitBtn) {
    exitBtn.addEventListener('click', () => {
      const r = requestExit('browser');
      if (r && r.stopped) {
        game.stop();                 // arrete la boucle
        drawState(game.state, surface); // fige l'etat final a l'ecran (effet observable)
      }
    });
  }
  if (replayBtn) replayBtn.addEventListener('click', () => game.replay());
  window.addEventListener('keydown', (e) => { if (e.key === 'r' && isOver(game.state)) game.replay(); });

  function frame() {
    if (game.running) {
      const events = game.tick(humanRaw());
      if (events.some((ev) => cueFor(ev) === 'bounce')) playBounce();
    }
    drawState(game.state, surface);   // redessine toujours : montre l'etat fige a la sortie/fin
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

// Auto-montage si charge dans une page contenant les elements attendus.
if (typeof document !== 'undefined') {
  window.addEventListener('DOMContentLoaded', () => {
    const canvas = document.getElementById('game');
    if (canvas) {
      mount(
        canvas,
        document.getElementById('bounce'),
        document.getElementById('exit'),
        document.getElementById('replay'),
      );
    }
  });
}
