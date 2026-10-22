#!/usr/bin/env python3
"""Apply the attributed existing state rewriter with a 64-byte allocation contract.

FM1 Open's unchanged public DSP source has writable 32-byte-aligned objects.
The original Virtual FM-1 rewriter assumes a 16-byte-aligned host allocation;
this wrapper changes only that explicit bound, final padding and memset alignment.
It fails if those source anchors change instead of silently applying stale patches.
"""
from pathlib import Path
import sys

source = Path(__file__).with_name('fel_state.py')
text = source.read_text()
for before, after, count in [
    ('16-aligned', '64-aligned', 3),
    ("g['align'] > 16", "g['align'] > 64", 1),
    ('(off + 15) // 16 * 16', '(off + 63) // 64 * 64', 1),
    ('ptr align 16 %p', 'ptr align 64 %p', 1),
]:
    if text.count(before) != count:
        sys.exit('Official preview state rewrite anchor changed: ' + before)
    text = text.replace(before, after)
namespace = {'__name__': '__main__', '__file__': str(source)}
exec(compile(text, str(source), 'exec'), namespace)
