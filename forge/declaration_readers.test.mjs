// Tests de declaration_readers.mjs — node --test. Fixtures ephemeres, aucune dependance
// au repo reel (meme discipline que studio_selfaudit.test.mjs : le repo bouge, les tests non).
//
// Les 3 CAS DE VERITE TERRAIN du 2026-07-19 sont reproduits a l'identique en fixture :
//   C1 .claude/agents/*.md sans lecteur et sans `description:`
//   C2 tool_permission_matrix.json lu par autopilot.py qui ignore `agent_id`
//   C3 champs custom hors-schema + `domain:` vers un dossier inexistant
// Chacun a son CAS NEGATIF jumeau : un fichier declare ET lu ne doit PAS etre signale,
// sinon le capteur ne discrimine rien et ne prouve rien.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import {
  loadWatchlist,
  isExcludedDir,
  listCorpus,
  needlesFor,
  findMentions,
  parseFrontmatter,
  extractPathTokens,
  auditAgentFile,
  collectDeclaredFields,
  readersNamingField,
  auditDeclaration,
  runDeclarationAudit,
} from './declaration_readers.mjs';

const SCAN = {
  code_extensions: ['.py', '.mjs', '.js', '.rs'],
  data_extensions: ['.json', '.yaml'],
  exclude_dirs: ['node_modules', '.git', 'worktrees', '.claude/worktrees', 'graphify-out'],
  exclude_dir_patterns: ['^\\.venv', '_MIGRATED_HOLD$'],
  self_files: ['forge/declaration_readers.mjs', 'forge/declaration_watchlist.json'],
};

const AGENT_DECL = {
  id: 'claude-agents',
  kind: 'agent_md',
  dir: '.claude/agents',
  extension: '.md',
  schema_keys: ['name', 'description', 'model', 'tools', 'allowed-tools', 'disallowedTools', 'color'],
  required_keys: ['description'],
  path_valued_keys: ['domain', 'forbidden_paths'],
};

const MATRIX_DECL = {
  id: 'tool-permission-matrix',
  kind: 'policy_json',
  path: 'lab/agent_policy/tool_permission_matrix.json',
  field_scopes: ['$', '$.global_constraints', '$.tool_rules[*]'],
  ignore_fields: ['$schema'],
};

function tmpRepo() {
  return mkdtempSync(join(tmpdir(), 'declread-'));
}
function put(root, rel, content) {
  const p = join(root, rel);
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, content, 'utf-8');
  return p;
}
function writeWatchlist(root, declarations, scan = SCAN) {
  put(root, 'forge/declaration_watchlist.json', JSON.stringify({ scan, declarations }));
}
/** Reproduit la matrice reelle (forme, pas les 62 regles). */
function realShapedMatrix() {
  return JSON.stringify({
    $schema: '../../schemas/tool_permission_matrix.schema.json',
    policy_version: '2026-05-08',
    deny_by_default: true,
    default_effect: 'DENY',
    global_constraints: { can_any_agent_merge: false },
    tool_rules: [
      { agent_id: 'producer', autonomy_level: '0_READ_ONLY', tool: 'read_repo', effect: 'ALLOW', human_review_required: false },
      { agent_id: 'code', autonomy_level: '2_CONTROL_PLANE_ONLY', tool: 'propose_patch', effect: 'ALLOW', human_review_required: true },
    ],
  });
}
/** Reproduit _check_tool_permission : filtre sur `tool` + `effect`, ignore `agent_id`. */
const AUTOPILOT_LIKE = `
_pm_path = REPO / "lab/agent_policy/tool_permission_matrix.json"
_TOOL_PERMISSION_MATRIX = json.loads(_pm_path.read_text(encoding="utf-8"))
def _check_tool_permission(chain_id):
    rules = _TOOL_PERMISSION_MATRIX.get("tool_rules", [])
    for rule in rules:
        if rule.get("tool") == tool and rule.get("effect") == "ALLOW":
            return (True, None)
    return (False, "deny_by_default")
`;

// ---------------------------------------------------------------- primitives

test('isExcludedDir : node_modules, .venv*, worktrees, *_MIGRATED_HOLD exclus', () => {
  for (const d of ['node_modules', 'a/b/node_modules', '.venv312', 'x/.venv', 'worktrees',
    '.claude/worktrees', 'repos/GAMES/studioV2_MIGRATED_HOLD', 'graphify-out']) {
    assert.equal(isExcludedDir(d, SCAN), true, d);
  }
  for (const d of ['scripts', 'lab/agent_policy', 'src/chess']) {
    assert.equal(isExcludedDir(d, SCAN), false, d);
  }
});

