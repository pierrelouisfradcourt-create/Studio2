#!/usr/bin/env bash
# L'ORACLE de Dungeon 666 (version Godot) : un seul, sans Node. Godot est seul maître de ses
# règles et de ses données ; ceci dit si elles tiennent encore.
#   bash outils/verifier.sh                     tout (environ 2 minutes sur 8 cœurs)
#   bash outils/verifier.sh --jouabilite        … puis les oracles de jouabilité (20 et 20 graines, ~5 min)
#   bash outils/verifier.sh --jouabilite 6 3    … avec ces nombres de graines (solvabilité, classes)
#   PROCESSUS=4 bash outils/verifier.sh         nombre de processus Godot en parallèle (défaut : un par cœur)
#
# 1. import          Godot enregistre ses classes (seul endroit où `--import` est lancé) ;
# 2. données         data/*.json contre leurs schémas (validateur du kit) ; écriture sans perte ;
# 3. règles          tests/regles/*.gd, un processus par fichier ;
# 4. références      les parties enregistrées par Godot sont rejouées : la simulation n'a pas
#                    changé sans qu'on le veuille (consigne : references/verifier.gd) ;
# 5. vues            les tests headless de jeu/ (jeu/*/test_*.gd, jeu/*/verifier.gd) ;
# 6. jouabilité      sur demande : outils/jouabilite.sh (un bot bat la section 1, le dash compte, les classes).
#
# Les étapes 2 à 5 tournent en parallèle, chacune dans ses propres processus Godot. ROUGE si une
# commande sort en erreur, si son verdict manque, ou si une « SCRIPT ERROR » apparaît dans sa sortie.
# Ce que l'oracle ne prouve pas : le rendu, les commandes en main, le son, le plaisir de jeu.
# Sortie 0 = VERT, 1 = ROUGE.
set -uo pipefail

ICI="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe}"
PROCESSUS="${PROCESSUS:-$(nproc 2>/dev/null || echo 4)}"
ERREUR_SCRIPT="SCRIPT ERROR\|Parse Error"
# Gardes anti-faux-vert : en dessous, un fichier de tests ou des parties ont disparu.
MIN_TESTS_REGLES=359
MIN_PARTIES=70
LIGNES_PAR_ROUGE=6 # lignes montrées par processus rouge (la suite : relancer l'étape seule, voir README.md)
VUES_ATTENDUES="jeu/entrees/test_entrees.gd jeu/ecrans/test_ecrans.gd jeu/ville/test_ville.gd jeu/son/test_son.gd jeu/effets/verifier.gd jeu/theme/verifier.gd jeu/monde/test_profondeur.gd jeu/monde/test_finitions.gd"

JOUABILITE=0
GRAINES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jouabilite) JOUABILITE=1 ;;
    [0-9]*) GRAINES+=("$1") ;;
    *) echo "argument inconnu : $1 (voir l'en-tête de outils/verifier.sh)"; exit 1 ;;
  esac
  shift
done

J="$(mktemp -d)"
rouge=0
RESUME=()

nettoyer() {
  # N'arrête que les processus Godot lancés ICI (d'autres tournent sur la machine).
  for f in "$J"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
  rm -rf "$J"
}
trap nettoyer EXIT
trap 'exit 130' INT TERM

ms() { echo $(($(date +%s%N) / 1000000)); }
duree() { printf '%d,%d s' $(($1 / 1000)) $((($1 % 1000) / 100)); }

# tache <étape> <nom> <verdict attendu dans la sortie, ou -> <arguments de Godot…>
# Lance la commande en arrière-plan, au plus $PROCESSUS à la fois. Écrit <étape>.<nom>.log et .res
# (« vert|rouge durée_ms »).
tache() {
  local etape="$1" nom="$2" attendu="$3"
  shift 3
  while [ "$(jobs -rp | wc -l)" -ge "$PROCESSUS" ]; do wait -n; done
  (
    debut=$(ms)
    journal="$J/$etape.$nom.log"
    "$GODOT_BIN" --headless --path "$ICI" "$@" >"$journal" 2>&1 &
    echo $! >"$J/$etape.$nom.pid"
    wait $!
    code=$?
    rm -f "$J/$etape.$nom.pid"
    verdict=vert
    [ "$code" -ne 0 ] && verdict=rouge
    grep -q "$ERREUR_SCRIPT" "$journal" && verdict=rouge
    [ "$attendu" != "-" ] && ! grep -q "$attendu" "$journal" && verdict=rouge
    echo "$verdict $(($(ms) - debut))" >"$J/$etape.$nom.res"
  ) &
}

# bilan <étape> <titre> : affiche le verdict de l'étape, la plus longue de ses tâches et, pour
# chaque tâche rouge, les lignes qui disent pourquoi. Rend 1 si l'étape est rouge.
bilan() {
  local etape="$1" titre="$2" rouges=0 taches=0 max=0 f verdict t nom
  for f in "$J/$etape".*.res; do
    [ -f "$f" ] || continue
    read -r verdict t <"$f"
    taches=$((taches + 1))
    [ "$t" -gt "$max" ] && max=$t
    if [ "$verdict" != "vert" ]; then
      rouges=$((rouges + 1))
      nom="$(basename "$f" .res)"
      echo "  ROUGE — ${nom#"$etape".}"
      grep -a "ROUGE\|FAUX\|^ *- \|$ERREUR_SCRIPT\|ECHEC\|échec\|FAIL" "${f%.res}.log" | head -"$LIGNES_PAR_ROUGE" | sed 's/^/      /'
    fi
  done
  [ "$taches" -eq 0 ] && rouges=1
  local detail="${3:-}"
  if [ "$rouges" -eq 0 ]; then
    RESUME+=("  VERT   $titre — $detail$taches processus, le plus long $(duree "$max")")
    return 0
  fi
  RESUME+=("  ROUGE  $titre — $detail$rouges processus rouge(s) sur $taches")
  return 1
}

