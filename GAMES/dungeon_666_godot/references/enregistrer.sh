#!/usr/bin/env bash
# Réenregistre les parties de référence sur plusieurs processus Godot (un par cœur).
#   bash references/enregistrer.sh [nom …]
# À lancer seulement quand une règle ou un nombre a changé EXPRÈS : consigne en tête de
# references/enregistrer.gd. Sortie 0 = tout écrit.
set -uo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe}"
PROCESSUS="${PROCESSUS:-$(nproc 2>/dev/null || echo 4)}"
JOURNAUX="$(mktemp -d)"
ENFANTS=()
rouge=0

nettoyer() {
  # N'arrête que les processus lancés ICI (d'autres Godot tournent sur la machine).
  for pid in "${ENFANTS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
  rm -rf "$JOURNAUX"
}
trap nettoyer EXIT
trap 'exit 130' INT TERM

for ((i = 0; i < PROCESSUS; i++)); do
  "$GODOT_BIN" --headless --path "$ICI" --script res://references/enregistrer.gd -- "$@" --tranche "$i/$PROCESSUS" >"$JOURNAUX/$i.log" 2>&1 &
  ENFANTS+=("$!")
done
for pid in "${ENFANTS[@]}"; do wait "$pid" || rouge=1; done
ENFANTS=()
grep -h "ROUGE\|retiré\|SCRIPT ERROR\|Parse Error\|inconnue" "$JOURNAUX"/*.log
grep -q "SCRIPT ERROR\|Parse Error" "$JOURNAUX"/*.log && rouge=1
ecrites=$(cat "$JOURNAUX"/*.log | grep -c "écrit —")
octets=$(cat "$ICI"/references/parties/*.ref 2>/dev/null | wc -c)
echo "$ecrites parties écrites ; references/parties : $octets octets ; ${SECONDS} s ($PROCESSUS processus)"
if [ "$rouge" -eq 0 ]; then echo "ENREGISTREMENT : VERT"; else echo "ENREGISTREMENT : ROUGE"; fi
exit "$rouge"
