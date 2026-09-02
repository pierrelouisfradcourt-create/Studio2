# hud.gd — ligne render.hud_lives_score (volet texte). Le texte lu a l'ecran et la valeur de
# l'etat expose sont STRICTEMENT egaux (le nombre affiche se re-parse en la valeur exacte).
# Formatage PUR, testable en headless ; le pilote de scene pose les Labels. RefCounted.
extends RefCounted

const PREFIXE_VIES := "Vies: "
const PREFIXE_SCORE := "Score: "

static func texte_vies(vies: int) -> String:
	return PREFIXE_VIES + str(vies)

static func texte_score(score: int) -> String:
	return PREFIXE_SCORE + str(score)

# Re-lecture STRICTE : extrait la valeur numerique du texte produit ci-dessus.
static func valeur_vies_depuis_texte(texte: String) -> int:
	return int(texte.substr(PREFIXE_VIES.length()))

static func valeur_score_depuis_texte(texte: String) -> int:
	return int(texte.substr(PREFIXE_SCORE.length()))
