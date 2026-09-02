// godot_bin.mjs — resolution du binaire Godot. Une seule responsabilite : OU est Godot.
// Le binaire vit hors repo (installation utilisateur) : aucun chemin absolu n'est
// versionne. Ordre : env GODOT_BIN -> forge/godot.config.json -> erreur.
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, '../..');
const DEFAULT_CONFIG = resolve(HERE, 'godot.config.json');

const HOWTO =
  'Configure Godot : soit la variable d environnement GODOT_BIN, soit le champ ' +
  '"godot_bin" dans forge/godot.config.json (cf. godot.config.example.json). ' +
  'Utiliser l executable CONSOLE (…_console.exe) pour capturer stdout.';

/**
 * @param {{env?: object, configPath?: string}} [opts]
 * @returns {string} chemin absolu vers l executable Godot
 */
export function resolveGodotBin(opts = {}) {
  const env = opts.env ?? process.env;
  const configPath = opts.configPath ?? DEFAULT_CONFIG;

  let candidate = null;
  let origin = null;

  if (env.GODOT_BIN) {
    candidate = env.GODOT_BIN;
    origin = 'GODOT_BIN';
  } else if (existsSync(configPath)) {
    let parsed;
    try {
      parsed = JSON.parse(readFileSync(configPath, 'utf-8'));
    } catch (e) {
      throw new Error(`godot.config.json illisible (${configPath}) : ${e.message}`);
    }
    if (parsed && typeof parsed.godot_bin === 'string' && parsed.godot_bin.length > 0) {
      candidate = parsed.godot_bin;
      origin = configPath;
    }
  }

  if (!candidate) throw new Error(`Binaire Godot non configure. ${HOWTO}`);
  candidate = resolve(REPO_ROOT, candidate);
  if (!existsSync(candidate)) {
    throw new Error(`Binaire Godot introuvable sur le disque : ${candidate} (declare par ${origin}). ${HOWTO}`);
  }
  return candidate;
}