test('listCorpus : classe code vs donnees, saute les exclusions et le capteur lui-meme', () => {
  const root = tmpRepo();
  put(root, 'autopilot.py', 'x');
  put(root, 'a/b.mjs', 'x');
  put(root, 'c/d.json', '{}');
  put(root, 'README.md', 'x'); // .md jamais scanne
  put(root, 'node_modules/pkg/index.js', 'x');
  put(root, '.venv312/lib/mod.py', 'x');
  put(root, 'repos/GAMES/studioV2_MIGRATED_HOLD/autopilot.py', 'x');
  put(root, 'forge/declaration_readers.mjs', 'x');
  const c = listCorpus(root, SCAN);
  assert.deepEqual(c.code, ['a/b.mjs', 'autopilot.py']);
  assert.deepEqual(c.data, ['c/d.json']);
});

test('needlesFor : chemin posix + basename + variantes Windows', () => {
  const n = needlesFor('lab/agent_policy/tool_permission_matrix.json');
  assert.ok(n.includes('lab/agent_policy/tool_permission_matrix.json'));
  assert.ok(n.includes('tool_permission_matrix.json'));
  assert.ok(n.some((x) => x.includes('\\')));
  // REPERTOIRE : le nom nu (« agents ») matcherait la moitie du repo -> jamais utilise.
  const d = needlesFor('.claude/agents', { includeBasename: false });
  assert.ok(!d.includes('agents'));
  assert.ok(d.includes('.claude/agents'));
});

test('findMentions : rapporte chemin:ligne, ignore les fichiers muets', () => {
  const root = tmpRepo();
  put(root, 'reader.py', 'a\nb\nopen("lab/x.json")\n');
  put(root, 'muet.py', 'rien\n');
  const hits = findMentions(root, needlesFor('lab/x.json'), ['reader.py', 'muet.py']);
  assert.equal(hits.length, 1);
  assert.equal(hits[0].path, 'reader.py');
  assert.deepEqual(hits[0].lines, [3]);
});

test('parseFrontmatter : frontmatter non ferme -> on ne conclut rien', () => {
  assert.equal(parseFrontmatter('---\nname: x\ncorps sans fin').present, false);
  assert.equal(parseFrontmatter('pas de frontmatter').present, false);
  const fm = parseFrontmatter('---\nname: x\nmodel: sonnet\n---\ncorps\n');
  assert.equal(fm.present, true);
  assert.deepEqual(fm.keys.map((k) => k.key), ['name', 'model']);
});

test('extractPathTokens : seuls les jetons contenant "/" sont des chemins', () => {
  assert.deepEqual(extractPathTokens('src/neural/ ml/'), ['src/neural', 'ml']);
  assert.deepEqual(extractPathTokens('[tests/, eval/, oracle/]'), ['tests', 'eval', 'oracle']);
  // conservateur : de la prose sans slash n'est JAMAIS lue comme un chemin
  assert.deepEqual(extractPathTokens('Mecaniques Godot et juice'), []);
  assert.deepEqual(extractPathTokens('producteur-dur'), []);
});

// ------------------------------------------------- CAS 1 : agents sans lecteur

test('CAS 1 — .claude/agents/*.md : aucun code ne les lit -> D1', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/qa-lead.md', '---\nname: qa-lead\nmodel: claude-sonnet-4-6\n---\nblabla\n');
  put(root, 'autopilot.py', 'print("rien a voir")\n');
  writeWatchlist(root, [AGENT_DECL]);
  const [e] = auditDeclaration(root, AGENT_DECL, listCorpus(root, SCAN));
  assert.equal(e.file, '.claude/agents/qa-lead.md');
  assert.equal(e.reader_verdict, 'AUCUN_LECTEUR_CODE');
  assert.equal(e.readers.length, 0);
  assert.ok(e.findings.some((f) => f.rule === 'D1'));
});

