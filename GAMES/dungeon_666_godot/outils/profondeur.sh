#!/usr/bin/env bash
# Mesure EN PROFONDEUR du combat V3 (outils/profondeur.gd) sur plusieurs processus Godot : chaque
# classe, sections 1, 7 et 19 (étages 1, 109, 325), arbre vide contre arbre plein, avec et sans
# déplacement de classe. Écrit _dev/rapports/profondeur_mesures.md.
#   bash outils/profondeur.sh [graines=12]
#   PROCESSUS=4 bash outils/profondeur.sh 6
# Coût : 27 cases × graines parties d'une section (une partie : 10 à 40 s de calcul selon la
# profondeur). Ce n'est pas un oracle : aucune sortie rouge sur un nombre, seulement sur une erreur de script.
# Un essai ne touche jamais le profil du joueur : la mesure ne lit ni n'écrit de sauvegarde.
set -uo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe}"
GRAINES="${1:-12}"
PROCESSUS="${PROCESSUS:-$(nproc 2>/dev/null || echo 4)}"
PARTIELS="$ICI/_dev/rapports/profondeur_partiels_$$"
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
  "$GODOT_BIN" --headless --path "$ICI" --script res://outils/profondeur.gd -- "$GRAINES" \
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
"$GODOT_BIN" --headless --path "$ICI" --script res://outils/profondeur.gd -- "$GRAINES" --agreger "$PARTIELS" 2>&1 | grep -v "^Godot Engine\|^$" || echec=1
echo "durée : ${SECONDS} s ($PROCESSUS processus)"
exit "$echec"
