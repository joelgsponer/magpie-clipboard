import re

group = None
entries = []
groups_order = []

with open('/tmp/emoji-test.txt') as f:
    for line in f:
        m = re.match(r'^# group: (.+)$', line)
        if m:
            group = m.group(1).strip()
            groups_order.append(group)
            continue
        if not line or line.startswith('#') or group is None:
            continue
        codepart, _, comment = line.partition('#')
        if 'fully-qualified' not in codepart:
            continue
        codes = codepart.split(';')[0].split()
        # Skip skin-tone variants for v1 (cleaner grid; tones deferred)
        if any(c.upper() in ('1F3FB','1F3FC','1F3FD','1F3FE','1F3FF') for c in codes):
            continue
        char = ''.join(chr(int(c, 16)) for c in codes)
        parts = comment.strip().split()
        name = ' '.join(parts[2:])  # strip leading emoji char + "E1.0" version token
        entries.append((char, name, group))

def swift_str(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

def ident(g):
    return re.sub(r'[^a-z0-9]+', '_', g.lower()).strip('_')

cats = []
seen = {}
for e in entries:
    seen.setdefault(e[2], []).append(e)
for g in groups_order:
    if g in seen:
        cats.append((g, seen[g]))

out = []
out.append('// Generated from Unicode emoji-test.txt v15.1 — do not edit by hand.')
out.append('// Regenerate with Scripts/gen_emoji.py (expects emoji-test.txt at /tmp/emoji-test.txt).')
out.append('import Foundation')
out.append('')
out.append('struct EmojiEntry: Identifiable, Hashable {')
out.append('    let char: String')
out.append('    let name: String      // lowercase CLDR short name, e.g. "face with tears of joy"')
out.append('    let category: String')
out.append('    var id: String { char }')
out.append('}')
out.append('')
out.append('enum EmojiData {')
out.append('    static let categories: [String] = [')
for g, _ in cats:
    out.append(f'        "{swift_str(g)}",')
out.append('    ]')
out.append('')
out.append('    static let entries: [EmojiEntry] =')
out.append('        ' + ' + '.join(f'entries_{ident(g)}' for g, _ in cats))
out.append('')
for g, es in cats:
    out.append(f'    // MARK: {g}')
    out.append(f'    private static let entries_{ident(g)}: [EmojiEntry] = [')
    for char, name, grp in es:
        out.append(f'        .init(char: "{char}", name: "{swift_str(name.lower())}", category: "{swift_str(grp)}"),')
    out.append('    ]')
    out.append('')
out.append('}')
open('/Users/joel/Documents/apps/Magpie/Sources/Magpie/Emoji/EmojiData.swift', 'w').write('\n'.join(out) + '\n')
print(len(entries), 'entries in', len(cats), 'categories')
