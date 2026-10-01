extends RefCounted
## Palette par RÔLE — générée depuis GAMES/dungeon_666/src/render/palette.mjs (ne pas éditer à la
## main : relancer la génération). Le héros est froid (cyan, blanc), tout ce qui fait mal est
## chaud (rouge, orange, magenta) et cerné de sombre, le butin parle la langue de Diablo.
##   const Couleurs = preload("res://jeu/theme/couleurs.gd")   puis   Couleurs.PAL.hero

const PAL := {
	"void": Color("#07040a"),
	"floorA": Color("#1b1116"),
	"floorB": Color("#22151b"),
	"floorLine": Color("#2e1d24"),
	"crack": Color("#120a0e"),
	"lava": Color("#ff5a1f"),
	"lavaDim": Color("#7a1f0a"),
	"wall": Color("#2a1a20"),
	"wallTop": Color("#3b252d"),
	"wallEdge": Color("#5a3a44"),
	"pillarTop": Color("#47303a"),
	"pillarSide": Color("#24161c"),
	"shadow": Color(0, 0, 0, 0.45),
	"hero": Color("#eaf7ff"),
	"heroCape": Color("#2fc7ff"),
	"heroGlow": Color(0.3137, 0.8235, 1, 0.35),
	"heroHurt": Color("#ff4a4a"),
	"slash": Color("#dff8ff"),
	"slashStrike": Color("#7fe8ff"),
	"lance": Color("#9ff4ff"),
	"danger": Color("#ff3b3b"),
	"dangerFill": Color(1, 0.1765, 0.1765, 0.16),
	"dangerFillHot": Color(1, 0.2353, 0.1569, 0.42),
	"enemyOutline": Color("#140507"),
	"enemyFlash": Color("#ffc9b0"),
	"impactRing": Color("#ffd2a8"),
	"summon": Color("#b48cff"),
	"arrow": Color("#ff8a2a"),
	"bossOrb": Color("#ff3cbe"),
	"imp": Color("#e2483b"),
	"archer": Color("#d9cdb8"),
	"brute": Color("#9a3030"),
	"charger": Color("#c8732e"),
	"exploder": Color("#ff9c2a"),
	"boss": Color("#6a1428"),
	"bossTrim": Color("#ffcf5a"),
	"eliteRapide": Color("#4fd1ff"),
	"eliteBlinde": Color("#c9c9d6"),
	"eliteArdent": Color("#ff6a1a"),
	"eliteVampirique": Color("#ff3d7f"),
	"eliteBouclier": Color("#ffe9a8"),
	"eliteInvocateur": Color("#b48cff"),
	"gold": Color("#ffd23c"),
	"heal": Color("#6dff8a"),
	"text": Color("#f3e9e4"),
	"textDim": Color("#a8949a"),
	"crit": Color("#ffe14a"),
	"hpBar": Color("#e23a3a"),
	"hpBack": Color("#2a1216"),
	"superBar": Color("#ffb02e"),
	"dashPip": Color("#7fe8ff"),
}

const ELITE_COLORS := {
	"rapide": Color("#4fd1ff"),
	"blinde": Color("#c9c9d6"),
	"ardent": Color("#ff6a1a"),
	"vampirique": Color("#ff3d7f"),
	"bouclier": Color("#ffe9a8"),
	"invocateur": Color("#b48cff"),
}

const ELITE_NAMES := {
	"rapide": "Rapide",
	"blinde": "Blindé",
	"ardent": "Ardent",
	"vampirique": "Vampirique",
	"bouclier": "Bouclier",
	"invocateur": "Invocateur",
}

## Teinte de chaque Cercle (sols, lueurs), index = Cercle − 1 ; le 10e = finale.
const CIRCLE_TINTS: Array[Color] = [Color("#ff5a1f"), Color("#ff3c8c"), Color("#9be03c"), Color("#ffc83c"), Color("#ff2a2a"), Color("#b98cff"), Color("#ff7a3c"), Color("#3ce0b4"), Color("#7ab8ff"), Color("#ffffff")]

const REWARD_COLORS := {
	"boon": Color("#ff8ae0"),
	"loot": Color("#ffd23c"),
	"gold": Color("#ffd23c"),
	"elite": Color("#ff6a1a"),
	"heal": Color("#6dff8a"),
	"shop": Color("#7fe8ff"),
	"event": Color("#b98cff"),
	"boss": Color("#ff3b3b"),
	"town": Color("#9ff4ff"),
}

## Interface (variables CSS de index.html).
const UI := {
	"void": Color("#07040a"),
	"ink": Color("#f3e9e4"),
	"ink_dim": Color("#a8949a"),
	"ember": Color("#ff5a1f"),
	"gold": Color("#ffd23c"),
	"cyan": Color("#2fc7ff"),
	"blood": Color("#c0304a"),
	"panel": Color(0.0706, 0.0353, 0.0549, 0.94),
	"line": Color(1.0, 0.8235, 0.7059, 0.16),
}
