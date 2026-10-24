#!/usr/bin/env python3
"""Account-free synthetic fixtures, exclusively inside dedicated dev HOME."""
import json
import os
from pathlib import Path

home = Path('/home/tester')
if Path.home() != home or os.getuid() != 1000:
    raise SystemExit('Refusing unexpected development identity')
marker = home / '.goverlay-synthetic-dev-v1'
if marker.exists():
    if marker.is_symlink() or marker.read_text() != 'synthetic development HOME v1\n':
        raise SystemExit('Refusing unknown development HOME marker')
    raise SystemExit(0)
# A mount-selection mistake must never seed an authenticated research HOME.
if any(home.rglob('accounts.json')):
    raise SystemExit('Refusing HOME containing Prism accounts')
roots = [
    home / '.local/share/PrismLauncher',
    home / '.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher',
    home / 'synthetic-prism-custom',
]
if any(root.exists() for root in roots):
    raise SystemExit('Refusing pre-existing unmarked Prism roots')
for number, root in enumerate(roots):
    root.mkdir(parents=True)
    (root / 'prismlauncher.cfg').write_text('[General]\nConfigVersion=1.3\nInstanceDir=instances\n')
    for letter in 'AB':
        instance = root / 'instances' / letter
        instance.mkdir(parents=True)
        uid = f'{number + 1:01x}{letter.lower()}' + '0' * 30
        assert len(uid) == 32
        label = ('Native', 'Flatpak', 'Custom')[number]
        (instance / 'instance.cfg').write_text(
            '[General]\nConfigVersion=1.3\nInstanceType=OneSix\n'
            f'name=Synthetic {label} {letter}\nuuid={uid}\nJavaPath=/synthetic/shared/java\n')
        (instance / 'mmc-pack.json').write_text(json.dumps({
            'formatVersion': 1, 'components': [{'uid': 'net.minecraft', 'version': 'synthetic'}]}))
config = home / '.config/goverlay'
config.mkdir(parents=True, exist_ok=True)
with (config / 'prism_roots.json').open('x') as target:
    json.dump({'version': 1, 'roots': [str(roots[2])]}, target)
marker.write_text('synthetic development HOME v1\n')
print('Seeded 3 account-free Prism roots / 6 A/B instances before GUI startup')