# somme <étape> <expression sed qui extrait un nombre> : additionne ce nombre sur les sorties de l'étape.
somme() {
  cat "$J/$1".*.log 2>/dev/null | sed -n "$2" | awk '{ s += $1 } END { print s + 0 }'
}

DEBUT=$(ms)

echo "[1/5] import : Godot enregistre ses classes"
"$GODOT_BIN" --headless --path "$ICI" --import >"$J/import.log" 2>&1 || true
if grep -q "$ERREUR_SCRIPT" "$J/import.log"; then
  grep "$ERREUR_SCRIPT" -A2 "$J/import.log" | head -12
  RESUME+=("  ROUGE  1. import — erreur de script")
  rouge=1
else
  RESUME+=("  VERT   1. import — $(duree $(($(ms) - DEBUT)))")
fi

echo "[2-5] données, règles, références, vues : en parallèle ($PROCESSUS processus au plus)"
# Les plus longues d'abord : les sections entières des références, puis les règles.
for ((i = 0; i < PROCESSUS; i++)); do
  tache references "tranche_$i" "REFERENCES: PASS" --script res://references/verifier.gd -- --tranche "$i/$PROCESSUS"
done
for f in "$ICI"/tests/regles/*.gd; do
  nom="$(basename "$f" .gd)"
  tache regles "$nom" "REGLES: PASS" --script res://tests/regles.gd -- "$nom"
done
tache donnees schemas "0 faute(s)" --script res://addons/studio_kit/outils/valider.gd
tache donnees ecriture "DONNEES_ECRITURE: PASS" --script res://outils/donnees.gd
VUES=()
for f in "$ICI"/jeu/*/test_*.gd "$ICI"/jeu/*/verifier.gd; do
  [ -f "$f" ] && VUES+=("${f#"$ICI"/}")
done
for v in "${VUES[@]}"; do
  tache vues "$(echo "${v%.gd}" | tr '/' '_')" - --script "res://$v"
done
wait

echo "[2/5] données"
FAUTES=$(somme donnees 's/^=== DONNÉES : .* \([0-9]*\) faute.*/\1/p')
ECRITURE=$(grep -q "DONNEES_ECRITURE: PASS" "$J/donnees.ecriture.log" 2>/dev/null && echo "sans perte" || echo "EN DÉFAUT")
bilan donnees "2. données" "$(somme donnees 's/^=== DONNÉES : \([0-9]*\) fichier.*/\1/p') fichiers, $FAUTES faute(s) de schéma, écriture $ECRITURE ; " || rouge=1

echo "[3/5] règles"
TESTS=$(somme regles 's/^[0-9]* fichiers, \([0-9]*\) tests.*/\1/p')
bilan regles "3. règles" "$TESTS tests, $(somme regles 's/^[0-9]* fichiers, .* \([0-9]*\) rouges$/\1/p') rouge(s) ; " || rouge=1
if [ "$TESTS" -lt "$MIN_TESTS_REGLES" ]; then
  RESUME+=("  ROUGE  3. règles — $TESTS tests joués, $MIN_TESTS_REGLES attendus au moins : un fichier de tests a disparu ?")
  rouge=1
fi

echo "[4/5] références"
PARTIES=$(somme references 's/^\([0-9]*\) parties rejouées.*/\1/p')
POINTS=$(somme references 's/^[0-9]* parties rejouées, \([0-9]*\) points.*/\1/p')
ECARTS=$(somme references 's/^[0-9]* parties rejouées, .* \([0-9]*\) en écart.*/\1/p')
bilan references "4. références" "$PARTIES parties rejouées, $ECARTS en écart, $POINTS points de contrôle identiques ; " || rouge=1
if [ "$PARTIES" -lt "$MIN_PARTIES" ]; then
  RESUME+=("  ROUGE  4. références — $PARTIES parties rejouées, $MIN_PARTIES attendues au moins")
  rouge=1
fi

echo "[5/5] vues"
bilan vues "5. vues" "${#VUES[@]} tests ; " || rouge=1
for v in $VUES_ATTENDUES; do
  if [ ! -f "$ICI/$v" ]; then
    RESUME+=("  ROUGE  5. vues — $v a disparu")
    rouge=1
  fi
done

if [ "$JOUABILITE" -eq 1 ]; then
  echo "[6] jouabilité"
  debut=$(ms)
  if bash "$ICI/outils/jouabilite.sh" "${GRAINES[@]}" >"$J/jouabilite.log" 2>&1; then
    RESUME+=("  VERT   6. jouabilité — $(grep -c "PASS" "$J/jouabilite.log") volets PASS, $(duree $(($(ms) - debut)))")
  else
    grep "ROUGE\|FAIL\|incomplète\|$ERREUR_SCRIPT" "$J/jouabilite.log" | head -12 | sed 's/^/      /'
    RESUME+=("  ROUGE  6. jouabilité — $(duree $(($(ms) - debut))) (détail : bash outils/jouabilite.sh ${GRAINES[*]})")
    rouge=1
  fi
fi

echo
echo "RÉSUMÉ"
printf '%s\n' "${RESUME[@]}"
echo "  durée totale : $(duree $(($(ms) - DEBUT)))"
if [ "$rouge" -eq 0 ]; then echo "VERDICT : VERT"; else echo "VERDICT : ROUGE"; fi
exit "$rouge"
