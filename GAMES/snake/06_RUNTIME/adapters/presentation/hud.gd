# hud.gd — ligne render.hud_numbers. Texte du bandeau d'information : score courant et
# meilleur score. Le texte lu a l'ecran et la valeur de l'etat expose sont STRICTEMENT
# EGAUX (le nombre affiche se re-parse en la valeur exacte). Formatage PUR et testable en
# headless ; le pilote de scene pose le Label. RefCounted.
extends RefCounted

const PREFIXE_SCORE := "Score: "
const PREFIXE_MEILLEUR := "Record: "

static func texte_score(score: int) -> String:
	return PREFIXE_SCORE + str(score)

static func texte_meilleur(meilleur: int) -> String:
	return PREFIXE_MEILLEUR + str(meilleur)

# Re-lecture STRICTE : extrait la valeur numerique d'un texte de score produit ci-dessus.
# Sert l'egalite stricte texte<->etat de l'oracle (jamais un simple "contient le chiffre").
static func valeur_score_depuis_texte(texte: String) -> int:
	return int(texte.substr(PREFIXE_SCORE.length()))

static func valeur_meilleur_depuis_texte(texte: String) -> int:
	return int(texte.substr(PREFIXE_MEILLEUR.length()))