test('CAS 1 — negatif : un code qui LIT le dossier .claude/agents -> pas de D1', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/qa-lead.md', '---\nname: qa-lead\ndescription: x\nmodel: sonnet\n---\n');
  put(root, 'loader.mjs', 'const files = readdirSync(".claude/agents");\n');
  const [e] = auditDeclaration(root, AGENT_DECL, listCorpus(root, SCAN));
  assert.equal(e.reader_verdict, 'MENTIONNE_PAR_CODE');
  assert.deepEqual(e.readers, [{ path: 'loader.mjs', lines: [1] }]);
  assert.deepEqual(e.findings, []);
});

test('CAS 1 — negatif : une mention en .md (doc) ne compte PAS comme lecteur', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/qa-lead.md', '---\nname: qa-lead\ndescription: x\n---\n');
  put(root, 'docs/ARCHI.md', 'les agents vivent dans .claude/agents/qa-lead.md\n');
  const [e] = auditDeclaration(root, AGENT_DECL, listCorpus(root, SCAN));
  assert.equal(e.reader_verdict, 'AUCUN_LECTEUR_CODE');
});

test('CAS 1 — une mention en .json est rapportee en other_mentions, pas en lecteur', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/qa-lead.md', '---\nname: qa-lead\ndescription: x\n---\n');
  put(root, 'EVIDENCE/reports/compact-state.json', '{"modified_files": [".claude/agents/qa-lead.md"]}\n');
  const [e] = auditDeclaration(root, AGENT_DECL, listCorpus(root, SCAN));
  assert.equal(e.reader_verdict, 'AUCUN_LECTEUR_CODE');
  assert.equal(e.readers.length, 0);
  assert.equal(e.other_mentions[0].path, 'EVIDENCE/reports/compact-state.json');
});

// ---------------------------------- CAS 2 : matrice lue mais agent_id jamais lu

test('CAS 2 — matrice LUE par autopilot.py mais `agent_id` nomme par aucun lecteur -> D2', () => {
  const root = tmpRepo();
  put(root, 'lab/agent_policy/tool_permission_matrix.json', realShapedMatrix());
  put(root, 'autopilot.py', AUTOPILOT_LIKE);
  const [e] = auditDeclaration(root, MATRIX_DECL, listCorpus(root, SCAN));
  assert.equal(e.reader_verdict, 'MENTIONNE_PAR_CODE');
  assert.equal(e.readers[0].path, 'autopilot.py');
  assert.equal(e.field_analysis, 'effectuee');
  const unread = e.unread_fields.map((u) => u.field);
  assert.ok(unread.includes('agent_id'), `agent_id attendu dans ${unread}`);
  assert.ok(unread.includes('autonomy_level'));
  assert.ok(unread.includes('human_review_required'));
  // discrimination : ce que le lecteur nomme VRAIMENT n'est pas signale
  assert.ok(!unread.includes('tool_rules'));
  assert.ok(!unread.includes('effect'));
  assert.ok(!unread.includes('deny_by_default'));
  assert.ok(e.findings.some((f) => f.rule === 'D2' && f.detail.includes('agent_id')));
  // couverture PAR LECTEUR : le fait brut « ce lecteur-ci ignore agent_id »
  const cov = e.reader_field_coverage.find((c) => c.reader === 'autopilot.py');
  assert.ok(cov.named.includes('tool_rules'));
  assert.ok(cov.not_named.includes('agent_id'));
  assert.ok(e.findings.some((f) => f.rule === 'D7' && f.detail.includes('autopilot.py') && f.detail.includes('agent_id')));
});

test('CAS 2 bis — le fichier est LU par un AUTRE lecteur qui nomme agent_id : D2 se tait, D7 montre quand meme que autopilot.py l\'ignore', () => {
  // Situation REELLE du repo : agent_pr_operator.py charge la matrice ET contient le mot
  // agent_id (pour son task packet). D2 (global) doit se TAIRE — zero faux positif — mais
  // la couverture par lecteur doit rester factuelle sur autopilot.py.
  const root = tmpRepo();
  put(root, 'lab/agent_policy/tool_permission_matrix.json', realShapedMatrix());
  put(root, 'autopilot.py', AUTOPILOT_LIKE);
  put(root, 'scripts/studioV2/agent_pr_operator.py',
    'POLICY = Path("lab/agent_policy/tool_permission_matrix.json")\nagent_id = packet.get("agent_id")\nif policy.get("deny_by_default"): pass\n');
  const [e] = auditDeclaration(root, MATRIX_DECL, listCorpus(root, SCAN));
  assert.equal(e.readers.length, 2);
  assert.ok(!e.unread_fields.map((u) => u.field).includes('agent_id'), 'D2 doit se taire : un lecteur nomme agent_id');
  const cov = e.reader_field_coverage.find((c) => c.reader === 'autopilot.py');
  assert.ok(cov.not_named.includes('agent_id'));
  assert.ok(e.findings.some((f) => f.rule === 'D7' && f.detail.includes('autopilot.py') && f.detail.includes('agent_id')));
});

