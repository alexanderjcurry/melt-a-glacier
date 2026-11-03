# Sound and music

Every sound in the game is original: made from scratch by the Python scripts
in `art/audio/` (oscillators, noise, filters and a little reverb, using numpy
and scipy). No recordings, sample packs or third-party audio are used, so
there is nothing to license or credit. The files here are part of this game
and its source.

| Folder | What | How it plays |
|---|---|---|
| `sfx/` | 92 short sounds and loops: the six tool sprays, ice cracks and drips, finds, the shed, footsteps, the jetpack, helpers, the gate, jingles | One-offs as Web Audio samples on the web; loops mixed by Godot |
| `amb/` | Wind and summer birdsong (seamless loops) | Mixed by Godot, faded by `Sound` |
| `music/` | Five tunes: `valley_1`, `valley_2` (the village glacier), `lake_1`, `lake_2` (the frozen lake), `summer` (after the ending) | Mixed by Godot (streamed, not decoded up front) |

Rebuild after changing a script (needs `pip install numpy scipy` and ffmpeg
with libvorbis):

    python art/audio/make_sfx.py              # every sound effect and ambience loop
    python art/audio/make_sfx.py crack drip   # only names starting with these
    python art/audio/make_music.py            # every tune (about 2 minutes)
    python art/audio/make_music.py summer     # one tune

Names ending in `_1`, `_2`... are variations of one sound; the game picks one
at random each time (`Sound.play("crack")`). The game side is
`scripts/audio/sound.gd`.
