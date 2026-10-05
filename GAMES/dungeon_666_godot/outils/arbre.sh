#!/usr/bin/env bash
# Mesures de l'arbre de compétences (outils/arbre.gd) sur plusieurs processus Godot : puissance de
# l'arbre plein, et valeur de chaque compétence neuve. Écrit _dev/rapports/arbre.md.
#   bash outils/arbre.sh [graines=10]
#   PROCESSUS=4 bash outils/arbre.sh 6
# Ce n'est pas un oracle : aucune sortie rouge sur un nombre, seulement sur une erreur de script.
# Un essai ne touche jamais le profil du joueur : la mesure ne lit ni n'écrit de sauvegarde.
set -uo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe}"
GRAINES="${1:-10}"
PROCESSUS="${PROCESSUS:-$(nproc 2>/dev/null || echo 4)}"
PARTIELS="$ICI/_dev/rapports/arbre_partiels_$$"
export D666_DONNEES="${D666_DONNEES:-user://essais}"
ENFANTS=()

nettoyer() {
  for pid in "${ENFANTS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
  rm -rf "$PARTIELS"
}
trap nettoyer EXIT
trap 'exit 130' INT TERM

mkdir -p "$PARTIELS"
for ((i = 0; i < PROCESSUS; i++)); do
  "$GODOT_BIN" --headless --path "$ICI" --script res://outils/arbre.gd -- "$GRAINES" \
    --tranche "$i/$PROCESSUS" --sortie "$PARTIELS/part_$i.json" >"$PARTIELS/$i.log" 2>&1 &
  ENFANTS+=("$!")
done
echec=0
for pid in "${ENFANTS[@]}"; do wait "$pid" || echec=1; done
ENFANTS=()
if grep -l "SCRIPT ERROR\|Parse Error" "$PARTIELS"/*.log >/dev/null 2>&1; then
  grep -h "SCRIPT ERROR\|Parse Error" -A2 "$PARTIELS"/*.log | head -12
  echec=1
fi
"$GODOT_BIN" --headless --path "$ICI" --script res://outils/arbre.gd -- "$GRAINES" --agreger "$PARTIELS" 2>&1 | grep -v "^Godot Engine\|^$" || echec=1
exit "$echec"
