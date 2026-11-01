# Art sources

Everything here is made by script, so it can be changed and rebuilt rather than
hand-edited.

## 3D models (`art/blender/` -> `models/*.glb`)

Blender, driven from Python. `pip install bpy` gives Blender as a Python module
(Python 3.11; no Blender install needed), then run any build script:

    python art/blender/build_village.py      # house_0..4, church, well
    python art/blender/build_penguin.py      # penguin (Body, FlipperL/R, Foot)
    python art/blender/build_shed_props.py   # woodpile, barrel, lantern... round the shed
    python art/blender/build_pirates.py      # goblin pirate ships and crew frozen in the lake

`kit.py` is the shared modelling kit. It works in Godot coordinates (x right,
y up, -z forward) and on-screen sRGB colours, so numbers match the GDScript that
places the models. Godot imports the `.glb` files on its own; `scripts/models.gd`
loads them.

Style: chunky low-poly shapes with small bevels that catch the light, flat
colours (no textures), ink-dark wood trim, warm plaster, slate and copper.

House `i` is built for `HOUSES[i]` in `scripts/world.gd`: if a footprint
changes there, change `HOUSES` in `build_village.py` to match and rebuild.

## HUD (`art/ui/make_ui.py` -> `ui/*.png`)

Pillow draws the wooden sign, paper sheet, enamel buttons, progress bar and
round phone buttons as nine-patch images. Grey parts are tinted in the game
(`UiTheme.enamel(color)`), so one button image makes every colour.

Fonts (SIL Open Font License, in `fonts/`): Lilita One for titles and
buttons, Nunito ExtraBold for everything else.
