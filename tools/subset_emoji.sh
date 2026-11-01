#!/bin/bash
# Rebuilds fonts/NotoColorEmoji-subset.ttf with every emoji used in scripts/.
# Needs: pip install fonttools, and the full NotoColorEmoji.ttf
# (https://fonts.google.com/noto/specimen/Noto+Color+Emoji) passed as $1.
set -e
FULL="$1"
CHARS=$(python3 -c "
import glob
s=set()
for f in glob.glob('scripts/**/*.gd',recursive=True):
    s.update(c for c in open(f,encoding='utf-8').read() if ord(c)>0x2000)
print(','.join('U+%04X'%ord(c) for c in sorted(s)))")
pyftsubset "$FULL" --unicodes="$CHARS" --output-file=fonts/NotoColorEmoji-subset.ttf --layout-features='*'
echo "Done: fonts/NotoColorEmoji-subset.ttf"
