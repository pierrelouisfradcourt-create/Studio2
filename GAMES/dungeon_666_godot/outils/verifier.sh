#!/usr/bin/env bash
# Oracle complet de la version Godot : la simulation portée calcule-t-elle EXACTEMENT ce que
# calcule la simulation web (GAMES/dungeon_666, la spécification) ?
#   bash outils/verifier.sh
# 1. la version web exporte données, vecteurs et parties notées ; 2. Godot enregistre ses classes ;
# 3. fonctions pures contre leurs vecteurs ; 4. parties rejouées, comparées au bit près.
# Sortie 0 = tout vert. Une erreur de script Godot (« SCRIPT ERROR ») est un rouge.
set -uo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ICI/../dungeon_666"
GODOT_BIN="${GODOT_BIN:-C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe}"
JOURNAL="$(mktemp)"
rouge=0

echo "[1/4] export depuis la simulation web"
(cd "$WEB" && node tools/export_godot.mjs >/dev/null) || { echo "ÉCHEC : export web"; exit 1; }

echo "[2/4] enregistrement des classes Godot"
"$GODOT_BIN" --headless --path "$ICI" --import >"$JOURNAL" 2>&1 || true
if grep -q "SCRIPT ERROR\|Parse Error" "$JOURNAL"; then
  grep "SCRIPT ERROR\|Parse Error" "$JOURNAL" | head -10
  rouge=1
fi

echo "[3/4] fonctions pures (vecteurs) et données"
"$GODOT_BIN" --headless --path "$ICI" --script res://tests/run_tests.gd >"$JOURNAL" 2>&1 || rouge=1
grep -E "ROUGE|vérifications|RESULT|SCRIPT ERROR" "$JOURNAL" | head -30
grep -q "SCRIPT ERROR" "$JOURNAL" && rouge=1
grep -q "RESULT: PASS" "$JOURNAL" || rouge=1

echo "[4/4] parties rejouées (parité exacte)"
"$GODOT_BIN" --headless --path "$ICI" --script res://parite/rejouer.gd >"$JOURNAL" 2>&1 || rouge=1
grep -E "ROUGE|rejouées|PARITE|SCRIPT ERROR" "$JOURNAL" | head -30
grep -q "SCRIPT ERROR" "$JOURNAL" && rouge=1
grep -q "PARITE: PASS" "$JOURNAL" || rouge=1

rm -f "$JOURNAL"
if [ "$rouge" -eq 0 ]; then echo "VERDICT : VERT"; else echo "VERDICT : ROUGE"; fi
exit "$rouge"
