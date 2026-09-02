"""build_asset.py — PRODUCTEUR d'assets Blender, pilote par une spec JSON.

COUCHE PRODUCTEUR (cf. docs/forge/ASSET_GEOMETRY_PIPELINE_BOUNDARY_V1.md).
Ce script CREE. Il ne juge jamais, et il n'ecrit JAMAIS le manifeste de recensement
(`<asset>.glb.geometry.json`) : celui-ci est la parole du HumanGate, pas du producteur.
S'il l'ecrivait, le producteur declarerait sa propre geometrie legitime et court-circuiterait
l'oracle -- exactement ce que l'architecture interdit.

Il ecrit :
  <asset>.glb                  la geometrie
  <asset>.glb.metadata.json    sa DECLARATION (confrontee ensuite a la mesure independante)
  <asset>.generation_report.json  ce qu'il a fait, et avec quels parametres

Invariants imposes A LA CONSTRUCTION (pas verifies ici -- c'est le role de l'oracle) :
  - origine au pied  : la geometrie est batie en Z>=0 dans Blender (=> Y>=0 en glTF)
  - materiau present : chaque objet en recoit un
  - pas de parasite  : scene videe avant construction, un seul objet racine par piece
  - echelle en metres

Usage (depuis WSL) :
  <blender> -b --python forge/asset_producer/build_asset.py -- <spec.json> <dest_dir>
"""
# RATIFICATION EXPLICITE DE PIERRE, 2026-08-12 — P9 etape 2.
#
# `forge/**` est une zone protegee (reference_protected.yaml). L'ecriture ci-dessous a
# ete faite AVANT ratification, signalee comme telle, puis CONSERVEE en l'etat pour que la
# decision porte sur un perimetre identifiable plutot que sur un souvenir.
#
# PERIMETRE RATIFIE, mesure et non estime :
#   366 insertions, 1 suppression ; UNE SEULE ligne existante modifiee — l'enumeration FERMEE
#   `ARCHETYPES`, etendue de 8 a 11 : `military_crate`, `sandbag`, `fuel_drum`, avec leurs
#   generateurs. Tout le reste est de l'ajout pur.
#
# CE QUE CETTE RATIFICATION NE COUVRE PAS :
#   - aucune autorisation generale de modifier `forge/**` ;
#   - aucune refonte du producteur.
#
# LIMITE ARCHITECTURALE MESUREE, DECISION DIFFEREE : ce fichier cumule quatre roles — registre
# des archetypes, dispatcher, point d'extension, producteur. Toute famille d'asset inedite doit
# donc franchir une frontiere protegee. Constate une fois, PAS refactore : un second kit sert
# de capteur. Si la meme frontiere est rencontree ET que les regles R1/R2 se generalisent a des
# pieces qu'elles n'ont pas servi a produire, la limite est confirmee. Sinon elle etait
# circonstancielle. Detail : knowledge_base/proposals/forge.consumer_is_not_found_by_shape.yaml

import json
import os
import sys

import bpy

SCHEMA_VERSION = "1.0"

# Doit correspondre EXACTEMENT au prefixe attendu par knowledge_base/kb-validate.mjs
# (ORIGINAL_MARKER) : R3 accepte `provenance_url: null` seulement si `source` commence
# par cette chaine. Une paraphrase (« ORIGINAL — genere par ... ») fait echouer
# l'ingestion beaucoup plus tard, au moment de la ratification -- constate le 2026-08-06.
ORIGINAL_MARKER = "ORIGINAL — aucune inspiration externe citee"

# Archetypes disponibles. Enumeration FERMEE : un archetype inconnu est une erreur
# explicite, jamais un cube par defaut silencieux.
ARCHETYPES = ["crate", "door", "platform", "barrel", "pillar", "button", "chest", "soldier",
              "military_crate", "sandbag", "fuel_drum"]

# Roles de l'archetype `soldier`. Enumeration FERMEE, meme discipline que ARCHETYPES : un
# role inconnu est une erreur explicite, jamais une figurine par defaut.
#
# POURQUOI UN SEUL ARCHETYPE POUR QUATRE PERSONNAGES, et pas quatre archetypes : c'est CE
# CHOIX qui fait d'eux un SET et non quatre figurines choisies separement. Le corps, les
# proportions, l'echelle, le pivot et le langage de formes sont ecrits UNE fois dans
# `_soldier_body()` ; le role ne pilote que le casque et un accessoire. Deux fonctions
# separees auraient diverge des la premiere retouche.
SOLDIER_ROLES = ["scout", "assault", "tech", "demo"]


