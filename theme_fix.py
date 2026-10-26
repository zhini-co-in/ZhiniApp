#!/usr/bin/env python3
"""
Hardcoded Colors.* -> theme-aware AppColors.*  (auto, whole lib/ folder)

Usage (project root la):
    python3 theme_fix.py            # lib/ full ah maathum (.bak backup create aagum)
    python3 theme_fix.py --dry      # edhu maarum nu mattum kaattum
    python3 theme_fix.py lib/a.dart lib/b.dart   # specific files
"""
import re, sys, pathlib, shutil

DRY = '--dry' in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith('--')]

# 1. Blue-button mela irukkura white -> onPrimary (munnadi run aagum)
ON_PRIMARY_RULES = [
    (r'(selected\s*\?\s*)Colors\.white\b', r'\1AppColors.onPrimary'),
    (r'(isSelected\s*\?\s*)Colors\.white\b', r'\1AppColors.onPrimary'),
    (r'(activeThumbColor:\s*)Colors\.white\b', r'\1AppColors.onPrimary'),
    (r'(Icons\.add,\s*color:\s*)Colors\.white\b', r'\1AppColors.onPrimary'),
    (r"(Text\('Create Ticket',\s*style:\s*(?:const\s+)?TextStyle\(color:\s*)Colors\.white\b", r'\1AppColors.onPrimary'),
    (r'(Icons\.qr_code_scanner_rounded,\s*color:\s*)Colors\.white\b', r'\1AppColors.onPrimary'),
    (r'(CircularProgressIndicator\(\s*color:\s*)Colors\.white\b', r'\1AppColors.onPrimary'),
    (r"(Text\(text,\s*style:\s*(?:const\s+)?TextStyle\(color:\s*)Colors\.white\b", r'\1AppColors.onPrimary'),
]

# 2. General mapping
GENERAL = [
    (r'\bColors\.white70\b', 'AppColors.textSecondary'),
    (r'\bColors\.white60\b', 'AppColors.textSecondary'),
    (r'\bColors\.white54\b', 'AppColors.textMuted'),
    (r'\bColors\.white38\b', 'AppColors.textFaint'),
    (r'\bColors\.white30\b', 'AppColors.textFaint'),
    (r'\bColors\.white24\b', 'AppColors.borderSubtle'),
    (r'\bColors\.white12\b', 'AppColors.borderSubtle'),
    (r'\bColors\.white10\b', 'AppColors.borderSubtle'),
    (r'\bColors\.white\b', 'AppColors.textPrimary'),
    (r'\bColors\.redAccent\b', 'AppColors.danger'),
    (r'\bColors\.red\b', 'AppColors.danger'),
    (r'\bColors\.greenAccent\b', 'AppColors.success'),
    (r'\bColors\.green\b', 'AppColors.success'),
    (r'\bColors\.orangeAccent\b', 'AppColors.warning'),
    (r'\bColors\.amber\b', 'AppColors.warning'),
    (r'\bColors\.blue\.shade300\b', 'AppColors.primaryBorder'),
    (r'\bColors\.blue\b', 'AppColors.primary'),
]

# 3. AppColors irukkura const expression la 'const' eduthudum
def strip_bad_consts(src):
    pat = re.compile(r'\bconst\s+(?=[A-Za-z_<\[(])')
    while True:
        changed = False
        for m in pat.finditer(src):
            i = m.end()
            j = i
            while j < len(src) and src[j] not in '([':
                j += 1
            if j >= len(src):
                continue
            depth, k = 0, j
            while k < len(src):
                if src[k] in '([{':
                    depth += 1
                elif src[k] in ')]}':
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            if 'AppColors.' in src[i:k + 1]:
                src = src[:m.start()] + src[m.end():]
                changed = True
                break
        if not changed:
            return src

def process(path):
    orig = path.read_text(encoding='utf-8')
    s = orig
    for p, r in ON_PRIMARY_RULES:
        s = re.sub(p, r, s)
    for p, r in GENERAL:
        s = re.sub(p, r, s)
    if s == orig:
        return False
    if 'theme/app_theme.dart' not in s:
        parts = path.resolve().relative_to(pathlib.Path('lib').resolve()).parts[:-1]
        rel = '../' * len(parts) + 'theme/app_theme.dart'
        s = re.sub(r"^(import [^\n]+\n)", r"\1import '%s';\n" % rel, s, count=1, flags=re.M)
    s = strip_bad_consts(s)
    print(('[dry] ' if DRY else '[fix] ') + str(path))
    if not DRY:
        shutil.copy(path, str(path) + '.bak')
        path.write_text(s, encoding='utf-8')
    return True

files = [pathlib.Path(a) for a in args] or sorted(pathlib.Path('lib').rglob('*.dart'))
n = sum(process(f) for f in files if f.name != 'app_theme.dart' and f.exists())
print('\n%d file(s) %s.' % (n, 'would change' if DRY else 'changed'))
