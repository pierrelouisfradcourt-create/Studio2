"""build_fixtures.py — genere les 5 fixtures de falsification avec Blender.

Blender est ici PRODUCTEUR (il fabrique des cas de test), jamais juge : les fixtures sont
ensuite mesurees par le parseur independant, et c'est cette mesure qui fait foi.

A executer depuis WSL :
  <blender> -b --python forge/asset_geometry/tests/build_fixtures.py -- <dest_dir>

Chaque fixture cible UN check et doit le faire echouer SEUL quand c'est possible --
sinon la fixture ne discrimine rien. En particulier `pivot_center` est POSEE au sol
(min_y = 0) avec son origine au centre : ground/buried passent, seul le pivot echoue.
"""
import sys
import os

import bpy


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_cube(name, size, base_y, origin_at_center, with_material=True):
    """Cube de cote `size` dont le bas est a `base_y`.

    origin_at_center=False -> l'origine de l'objet est au PIED (convention base_center)
    origin_at_center=True  -> l'origine reste au centre du cube (defaut Blender)
    with_material=False    -> aucun materiau : reproduit la signature d'une sortie
                              generative brute (Hunyuan3D), qui force le cas degrade
                              `main_geometry_undetermined` de l'oracle
    """
    # Blender est Z-up ; l'export glTF convertit en Y-up. On travaille donc en Z ici,
    # et la hauteur devient Y dans le fichier produit.
    bpy.ops.mesh.primitive_cube_add(size=size, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.name = name

    half = size / 2.0
    if origin_at_center:
        # origine au centre : on remonte l'objet pour que son bas soit a base_y
        ob.location = (0, 0, base_y + half)
    else:
        # origine au pied : on decale la GEOMETRIE de +half en local, puis on place
        # l'origine (l'objet) exactement a base_y
        for v in ob.data.vertices:
            v.co.z += half
        ob.location = (0, 0, base_y)

    if with_material:
        mat = bpy.data.materials.new(name=f"{name}_mat")
        ob.data.materials.append(mat)
    return ob


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB")
    print(f"FIXTURE_WRITTEN|{path}|{os.path.getsize(path)}")


FIXTURES = [
    # (nom, cote, base_y, origine_au_centre, materiau, check vise)
    ("posed_ok",       1.0,  0.00, False, True,  "aucun -- doit passer tous les checks"),
    ("floating",       1.0,  0.10, False, True,  "ground_contact"),
    ("buried",         1.0, -0.10, False, True,  "no_buried_geometry"),
    ("pivot_center",   1.0,  0.00, True,  True,  "pivot_at_base"),
    ("scale_x100",   100.0,  0.00, False, True,  "scale_within_band"),
    # Reproduit la signature d'une sortie Hunyuan3D brute : centree sur l'origine,
    # sans materiau. Rend le vrai positif reproductible en CI sans le fichier de
    # 13 Mo qui vit hors depot (~/3d-pipeline/output/demo_generated.glb).
    ("generated_like", 2.0, -1.00, True,  False, "no_buried_geometry + cas degrade"),
]


def main():
    dest = sys.argv[sys.argv.index("--") + 1]
    os.makedirs(dest, exist_ok=True)
    for name, size, base_y, center, mat, target in FIXTURES:
        reset()
        make_cube(name, size, base_y, center, with_material=mat)
        export(os.path.join(dest, f"{name}.glb"))
        print(f"  cible={target}")


main()