test('D7 — un lecteur qui nomme TOUS les champs declares ne produit aucun constat', () => {
  const root = tmpRepo();
  put(root, 'lab/agent_policy/tool_permission_matrix.json', realShapedMatrix());
  put(root, 'complet.py',
    'p = "lab/agent_policy/tool_permission_matrix.json"\n'
    + 'policy_version deny_by_default default_effect global_constraints can_any_agent_merge\n'
    + 'tool_rules agent_id autonomy_level tool effect human_review_required\n');
  const [e] = auditDeclaration(root, MATRIX_DECL, listCorpus(root, SCAN));
  assert.deepEqual(e.unread_fields, []);
  assert.deepEqual(e.findings, []);
});

test('CAS 2 — negatif : un lecteur qui filtre SUR agent_id -> aucun D2 sur agent_id', () => {
  const root = tmpRepo();
  put(root, 'lab/agent_policy/tool_permission_matrix.json', realShapedMatrix());
  put(root, 'autopilot.py', `${AUTOPILOT_LIKE}\n        if rule.get("agent_id") != caller: continue\n`);
  const [e] = auditDeclaration(root, MATRIX_DECL, listCorpus(root, SCAN));
  assert.ok(!e.unread_fields.map((u) => u.field).includes('agent_id'));
});

test('CAS 2 — conservatisme : aucun lecteur -> analyse de champs NON faite (pas de bruit D2)', () => {
  const root = tmpRepo();
  put(root, 'lab/agent_policy/tool_permission_matrix.json', realShapedMatrix());
  put(root, 'autre.py', 'x = 1\n');
  const [e] = auditDeclaration(root, MATRIX_DECL, listCorpus(root, SCAN));
  assert.equal(e.reader_verdict, 'AUCUN_LECTEUR_CODE');
  assert.equal(e.field_analysis, 'ignoree_aucun_lecteur');
  assert.deepEqual(e.unread_fields, []);
  assert.deepEqual(e.findings.map((f) => f.rule), ['D1']);
});

test('collectDeclaredFields : respecte les scopes, ignore $schema et les noms < 3 char', () => {
  const doc = { $schema: 'x', ab: 1, policy_version: '1', global_constraints: { can_any_agent_merge: false }, tool_rules: [{ agent_id: 'a' }, { effect: 'ALLOW' }], hors_scope: { profond: 1 } };
  const fields = collectDeclaredFields(doc, ['$', '$.global_constraints', '$.tool_rules[*]'], ['$schema']).map((f) => f.field);
  assert.ok(fields.includes('policy_version'));
  assert.ok(fields.includes('can_any_agent_merge'));
  assert.ok(fields.includes('agent_id'));
  assert.ok(fields.includes('effect'));
  assert.ok(!fields.includes('$schema'));
  assert.ok(!fields.includes('ab'));
  assert.ok(!fields.includes('profond')); // hors des scopes declares -> jamais inference
});

test('readersNamingField : mot entier, toutes syntaxes, pas de sous-chaine accidentelle', () => {
  const root = tmpRepo();
  put(root, 'a.py', 'rule.get("agent_id")\n');
  put(root, 'b.mjs', 'const x = rule.effect;\n');
  put(root, 'c.py', 'my_agent_identity = 1\n'); // NE doit PAS compter comme "agent_id"
  assert.deepEqual(readersNamingField(root, 'agent_id', ['a.py', 'b.mjs', 'c.py']), ['a.py']);
  assert.deepEqual(readersNamingField(root, 'effect', ['a.py', 'b.mjs']), ['b.mjs']);
});

// ------------------------------ CAS 3 : champs hors-schema + domain inexistant

