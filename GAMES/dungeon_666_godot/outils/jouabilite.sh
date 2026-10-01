#!/usr/bin/env bash
# Oracles de JOUABILITÉ de la version Godot : le jeu se juge-t-il encore tout seul ?
#   bash outils/jouabilite.sh [graines_solvabilite=20] [graines_classes=20]
#   PROCESSUS=4 bash outils/jouabilite.sh 6 3        (défaut : un processus par cœur)
#   bash outils/jouabilite.sh 20 0                   (0 = volet sauté)
# 1. solvabilité (outils/solvabilite.gd) : un bot bat la section 1, et le dash compte ;
# 2. classes (outils/classes.gd) : les 6 kits joués par 3 bots, et l'attaque maintenue sur place.
# Sortie 0 = les deux volets PASS, 1 = au moins un FAIL, une mesure incomplète ou une erreur de script.
#
# Le GDScript joue ~3 000 pas de simulation par seconde et par processus (V8 : ~100 000). Les
# parties sont donc réparties sur plusieurs PROCESSUS Godot lancés en parallèle (jamais des fils :
# la simulation a des variables statiques partagées) ; chacun écrit un résultat partiel en JSON
# (nombres exacts), puis un dernier processus agrège et rend le verdict. Ces oracles sont portés de
# la version web (solvability.mjs, tools/classes.mjs), figée le 2026-10-01 : ils rendaient alors
# les mêmes nombres qu'elle sur les mêmes graines ; depuis, ils ne se mesurent qu'à eux-mêmes.
# Coût mesuré le 2026-10-01 (8 processus, machine partagée avec d'autres travaux) : 274 s avec les
# valeurs par défaut — solvabilité 20 graines 44 s (60 parties), classes 20 graines 230 s (360 parties
# et 180 essais sur place). Dans un seul processus : ~5 min et ~30 min. Avec 6 et 3 graines : 18 s + 50 s.
set -uo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe}"
GRAINES_SOLVABILITE="${1:-20}"
GRAINES_CLASSES="${2:-20}"
PROCESSUS="${PROCESSUS:-$(nproc 2>/dev/null || echo 4)}"
PARTIELS="$ICI/_dev/rapports/partiels_$$"
ENFANTS=()
rouge=0

nettoyer() {
  # N'arrête que les processus lancés ICI (d'autres Godot tournent sur la machine).
  for pid in "${ENFANTS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
  rm -rf "$PARTIELS"
}
trap nettoyer EXIT
trap 'exit 130' INT TERM

# volet <script.gd> <préfixe des partiels> <graines> : répartit, attend, agrège. Rend le code du verdict.
volet() {
  local script="$1" prefixe="$2" graines="$3" dossier="$PARTIELS/$2" debut=$SECONDS i echec=0
  mkdir -p "$dossier"
  ENFANTS=()
  for ((i = 0; i < PROCESSUS; i++)); do
    "$GODOT_BIN" --headless --path "$ICI" --script "res://outils/$script" -- "$graines" \
      --tranche "$i/$PROCESSUS" --sortie "$dossier/${prefixe}_$i.json" >"$dossier/$i.log" 2>&1 &
    ENFANTS+=("$!")
  done
  for pid in "${ENFANTS[@]}"; do wait "$pid" || echec=1; done
  ENFANTS=()
  if grep -l "SCRIPT ERROR\|Parse Error" "$dossier"/*.log >/dev/null 2>&1; then
    grep -h "SCRIPT ERROR\|Parse Error" -A2 "$dossier"/*.log | head -12
    echec=1
  fi
  "$GODOT_BIN" --headless --path "$ICI" --script "res://outils/$script" -- "$graines" --agreger "$dossier" 2>&1 \
    | grep -v "^Godot Engine\|^$" | tee "$dossier/verdict.log"
  local code=${PIPESTATUS[0]}
  grep -q "SCRIPT ERROR" "$dossier/verdict.log" && echec=1
  echo "  durée : $((SECONDS - debut)) s ($PROCESSUS processus)"
  [ "$echec" -ne 0 ] && return 1
  return "$code"
}

echo "[1/2] solvabilité — $GRAINES_SOLVABILITE graines × 3 bots"
if [ "$GRAINES_SOLVABILITE" -gt 0 ]; then volet solvabilite.gd solvabilite "$GRAINES_SOLVABILITE" || rouge=1; else echo "  sauté"; fi

echo "[2/2] classes — $GRAINES_CLASSES graines × 6 kits × 3 bots, et l'attaque maintenue sur place"
if [ "$GRAINES_CLASSES" -gt 0 ]; then volet classes.gd classes "$GRAINES_CLASSES" || rouge=1; else echo "  sauté"; fi

if [ "$rouge" -eq 0 ]; then echo "JOUABILITE : VERT (${SECONDS} s)"; else echo "JOUABILITE : ROUGE (${SECONDS} s)"; fi
exit "$rouge"