def _reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _mat(name, rgba):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = False
    m.diffuse_color = rgba
    return m


def _box(name, sx, sy, sz, cx=0.0, cy=0.0, base_z=0.0, mat=None):
    """Boite dont la BASE est a base_z (jamais centree sur l'origine)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    for v in ob.data.vertices:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z = (v.co.z + 0.5) * sz          # bas du cube ramene a z=0
    ob.location = (cx, cy, base_z)
    ob.data.materials.append(mat or _mat(f"{name}_mat", (0.6, 0.6, 0.6, 1.0)))
    return ob


def _cyl(name, radius, height, cx=0.0, cy=0.0, base_z=0.0, mat=None, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=height, vertices=verts,
                                        location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    for v in ob.data.vertices:
        v.co.z += height / 2.0                # base ramenee a z=0
    ob.location = (cx, cy, base_z)
    ob.data.materials.append(mat or _mat(f"{name}_mat", (0.6, 0.6, 0.6, 1.0)))
    return ob


def _sphere(name, rx, ry, rz, cx=0.0, cy=0.0, center_z=0.0, mat=None, seg=10, rings=6):
    """Sphere ecrasee, positionnee par son CENTRE (et non par sa base).

    Le centre plutot que la base parce qu'un dome de casque s'enfonce a dessein dans la
    tete : la moitie basse est INTERIEURE. Vouloir la poser sur une base obligerait a
    decouper la sphere -- de la geometrie et des sommets pour rien, dans un asset qui doit
    rester low-poly.
    """
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1.0,
                                         location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name
    for v in ob.data.vertices:
        v.co.x *= rx
        v.co.y *= ry
        v.co.z *= rz
    ob.location = (cx, cy, center_z)
    ob.data.materials.append(mat or _mat(f"{name}_mat", (0.6, 0.6, 0.6, 1.0)))
    return ob


def _join(nom_final, cible):
    """Fusionne TOUS les meshes en un seul objet. Les materiaux deviennent des slots.

    POURQUOI CETTE FUSION EST STRUCTURANTE, et pas une commodite : l'oracle de geometrie
    classe UNKNOWN tout noeud portant moins de `main_share_threshold` (0,10) des sommets, et
    `secondary_mesh_policy: declaration_required` fait alors BLOCKED. Une figurine livree en
    douze pieces aurait donc exige un manifeste de recensement ecrit a la main -- or le
    producteur n'a PAS le droit d'ecrire ce manifeste (c'est la parole du HumanGate).
    Une antenne n'est pas une variante exclusive : c'est une partie du personnage. La fusion
    dit cela mecaniquement, au lieu de demander a un humain de le declarer piece par piece.
    """
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    # CIBLE EXPLICITE, jamais `meshes[0]`. `bpy.data.objects` est trie PAR NOM : prendre le
    # premier faisait dependre l'ORIGINE et l'ORDRE DES SLOTS de l'alphabet. Mesure du
    # 2026-08-12 : l'oracle a rendu FAIL PIVOT_AT_BASE sur 3 des 4 figurines, l'origine
    # atterrissant sur `antenne` (-0,4592), `barre_visee` (-0,6560), `bord` (-0,6806) --
    # exactement les pieces alphabetiquement premieres. La cible fixe les deux d'un coup :
    # elle porte le materiau PRINCIPAL, donc slot 0 = principal, slot 1 = accent.
    bpy.context.view_layer.objects.active = cible
    if len(meshes) > 1:
        bpy.ops.object.join()
    final = bpy.context.view_layer.objects.active

    # ORIGINE RAMENEE A (0,0,0) = `base_center`, la convention declaree dans le metadata.
    # La geometrie est batie base a z=0 et centree en x/y : reporter la translation de
    # l'objet dans ses sommets suffit, aucune rotation ni echelle n'est en jeu.
    loc = final.location.copy()
    for v in final.data.vertices:
        v.co.x += loc.x
        v.co.y += loc.y
        v.co.z += loc.z
    final.location = (0.0, 0.0, 0.0)

    final.name = nom_final
    final.data.name = nom_final
    return final


# ---------------------------------------------------------------------------------------
# ARCHETYPE `soldier` — LE SET. Proportions partagees, exprimees en FRACTIONS de la hauteur
# totale : changer `size.h` deplace les quatre personnages ensemble, jamais un seul.
#
# Silhouette de figurine, pas d'humain realiste : tete volumineuse (0,20 h) + casque
# (0,17 h), jambes et bras courts, mains et pieds exageres, posture stable. Lu depuis la
# camera de jeu (vue haute inclinee), ce sont le CASQUE et l'ACCESSOIRE DORSAL qui portent
# la reconnaissance -- c'est donc la que le role varie, et nulle part ailleurs.
# ---------------------------------------------------------------------------------------
F_BOTTE_H = 0.095
F_JAMBE_BAS, F_JAMBE_HAUT = 0.070, 0.360
F_TORSE_BAS, F_TORSE_HAUT = 0.340, 0.660
F_BRAS_BAS, F_BRAS_HAUT = 0.380, 0.630
F_MAIN_BAS, F_MAIN_HAUT = 0.330, 0.420
F_TETE_BAS, F_TETE_HAUT = 0.660, 0.860
F_CASQUE_BAS = 0.830


def _soldier_body(name, w, d, h, principal, accent):
    """Le corps COMMUN aux quatre. Aucun parametre de role n'entre ici, a dessein.

    Rend le TORSE : c'est la piece de fusion (voir `_join`), choisie parce qu'elle porte le
    materiau principal et qu'elle existe pour les quatre roles.
    """
    sw, sd = w / 0.56, d / 0.42
    # V2 (2026-08-12) — VOLUMES SECONDAIRES. Ce qui manquait a V1, mesure piece par piece
    # sur les 11 volumes du corps : ni cou, ni epaules, ni ceinture, ni articulation de bras,
    # ni revers de botte. Une figurine se lit a ses RUPTURES de volume ; sans elles, le
    # personnage restait une pile de boites lisses. Aucun polygone ajoute « pour faire
    # nombre » : chaque volume ci-dessous porte une rupture identifiable a distance.

    # Jambes, bottes et REVERS. Le revers marque la limite jambe/pied — sans lui, une botte
    # n'est qu'une jambe plus large.
    for cote, sx in (("g", -0.095), ("d", 0.095)):
        _box(f"{name}_botte_{cote}", 0.175 * sw, 0.235 * sd,
             F_BOTTE_H * h, cx=sx, cy=-0.015, base_z=0.0, mat=accent)
        _box(f"{name}_revers_{cote}", 0.195 * sw, 0.190 * sd, 0.035 * h,
             cx=sx, cy=-0.010, base_z=F_BOTTE_H * h, mat=accent)
        _box(f"{name}_jambe_{cote}", 0.130 * sw, 0.150 * sd,
             (F_JAMBE_HAUT - F_JAMBE_BAS) * h, cx=sx, base_z=F_JAMBE_BAS * h, mat=principal)
    # Torse — PIECE DE FUSION (rendue en fin de fonction).
    torse = _box(f"{name}_torse", 0.345 * sw, 0.225 * sd,
                 (F_TORSE_HAUT - F_TORSE_BAS) * h, base_z=F_TORSE_BAS * h, mat=principal)
    # CEINTURE : debord lateral net a la taille. C'est la rupture qui separe le buste des
    # jambes quand la figurine est vue de loin.
    _box(f"{name}_ceinture", 0.375 * sw, 0.250 * sd, 0.050 * h,
         base_z=(F_TORSE_BAS + 0.005) * h, mat=accent)
    # HARNAIS en croix sur la poitrine : deux bandes fines, la seule zone du torse qui
    # portait zero information en V1.
    _box(f"{name}_harnais", 0.110 * sw, 0.240 * sd, 0.170 * h,
         base_z=(F_TORSE_BAS + 0.070) * h, mat=accent)
    # SAC DORSAL commun a l'escouade : c'est lui qui fait lire « equipe » plutot que
    # « figurine nue », et il est identique aux quatre — donc il unifie le set.
    _box(f"{name}_sac", 0.250 * sw, 0.115 * sd, 0.215 * h,
         cy=0.150 * sd, base_z=(F_TORSE_BAS + 0.035) * h, mat=accent)
    # EPAULES pour les quatre (V1 n'en donnait qu'a l'assaut). Elles creent la ligne
    # horizontale qui fait la difference entre un buste et une boite.
    for cote, sx in (("g", -0.185), ("d", 0.185)):
        _box(f"{name}_epaule_{cote}", 0.125 * sw, 0.215 * sd, 0.070 * h,
             cx=sx, base_z=(F_TORSE_HAUT - 0.075) * h, mat=principal)
    # BRAS EN DEUX SEGMENTS + mains exagerees. Le bras superieur est plus epais que
    # l'avant-bras : l'articulation se lit sans aucune animation.
    for cote, sx in (("g", -0.225), ("d", 0.225)):
        _box(f"{name}_brasH_{cote}", 0.110 * sw, 0.150 * sd, 0.115 * h,
             cx=sx, base_z=(F_BRAS_HAUT - 0.115) * h, mat=principal)
        _box(f"{name}_brasB_{cote}", 0.090 * sw, 0.125 * sd,
             (F_BRAS_HAUT - 0.115 - F_BRAS_BAS) * h, cx=sx, base_z=F_BRAS_BAS * h,
             mat=principal)
        _box(f"{name}_main_{cote}", 0.130 * sw, 0.155 * sd,
             (F_MAIN_HAUT - F_MAIN_BAS) * h, cx=sx, base_z=F_MAIN_BAS * h, mat=accent)
    # COU : sans lui la tete etait posee a plat sur le torse, defaut le plus visible en V1.
    _box(f"{name}_cou", 0.130 * sw, 0.130 * sd, 0.045 * h,
         base_z=(F_TETE_BAS - 0.030) * h, mat=accent)
    # Tete + VISIERE. Pas de visage : une bande sombre en facade, lisible a distance et
    # impossible a confondre avec un micro-detail.
    _box(f"{name}_tete", 0.265 * sw, 0.220 * sd,
         (F_TETE_HAUT - F_TETE_BAS) * h, base_z=F_TETE_BAS * h, mat=principal)
    _box(f"{name}_visiere", 0.240 * sw, 0.055 * sd, 0.060 * h,
         cy=-0.113 * sd, base_z=0.715 * h, mat=accent)
    # BORDURE DE CASQUE, commune : elle pose le casque sur la tete au lieu de l'y faire
    # flotter. Le casque lui-meme reste la piece qui varie par role.
    _box(f"{name}_bordure", 0.290 * sw, 0.245 * sd, 0.035 * h,
         base_z=(F_CASQUE_BAS - 0.030) * h, mat=accent)
    return torse


def _soldier_role(name, role, w, d, h, principal, accent):
    """CE QUI DIFFERE — casque + un accessoire, rien d'autre. Volontairement court : plus
    cette fonction grossit, moins les quatre personnages appartiennent au meme set."""
    sw, sd = w / 0.56, d / 0.42
    if role == "scout":
        # Casque rond + OREILLETTES : le casque est un volume porte, pas une bille posee.
        _sphere(f"{name}_casque", 0.155 * sw, 0.140 * sd, 0.110 * h / 0.82,
                center_z=(F_CASQUE_BAS + 0.010) * h, mat=principal)
        for cote, sx in (("g", -0.135), ("d", 0.135)):
            _box(f"{name}_oreillette_{cote}", 0.045 * sw, 0.110 * sd, 0.070 * h,
                 cx=sx, base_z=(F_CASQUE_BAS - 0.020) * h, mat=accent)
        _box(f"{name}_radio", 0.100 * sw, 0.080 * sd, 0.140 * h,
             cx=-0.080, cy=0.150 * sd, base_z=0.600 * h, mat=accent)
        _box(f"{name}_antenne", 0.035 * sw, 0.035 * sd, 0.155 * h,
             cx=-0.080, cy=0.150 * sd, base_z=0.740 * h, mat=accent)
    elif role == "assault":
        # Casque anguleux : coque + CRETE longitudinale + pointe frontale. Trois ruptures,
        # la silhouette la plus dure des quatre.
        _box(f"{name}_casque", 0.290 * sw, 0.240 * sd, 0.135 * h,
             base_z=F_CASQUE_BAS * h, mat=principal)
        _box(f"{name}_crete", 0.070 * sw, 0.250 * sd, 0.055 * h,
             base_z=(F_CASQUE_BAS + 0.135) * h, mat=accent)
        _box(f"{name}_casque_pointe", 0.260 * sw, 0.090 * sd, 0.060 * h,
             cy=-0.145 * sd, base_z=(F_CASQUE_BAS + 0.020) * h, mat=accent)
        # EPAULIERES renforcees, POSEES SUR les epaules communes : plus larges et plus
        # hautes, elles se lisent comme un blindage ajoute et non comme une autre anatomie.
        for cote, sx in (("g", -0.215), ("d", 0.215)):
            _box(f"{name}_epauliere_{cote}", 0.165 * sw, 0.235 * sd, 0.065 * h,
                 cx=sx, base_z=0.645 * h, mat=accent)
    elif role == "tech":
        # Dome bas + BARRE DE VISEE large en avant (elle se lit d'en haut) + LAMPE laterale.
        _sphere(f"{name}_casque", 0.145 * sw, 0.135 * sd, 0.085 * h / 0.82,
                center_z=(F_CASQUE_BAS + 0.020) * h, mat=principal)
        _box(f"{name}_barre_visee", 0.335 * sw, 0.075 * sd, 0.060 * h,
             cy=-0.150 * sd, base_z=(F_CASQUE_BAS - 0.010) * h, mat=accent)
        _box(f"{name}_lampe", 0.060 * sw, 0.075 * sd, 0.055 * h,
             cx=0.150, cy=-0.130 * sd, base_z=(F_CASQUE_BAS + 0.020) * h, mat=accent)
        _box(f"{name}_module_dorsal", 0.215 * sw, 0.120 * sd, 0.215 * h,
             cy=0.165 * sd, base_z=0.600 * h, mat=accent)
    elif role == "demo":
        # Large bord circulaire (le seul a se lire comme un DISQUE d'en haut) + BAVOLET de
        # nuque : la protection du demineur descend dans le cou.
        _cyl(f"{name}_bord", 0.200 * sw, 0.040 * h, base_z=(F_CASQUE_BAS + 0.005) * h,
             mat=accent, verts=12)
        _sphere(f"{name}_casque", 0.140 * sw, 0.130 * sd, 0.100 * h / 0.82,
                center_z=(F_CASQUE_BAS + 0.050) * h, mat=principal)
        _box(f"{name}_bavolet", 0.230 * sw, 0.060 * sd, 0.090 * h,
             cy=0.115 * sd, base_z=(F_CASQUE_BAS - 0.075) * h, mat=accent)
        _box(f"{name}_sacoche", 0.255 * sw, 0.140 * sd, 0.175 * h,
             cy=0.160 * sd, base_z=0.590 * h, mat=accent)
    else:
        raise SystemExit(f"role de soldier inconnu (liste fermee {SOLDIER_ROLES}): {role}")


# ---------------------------------------------------------------------------------------
# GRAMMAIRE DE PROPS « JOUET DE GUERRE » — direction A, art-bible revision 3.
#
#     volume principal (dit CE QUE C'EST) + 1 a 2 familles de volumes secondaires
#     (disent A QUOI CA SERT)
#
# Jamais une sculpture. Une sangle est une boite fine en saillie, un rebord est une bande,
# une poignee est une boite fine. LE DETAIL EST TOUJOURS DE LA GEOMETRIE, JAMAIS UNE
# TEXTURE : la direction A interdit les textures peintes, donc un detail qui n'est pas un
# volume n'existe simplement pas a l'ecran.
#
# Les trois archetypes ci-dessous sont ecrits COMME UN LOT, exactement pour la meme raison
# que les quatre `soldier` partagent `_soldier_body` : ce qui est teste ici n'est pas
# « une caisse », c'est la grammaire. Le plancher de lisibilite est donc calcule par UNE
# fonction commune ; corriger la grammaire corrige les trois d'un coup, et il est
# impossible d'embellir une piece isolement sans le voir.
#
# PLANCHER DE LISIBILITE — la camera de jeu regarde a ~30 deg de la verticale. Sous ~0,09 m,
# une saillie ne produit ni silhouette ni ombre exploitable a cette distance : elle est
# invisible, et comme la texture est interdite, un detail invisible n'existe pas. Chaque
# epaisseur et chaque saillie des trois archetypes passe donc par `_epaisseur()` : le
# plancher est MECANIQUE, il ne depend pas de la vigilance de qui ecrit les nombres.
#
# DEUX REGLES AJOUTEES APRES MESURE (passe 1 rendue puis regardee, 2026-08-12) — elles ne
# sont pas des preferences, ce sont les deux ecarts qui ont fait echouer deux pieces sur
# trois pendant que la troisieme passait :
#
#   (R1) LE PRINCIPAL DOIT DOMINER. Un volume secondaire est une BANDE ou une PLAQUE en
#        saillie SUR la masse, jamais une seconde masse ni un essaim. La caisse de la
#        passe 1 portait dix volumes secondaires (4 montants d'angle pleine hauteur + 6
#        pieces de sangle) : elle se lisait « cage/palette », le corps avait disparu. Le
#        bidon, lui, passait — un cylindre dominant + 2 bandes + 1 capuchon. La grammaire
#        a donc ete corrigee VERS ce que le bidon faisait deja, et les trois refaits.
#        Consequence directe : les ferrures de la caisse sont devenues des CERCLAGES,
#        c'est-a-dire exactement le geste des rebords du bidon applique a une boite.
#
#   (R2) `size` EST L'ENCOMBREMENT TOTAL, saillies comprises — pour les trois. En passe 1
#        la caisse declarait 0,74 et mesurait 0,92 : la meme cle ne voulait pas dire la
#        meme chose d'un archetype a l'autre, et aucune comparaison d'echelle n'etait
#        possible. Le corps est donc bati a `w - 2e`, jamais a `w`.
LISIBILITE_MIN = 0.09


def _epaisseur(w, d, part=0.12):
    """Epaisseur/saillie unique du lot. Proportionnelle, mais jamais sous le plancher."""
    return max(LISIBILITE_MIN, part * min(w, d))


def _military_crate(name, w, d, h, mat):
    """FAMILLE DURE / MODULAIRE — angles francs, cerclage et sangles en saillie.

    Retourne le corps : c'est la piece de fusion (voir `_join`).
    """
    e = _epaisseur(w, d)
    hc = h - e                      # le corps ; la sangle occupe le dernier `e` en hauteur
    corps = _box(f"{name}_corps", w - 2 * e, d - 2 * e, hc, mat=mat)
    # SECONDAIRE 1 — FERRURES : deux CERCLAGES qui font le tour de la caisse. Ce sont les
    # memes bandes que les rebords du bidon, appliquees a une boite au lieu d'un cylindre
    # — c'est ce qui fait de ces trois pieces un lot et non trois inventions.
    #
    # ELLES SONT AUX DEUX EXTREMITES, pas a 1/6 et 2/3 comme a la passe 2. Placees dans le
    # corps, elles laissaient une bande de corps AU-DESSUS et AU-DESSOUS de chacune : la
    # piece se lisait « pile de plateaux » en vue basse, le corps ayant perdu sa continuite.
    # A ras du sol et a ras du couvercle, elles bornent le corps au lieu de le trancher, et
    # celui du bas se lit en plus comme un patin — ce qu'est vraiment une caisse de terrain.
    _box(f"{name}_ferrure_bas", w, d, 1.2 * e, base_z=0.0, mat=mat)
    _box(f"{name}_ferrure_haut", w, d, 1.2 * e, base_z=hc - 1.2 * e, mat=mat)
    # SECONDAIRE 2 — SANGLES : deux bandes sur le DESSUS, la face que la camera voit le
    # plus. Elles debordent de `e` sur les deux flancs, donc elles se lisent comme un lien
    # qui passe par-dessus et non comme une bosse posee.
    for i, fx in enumerate((-0.22, 0.22)):
        _box(f"{name}_sangle_{i}", 2 * e, d, e, cx=fx * w, base_z=hc, mat=mat)
    return corps


def _sandbag(name, w, d, h, mat):
    """FAMILLE MOU / GENEREUSE — l'oppose exact de la caisse, et le test central du lot.

    Ce n'est PAS un cube auquel on ajoute des details : le volume principal est un
    ellipsoide ecrase et ALLONGE, et il n'existe aucune boite dans la masse. Les seules
    boites sont les deux bouts noues, qui sont REELLEMENT plats sur un vrai sac.

    L'ALLONGEMENT est le parametre qui decide de la lecture, pas l'arrondi. Mesure de la
    passe 1 : avec rx/ry = 1,29 la piece se lisait « champignon » ou « chapeau » — un
    ellipsoide presque circulaire vu de dessus est un DOME, jamais un sac. Ici rx/ry vaut
    ~1,64 et la piece se lit comme un sac couche.
    """
    e = _epaisseur(w, d)
    rx1, ry1, rz1 = w / 2.0 - e, 0.45 * d, 0.30 * h
    # PRINCIPAL — le sac du bas. `seg` (roundeur vue de DESSUS) est privilegie sur `rings`
    # (roundeur de profil) : la camera regarde a ~30 deg de la verticale, c'est la
    # silhouette vue d'en haut qui porte la lecture « mou ».
    sac = _sphere(f"{name}_sac_bas", rx1, ry1, rz1, center_z=rz1, mat=mat, seg=10, rings=5)
    # SECONDAIRE 1 — SAC SUPERIEUR. Deux contraintes, chacune tiree d'un echec mesure :
    #   * NETTEMENT plus petit (0,62 du principal) — a 0,82 il recouvrait le sac du bas vu
    #     d'en haut, et les deux masses fusionnaient en un dome unique ;
    #   * DECALE LATERALEMENT jusqu'a DEBORDER du sac du bas — c'est le porte-a-faux, et
    #     lui seul, qui dit « empile » plutot que « pose au milieu ».
    rx2, ry2, rz2 = rx1 * 0.62, ry1 * 0.80, 0.26 * h
    _sphere(f"{name}_sac_haut", rx2, ry2, rz2, cx=-0.19 * w, cy=0.09 * d,
            center_z=h - rz2, mat=mat, seg=8, rings=4)
    # SECONDAIRE 2 — COUTURES : les deux bouts noues, aplatis, en saillie de `e`. Elles
    # fixent aussi l'encombrement declare : largeur totale = 2*(rx1 + e) = w.
    for i, sx in enumerate((-1, 1)):
        _box(f"{name}_couture_{'a' if sx < 0 else 'b'}", 2 * e, ry1 * 1.30, e * 1.15,
             cx=sx * rx1, base_z=rz1 * 0.50, mat=mat)
    return sac


def _fuel_drum(name, w, d, h, mat):
    """FAMILLE CYLINDRIQUE UTILITAIRE — volume cylindrique franc, rebords et capuchon gros.

    `min(w, d)` est l'encombrement des REBORDS, pas celui du corps : le corps est en
    retrait de `e`, ce qui garantit que la saillie du rebord vaut exactement le plancher
    de lisibilite au lieu d'etre un residu d'arrondi.
    """
    e = _epaisseur(w, d)
    r_ext = min(w, d) / 2.0
    r = r_ext - e
    hc = h - e                      # le capuchon occupe le dernier `e` en hauteur
    corps = _cyl(f"{name}_corps", r, hc, mat=mat, verts=12)
    # SECONDAIRE 1 — REBORDS de roulage : deux bandes. Hauteur 1,4*e, saillie e : les deux
    # dimensions qui les rendent visibles sont au-dessus du plancher, pas seulement une.
    for i, fz in enumerate((0.16, 0.70)):
        _cyl(f"{name}_rebord_{i}", r_ext, e * 1.4, base_z=fz * hc, mat=mat, verts=12)
    # SECONDAIRE 2 — CAPUCHON de remplissage, DECENTRE. Le decentrage est ce qui distingue
    # un bidon d'un simple cylindre : il donne une face avant a un volume de revolution.
    _cyl(f"{name}_capuchon", max(e * 1.2, r * 0.42), e, cx=r * 0.45, base_z=hc,
         mat=mat, verts=8)
    return corps


def build(spec):
    """Construit la geometrie. Retourne la liste des noms d'objets crees."""
    a = spec["archetype"]
    w = float(spec["size"]["w"])
    d = float(spec["size"]["d"])
    h = float(spec["size"]["h"])
    col = tuple(spec.get("color", [0.55, 0.45, 0.35, 1.0]))
    name = spec["asset_id"]
    mat = _mat(f"{name}_mat", col)

    if a == "crate":
        _box(name, w, d, h, mat=mat)
    elif a == "platform":
        _box(name, w, d, h, mat=mat)
    elif a == "pillar":
        _cyl(name, min(w, d) / 2.0, h, mat=mat)
    elif a == "barrel":
        _cyl(name, min(w, d) / 2.0, h, mat=mat, verts=24)
    elif a == "button":
        _cyl(f"{name}_base", min(w, d) / 2.0, h * 0.3, mat=mat)
        _cyl(f"{name}_cap", min(w, d) / 2.0 * 0.7, h * 0.7, base_z=h * 0.3,
             mat=_mat(f"{name}_cap_mat", (0.8, 0.15, 0.15, 1.0)))
    elif a == "door":
        jamb = _mat(f"{name}_jamb_mat", (0.35, 0.30, 0.25, 1.0))
        t = w * 0.12
        _box(f"{name}_panel", w - 2 * t, d, h - t, mat=mat)
        _box(f"{name}_jamb_left", t, d, h, cx=-(w / 2 - t / 2), mat=jamb)
        _box(f"{name}_jamb_right", t, d, h, cx=(w / 2 - t / 2), mat=jamb)
        _box(f"{name}_lintel", w, d, t, base_z=h - t, mat=jamb)
    elif a == "soldier":
        role = spec.get("role")
        if role not in SOLDIER_ROLES:
            raise SystemExit(f"spec soldier : champ 'role' requis dans {SOLDIER_ROLES} "
                             f"(recu: {role!r})")
        accent = _mat(f"{name}_accent_mat",
                      tuple(spec.get("accent", [0.16, 0.16, 0.19, 1.0])))
        torse = _soldier_body(name, w, d, h, mat, accent)
        _soldier_role(name, role, w, d, h, mat, accent)
        # UN SEUL objet en sortie : voir `_join` pour la raison mecanique.
        _join(name, torse)
    elif a in ("military_crate", "sandbag", "fuel_drum"):
        # LOT « jouet de guerre ». Un seul objet en sortie, meme raison mecanique que pour
        # `soldier` : chaque volume secondaire pese moins de `main_share_threshold` des
        # sommets, donc sans fusion l'oracle les classerait UNKNOWN et rendrait BLOCKED,
        # en exigeant un manifeste que le producteur n'a pas le droit d'ecrire.
        principal = {"military_crate": _military_crate,
                     "sandbag": _sandbag,
                     "fuel_drum": _fuel_drum}[a](name, w, d, h, mat)
        _join(name, principal)
    elif a == "chest":
        # Le couvercle est une VARIANTE : deux etats exclusifs livres ensemble.
        # L'oracle bloquera donc cet asset tant qu'un humain n'aura pas declare
        # les roles -- comportement voulu, c'est la porte qui fonctionne.
        _box(f"{name}_body", w, d, h * 0.6, mat=mat)
        lid = _mat(f"{name}_lid_mat", (0.45, 0.35, 0.25, 1.0))
        _box(f"{name}_lid_closed", w, d, h * 0.4, base_z=h * 0.6, mat=lid)
        _box(f"{name}_lid_open", w, d * 0.4, h * 0.4, cy=-d * 0.8, base_z=h * 0.6, mat=lid)
    else:
        raise SystemExit(f"archetype inconnu (liste fermee {ARCHETYPES}): {a}")

    return [o.name for o in bpy.data.objects if o.type == "MESH"]


def measure_declaration():
    """Ce que le producteur CROIT avoir fait. Jamais une preuve — juste sa parole."""
    lo, hi = 1e9, -1e9
    dx = dy = 0.0
    xs, ys = [], []
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ __import__("mathutils").Vector(c)
            lo = min(lo, w.z)
            hi = max(hi, w.z)
            xs.append(w.x)
            ys.append(w.y)
    if xs:
        dx = max(xs) - min(xs)
        dy = max(ys) - min(ys)
    # Blender est Z-up ; le GLB exporte est Y-up. La declaration parle en Y (espace fichier).
    return {"lowest_point_y": round(lo, 6), "height_y": round(hi - lo, 6),
            "width_x": round(dx, 6), "depth_z": round(dy, 6)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    spec_path, dest = argv[0], argv[1]
    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)

    for champ in ("asset_id", "archetype", "category", "size", "consumer"):
        if champ not in spec:
            raise SystemExit(f"spec incomplete : champ '{champ}' absent")
    if not spec["consumer"]:
        raise SystemExit("spec refusee : aucun consumer — un asset sans consommateur "
                         "n'entre pas dans la bibliotheque")

    os.makedirs(dest, exist_ok=True)
    _reset()
    objets = build(spec)

    glb = os.path.join(dest, f"{spec['asset_id']}.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB")

    decl = measure_declaration()
    meta = {
        "schema_version": SCHEMA_VERSION,
        "_statut": "DECLARATION — ne fait JAMAIS foi (confrontee par declaration_mismatch)",
        "asset_id": spec["asset_id"],
        "category": spec["category"],
        "style": spec.get("style", "lowpoly"),
        "license": "CC0-1.0",
        "source": ORIGINAL_MARKER + " — forge/asset_producer/build_asset.py",
        "provenance_url": None,
        "produced_by": f"blender {bpy.app.version_string} / archetype={spec['archetype']}",
        "origin_rule": "base_center",
        "ground_rule": "base_contact",
        "variants": spec.get("variants", []),
        "consumer_examples": spec["consumer"],
        **decl,
    }
    with open(glb + ".metadata.json", "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)

    report = {
        "schema_version": SCHEMA_VERSION,
        "asset_id": spec["asset_id"],
        "archetype": spec["archetype"],
        "params": {"size": spec["size"], "color": spec.get("color")},
        "objects_created": objets,
        "blender_version": bpy.app.version_string,
        "glb_bytes": os.path.getsize(glb),
        "manifest_written": False,
        "manifest_note": ("le producteur n'ecrit JAMAIS <asset>.glb.geometry.json : "
                          "le recensement des roles appartient au HumanGate"),
    }
    with open(os.path.join(dest, f"{spec['asset_id']}.generation_report.json"),
              "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)

    print(f"PRODUCED|{spec['asset_id']}|{os.path.getsize(glb)}|objets={len(objets)}")


main()
