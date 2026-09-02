// PONG — adaptateur SORTIE (ADAPTATEUR, jamais importe par la logique).
// game.exit : quitter proprement, comportement defini PAR RUNTIME.
//   - node / godot-embed : process.exit(0) (preuve mecanique CONSERVEE).
//   - navigateur : window.close() est IGNORE par le navigateur sur un onglet non
//     ouvert par script (playtest-2026-07-27 : "Quitter inerte" — le clic ne
//     produisait aucun effet). requestExit ne s'y FIE donc PLUS : elle le tente en
//     best-effort mais RETOURNE un signal de sortie {stopped:true} que l'appelant
//     (browser/main.mjs) utilise pour produire l'effet OBSERVABLE reel : arret de la
//     boucle de jeu + affichage d'un etat final. C'est le delta core.exit du run.
export function requestExit(host = detectHost()) {
  if (host === 'browser') {
    if (typeof window !== 'undefined' && typeof window.close === 'function') {
      try { window.close(); } catch { /* onglet non fermable par script : ignore */ }
    }
    return { host: 'browser', stopped: true, code: 0 };
  }
  // node / godot-embed : sortie propre, code 0 (ne retourne pas si process.exit existe).
  if (typeof process !== 'undefined' && typeof process.exit === 'function') {
    process.exit(0);
  }
  return { host, stopped: true, code: 0 };
}

function detectHost() {
  if (typeof window !== 'undefined' && typeof document !== 'undefined') return 'browser';
  return 'node';
}

// CLI : `node exit.mjs` -> quitte avec le code 0 (preuve bot_action mecaniquement
// verifiable : le processus se termine, code de sortie 0).
// BUG CORRIGE (2026-07-26, test navigateur reel) : `process` non garde ici jetait
// un ReferenceError AU CHARGEMENT du module en navigateur (process n'existe pas) —
// meme famille que le defaut corrige dans audio.mjs le meme jour. Un module qui
// leve a l'evaluation casse tout le graphe d'imports statiques de main.mjs : le
// jeu ne demarrait jamais (aucune erreur console visible sans probe dediee).
if (typeof process !== 'undefined' && process.argv[1]?.endsWith('exit.mjs')) {
  process.stdout.write('exit: sortie propre, code 0\n');
  requestExit('node');
}