test('CAS 3 — champs custom hors-schema + description absente + domain inexistant', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/gameplay-programmer.md',
    '---\nname: gameplay-programmer\nmodel: claude-sonnet-4-6\nrole: Mecaniques Godot\ndomain: assets/godot/\nescalates_to: producteur-dur\n---\n');
  const findings = auditAgentFile(root, '.claude/agents/gameplay-programmer.md', AGENT_DECL);
  const rules = findings.map((f) => f.rule);
  assert.ok(rules.includes('D4'), 'description manquante');
  assert.equal(findings.filter((f) => f.rule === 'D5').length, 3); // role, domain, escalates_to
  assert.ok(findings.some((f) => f.rule === 'D5' && f.detail.includes('role')));
  assert.ok(findings.some((f) => f.rule === 'D5' && f.detail.includes('escalates_to')));
  assert.ok(findings.some((f) => f.rule === 'D6' && f.detail.includes('assets/godot')));
});

test('CAS 3 — forbidden_paths : chemins inexistants signales, chemins reels ignores', () => {
  const root = tmpRepo();
  mkdirSync(join(root, 'tests'), { recursive: true });
  put(root, '.claude/agents/producteur-dur.md',
    '---\nname: producteur-dur\ndescription: d\nforbidden_paths: [tests/, oracle/]\n---\n');
  const findings = auditAgentFile(root, '.claude/agents/producteur-dur.md', AGENT_DECL);
  const d6 = findings.filter((f) => f.rule === 'D6');
  assert.equal(d6.length, 1);
  assert.ok(d6[0].detail.includes('oracle'));
});

test('CAS 3 — negatif : agent 100% conforme -> AUCUN constat de schema', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/ai-programmer.md',
    '---\nname: ai-programmer\ndescription: Use when working on the neural path.\nmodel: sonnet\ndisallowedTools: Write, Edit\n---\ncorps\n');
  assert.deepEqual(auditAgentFile(root, '.claude/agents/ai-programmer.md', AGENT_DECL), []);
});

test('CAS 3 — negatif : domain vers un dossier QUI EXISTE -> pas de D6', () => {
  const root = tmpRepo();
  mkdirSync(join(root, 'GAMES/chess_tcg'), { recursive: true });
  put(root, '.claude/agents/technical-artist.md', '---\nname: t\ndescription: d\ndomain: GAMES/chess_tcg/\n---\n');
  const findings = auditAgentFile(root, '.claude/agents/technical-artist.md', AGENT_DECL);
  assert.equal(findings.filter((f) => f.rule === 'D6').length, 0);
  assert.equal(findings.filter((f) => f.rule === 'D5').length, 1); // domain reste hors-schema
});

test('frontmatter absent -> D3 seul, aucune sur-interpretation', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/nu.md', 'juste du texte, pas de frontmatter\n');
  assert.deepEqual(auditAgentFile(root, '.claude/agents/nu.md', AGENT_DECL).map((f) => f.rule), ['D3']);
});

// --------------------------------------------------------------- integration

test('runDeclarationAudit : bout-en-bout sur un repo fixture reproduisant les 3 cas', () => {
  const root = tmpRepo();
  // C1 + C3
  put(root, '.claude/agents/qa-lead.md', '---\nname: qa-lead\nmodel: claude-sonnet-4-6\nrole: QA\ndomain: design/\n---\n');
  // C2
  put(root, 'lab/agent_policy/tool_permission_matrix.json', realShapedMatrix());
  put(root, 'autopilot.py', AUTOPILOT_LIKE);
  // temoin POSITIF : declare ET lu ET tous champs nommes
  put(root, 'forge/studio_expectations.json', JSON.stringify({ doc_claims: [], connectors: {} }));
  put(root, 'forge/studio_selfaudit.mjs',
    "const p = join(repoRoot, 'scripts', 'forge', 'studio_expectations.json');\nexp.doc_claims; exp.connectors;\n");
  writeWatchlist(root, [
    AGENT_DECL,
    MATRIX_DECL,
    { id: 'studio-expectations', kind: 'policy_json', path: 'forge/studio_expectations.json', field_scopes: ['$'], ignore_fields: [] },
  ]);

  const r = runDeclarationAudit(root);
  const byFile = Object.fromEntries(r.entries.map((e) => [e.file, e]));

  assert.equal(byFile['.claude/agents/qa-lead.md'].reader_verdict, 'AUCUN_LECTEUR_CODE');
  assert.ok(byFile['.claude/agents/qa-lead.md'].findings.some((f) => f.rule === 'D6'));
  assert.equal(byFile['lab/agent_policy/tool_permission_matrix.json'].reader_verdict, 'MENTIONNE_PAR_CODE');
  assert.ok(byFile['lab/agent_policy/tool_permission_matrix.json'].unread_fields.map((u) => u.field).includes('agent_id'));

  // TEMOIN NEGATIF : declare + lu + champs nommes -> zero constat
  const temoin = byFile['forge/studio_expectations.json'];
  assert.equal(temoin.reader_verdict, 'MENTIONNE_PAR_CODE');
  assert.deepEqual(temoin.unread_fields, []);
  assert.deepEqual(temoin.findings, []);

  assert.ok(r.summary.without_code_reader >= 1);
  assert.ok(r.out_of_scope.length >= 4);
});

