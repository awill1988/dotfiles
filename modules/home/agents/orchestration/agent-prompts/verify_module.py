"""Exercise evaluated Nix installation contracts in temporary homes."""

import json
from pathlib import Path
import sys
import tempfile

from install_prompts import install


def verify(cases):
    assert cases['disabled'] == {'manifest': {}, 'activation': {}}
    enabled = cases['enabled']['manifest']
    aliases = enabled['aliases']
    for name, filename in [('agy', 'AGY.md'), ('claude', 'CLAUDE.md'),
                           ('codex', 'AGENTS.override.md'), ('opencode', 'AGENTS.md')]:
        assert f'/home/example/custom {name}/{filename}' in aliases
    assert '/home/example/.config/profiles/work/codex/AGENTS.override.md' not in aliases
    assert '/home/example/.config/antigravity-restricted/AGY.md' in aliases
    assert len(cases['no_profiles']['manifest']['files']) == 1
    assert not any('codex' in path for path in cases['no_codex']['manifest']['aliases'])
    assert cases['source_override']['manifest']['source'] != enabled['source']
    for name, case in cases.items():
        if name == 'disabled':
            continue
        assert set(case['activation']['ensureAgentPrompts']['after']) == {
            'writeBoundary', 'linkGeneration', 'ensureProfileDirs'}
        assert 'run ' in case['activation']['ensureAgentPrompts']['data']
        with tempfile.TemporaryDirectory() as directory:
            manifest = case['manifest']
            relocate = lambda path: path.replace('/home/example', directory, 1)
            relocated = {
                'source': manifest['source'],
                'files': [relocate(path) for path in manifest['files']],
                'aliases': {relocate(path): relocate(target) for path, target in manifest['aliases'].items()},
                'backup_dir': relocate(manifest['backup_dir']),
            }
            install(relocated)
            expected = Path(manifest['source']).read_bytes()
            for path in relocated['files'] + list(relocated['aliases']):
                assert Path(path).read_bytes() == expected, path
            assert install(relocated) == []
    print('prompt module contracts passed')


if __name__ == '__main__':
    verify(json.loads(Path(sys.argv[1]).read_text()))