test('runDeclarationAudit : deterministe (deux passes identiques)', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/a.md', '---\nname: a\nrole: r\n---\n');
  put(root, 'x.py', 'pass\n');
  writeWatchlist(root, [AGENT_DECL]);
  assert.equal(JSON.stringify(runDeclarationAudit(root)), JSON.stringify(runDeclarationAudit(root)));
});

test('manifeste REEL du repo : chargeable et bien forme', () => {
  const repoRoot = new URL('../..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
  const wl = loadWatchlist(repoRoot);
  assert.ok(Array.isArray(wl.declarations) && wl.declarations.length > 0);
  for (const d of wl.declarations) {
    assert.ok(d.id && d.kind, 'id + kind obligatoires');
    assert.ok(d.path || d.dir, 'path ou dir obligatoire');
  }
  assert.ok((wl.scan.exclude_dirs || []).includes('node_modules'));
});

// ------------------------------------------- EXTENSION 2026-07-19 : nouveaux leviers
// Deux leviers de manifeste ont ete ajoutes pour ETENDRE la watchlist sans introduire de
// faux positif. Les deux sont testes avec leur jumeau NEGATIF : sans le levier, le capteur
// doit dire l'inverse — sinon le levier ne discrimine rien et sert juste a faire taire.

const SCAN_SH = { ...SCAN, code_extensions: [...SCAN.code_extensions, '.sh'] };

test('non_reader_mentions : une mention prouvee non-lisante (commentaire) n\'est PAS un lecteur, et reste imprimee avec sa raison', () => {
  // Cas REEL : deploy_studio.sh a cesse de generer les fiches le 2026-07-19 ; il n'en reste
  // qu'un commentaire d'archive. Le compter comme lecteur MASQUAIT le fait qu'aucun code du
  // repo ne lit ces fiches.
  const root = tmpRepo();
  put(root, '.claude/agents/qa-lead.md', '---\nname: qa-lead\ndescription: d\n---\n');
  put(root, 'deploy_studio.sh', '# GENERATION RETIREE : ce script ecrivait .claude/agents/qa-lead.md\n');
  const decl = { ...AGENT_DECL, non_reader_mentions: [{ path: 'deploy_studio.sh', reason: 'commentaire d archive, plus aucune ecriture' }] };
  const [e] = auditDeclaration(root, decl, listCorpus(root, SCAN_SH));
  assert.equal(e.reader_verdict, 'AUCUN_LECTEUR_CODE');
  assert.equal(e.readers.length, 0);
  assert.deepEqual(e.non_reader_mentions.map((m) => m.path), ['deploy_studio.sh']);
  assert.match(e.non_reader_mentions[0].reason, /archive/); // rien n'est masque
  assert.deepEqual(e.non_reader_mentions[0].lines, [1]);
  assert.ok(e.findings.some((f) => f.rule === 'D1'), 'le masque leve, D1 redevient visible');
  // JUMEAU NEGATIF : sans l'exclusion, le meme fichier compte comme lecteur.
  const [e2] = auditDeclaration(root, AGENT_DECL, listCorpus(root, SCAN_SH));
  assert.equal(e2.reader_verdict, 'MENTIONNE_PAR_CODE');
  assert.deepEqual(e2.readers.map((r) => r.path), ['deploy_studio.sh']);
  assert.deepEqual(e2.non_reader_mentions, []);
});

test('external_consumer : D1 non emis (consommateur hors repo) mais les constats reels ne sont PAS etouffes', () => {
  const root = tmpRepo();
  put(root, '.claude/agents/casse.md', '---\nname: casse\nmodel: sonnet\n---\n'); // pas de description:
  put(root, 'x.py', 'pass\n');
  const decl = { ...AGENT_DECL, external_consumer: 'runtime Claude Code (hors repo)' };
  const [e] = auditDeclaration(root, decl, listCorpus(root, SCAN));
  assert.equal(e.reader_verdict, 'AUCUN_LECTEUR_CODE', 'le fait brut reste affiche');
  assert.equal(e.external_consumer, 'runtime Claude Code (hors repo)');
  assert.ok(!e.findings.some((f) => f.rule === 'D1'), '« lettre morte » serait faux : un runtime externe la consomme');
  assert.ok(e.findings.some((f) => f.rule === 'D4'), 'D4 subsiste — external_consumer n\'est pas un silencieux global');
  // JUMEAU NEGATIF : sans le champ, D1 est emis.
  const [e2] = auditDeclaration(root, AGENT_DECL, listCorpus(root, SCAN));
  assert.ok(e2.findings.some((f) => f.rule === 'D1'));
  assert.equal(e2.external_consumer, null);
});

test('declaration_doc (entrees schemas/* et matrices .md) : lecteur -> zero constat, sans lecteur -> D1, JAMAIS d\'analyse de champ', () => {
  const root = tmpRepo();
  put(root, 'schemas/task_packet.schema.json', '{"type": "object"}');
  put(root, 'schemas/strike_rules.schema.json', '{"type": "object"}');
  // un fichier de DONNEES qui pointe le schema via $schema n'est jamais un lecteur
  put(root, 'lab/agent_policy/strike_rules.json', '{"$schema": "../../schemas/strike_rules.schema.json"}');
  put(root, 'scripts/studioV2/validate.py', 'SCHEMA = Path("schemas/task_packet.schema.json")\n');
  const corpus = listCorpus(root, SCAN);

  const lu = { id: 'schema-task-packet', kind: 'declaration_doc', path: 'schemas/task_packet.schema.json' };
  const [a] = auditDeclaration(root, lu, corpus);
  assert.equal(a.reader_verdict, 'MENTIONNE_PAR_CODE');
  assert.deepEqual(a.readers.map((r) => r.path), ['scripts/studioV2/validate.py']);
  assert.deepEqual(a.findings, []);
  assert.equal(a.field_analysis, 'non_applicable', 'declaration_doc ne fait aucune analyse de champ');

  const mort = { id: 'schema-strike-rules', kind: 'declaration_doc', path: 'schemas/strike_rules.schema.json' };
  const [b] = auditDeclaration(root, mort, corpus);
  assert.equal(b.reader_verdict, 'AUCUN_LECTEUR_CODE');
  assert.deepEqual(b.findings.map((f) => f.rule), ['D1']);
  assert.equal(b.field_analysis, 'non_applicable');
  assert.deepEqual(b.unread_fields, []);
  assert.deepEqual(b.other_mentions.map((m) => m.path), ['lab/agent_policy/strike_rules.json']);
});

test('manifeste REEL : chaque cible EXISTE, kind connu, toute exclusion de lecteur motivee', () => {
  const repoRoot = new URL('../..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
  const wl = loadWatchlist(repoRoot);
  const KINDS = ['agent_md', 'policy_json', 'declaration_doc'];
  assert.ok(wl.declarations.length >= 18, 'la passe d\'extension 2026-07-19 porte le manifeste a 18 entrees');
  for (const d of wl.declarations) {
    assert.ok(KINDS.includes(d.kind), `kind inconnu (retomberait en silence sur « lecteur seul ») : ${d.id}/${d.kind}`);
    assert.ok(existsSync(join(repoRoot, d.path || d.dir)), `cible fantome : ${d.id} -> ${d.path || d.dir}`);
    if (d.kind === 'policy_json') assert.ok(Array.isArray(d.field_scopes), `field_scopes requis : ${d.id}`);
    for (const nr of d.non_reader_mentions || []) {
      assert.ok(nr.path, `exclusion sans chemin : ${d.id}`);
      assert.ok((nr.reason || '').length > 30, `exclusion de lecteur NON motivee : ${d.id} -> ${nr.path}`);
    }
  }
  const ids = wl.declarations.map((d) => d.id);
  for (const id of ['forge-roles', 'forge-oracles', 'claim-matrix', 'authority-matrix', 'escalation-matrix',
    'schema-tool-permission-matrix', 'schema-task-packet']) {
    assert.ok(ids.includes(id), `entree manquante : ${id}`);
  }
});
