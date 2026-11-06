#!/usr/bin/env python3
"""Protect application Lua annotations and strictly read-only external libraries.

Utilisation depuis la racine du dépôt :
  python .github/skills/lua-code-audit/scripts/audit_guard.py capture
  python .github/skills/lua-code-audit/scripts/audit_guard.py capture-libraries
  python .github/skills/lua-code-audit/scripts/audit_guard.py verify
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

SKIP_DIRS = {'.git', '.venv', 'venv', 'node_modules', '__pycache__', '.tox', '.mypy_cache'}
SCHEMA_VERSION = 2
LIBRARY_DIRECTORY = 'libs'
ANNOTATION = re.compile(
    rb'[ \t]*--[ \t]+@AUDIT[ \t]+RF-[0-9]{4,}'
    rb'[ \t]+status=(?:KEEP|TO_REMOVE|NEED_UPDATE|COULD_MERGE|RENAME_CANDIDATE)'
    rb'(?:[ \t]+target=RF-[0-9]{4,})?'
    rb'[ \t]+doc=docs/code-audit/INDEX\.md#rf-[0-9]{4,}[ \t]*'
)


def has_library_component(relative_path: str) -> bool:
    return any(part.casefold() == LIBRARY_DIRECTORY for part in PurePosixPath(relative_path).parts)


def lua_sources(root: Path, include_libraries: bool = False) -> dict[str, Path]:
    found = {}
    skipped = {name.casefold() for name in SKIP_DIRS}
    for path in root.rglob('*'):
        if not path.is_file() or path.suffix.lower() != '.lua':
            continue
        relative = path.relative_to(root).as_posix()
        if any(part.casefold() in skipped for part in PurePosixPath(relative).parts):
            continue
        if not include_libraries and has_library_component(relative):
            continue
        found[relative] = path
    return found


def normalized_bytes(data: bytes) -> bytes:
    return b''.join(
        line for line in data.splitlines(keepends=True)
        if not ANNOTATION.fullmatch(line.rstrip(b'\r\n'))
    )


def digest(path: Path) -> str:
    return hashlib.sha256(normalized_bytes(path.read_bytes())).hexdigest()


def strict_digest(path: Path) -> str:
    if path.is_symlink():
        data = b'SYMLINK\0' + os.readlink(path).encode('utf-8', errors='surrogateescape')
    else:
        data = path.read_bytes()
    return hashlib.sha256(data).hexdigest()


def protected_library_files(root: Path) -> dict[str, str]:
    found = {}
    for current, directories, filenames in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        relative_directory = current_path.relative_to(root)
        parts = () if relative_directory == Path('.') else relative_directory.parts
        protected = any(part.casefold() == LIBRARY_DIRECTORY for part in parts)

        if relative_directory == Path('.'):
            directories[:] = [name for name in directories if name != '.git']

        if protected:
            for name in filenames:
                path = current_path / name
                if path.is_file() or path.is_symlink():
                    found[path.relative_to(root).as_posix()] = strict_digest(path)

        for name in tuple(directories):
            path = current_path / name
            if not path.is_symlink():
                continue
            relative = path.relative_to(root).as_posix()
            if protected or name.casefold() == LIBRARY_DIRECTORY:
                found[relative] = strict_digest(path)
            directories.remove(name)

    return dict(sorted(found.items()))


def git_library_worktree_changes(root: Path) -> dict:
    try:
        result = subprocess.run(
            ['git', '-C', str(root), 'status', '--porcelain=v1', '-z', '--untracked-files=all'],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        return {'available': False, 'error': str(exc), 'paths': []}

    if result.returncode != 0:
        error = result.stderr.decode('utf-8', errors='replace').strip()
        return {'available': False, 'error': error or 'git status failed', 'paths': []}

    records = result.stdout.split(b'\0')
    changes = []
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if len(record) < 4:
            continue
        status = record[:2].decode('ascii', errors='replace')
        path = record[3:].decode('utf-8', errors='surrogateescape').replace('\\', '/')
        if has_library_component(path):
            changes.append({'status': status, 'path': path})
        if 'R' in status or 'C' in status:
            if index < len(records):
                old_path = records[index].decode('utf-8', errors='surrogateescape').replace('\\', '/')
                index += 1
                if has_library_component(old_path):
                    changes.append({'status': status, 'path': old_path, 'related_path': path})

    return {'available': True, 'paths': changes}


def legacy_library_differences(old_files: dict, current_lua: dict[str, Path]) -> list[dict]:
    legacy = {path: checksum for path, checksum in old_files.items() if has_library_component(path)}
    current = {
        path: file_path for path, file_path in current_lua.items()
        if has_library_component(path)
    }
    differences = []
    for path in sorted(set(legacy) - set(current)):
        differences.append({'status': 'missing_since_legacy_baseline', 'path': path})
    for path in sorted(set(current) - set(legacy)):
        differences.append({'status': 'not_in_legacy_lua_baseline', 'path': path})
    for path in sorted(set(legacy) & set(current)):
        if legacy[path] != digest(current[path]):
            differences.append({'status': 'content_differs_from_legacy_baseline', 'path': path})
    return differences


def write_baseline(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f'.{path.name}.',
        suffix='.tmp',
        dir=path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as stream:
            json.dump(data, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
        os.replace(temporary_path, path)
    except OSError:
        temporary_path.unlink(missing_ok=True)
        raise


def read_baseline(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data, dict) or not isinstance(data.get('files'), dict):
            raise ValueError('format de baseline non supporté')
        return data
    except (OSError, ValueError) as exc:
        raise ValueError(f'baseline invalide : {exc}') from exc


def differences(expected: dict[str, str], current: dict[str, str], label: str) -> list[str]:
    errors = []
    for path in sorted(set(expected) - set(current)):
        errors.append(f'{label} SUPPRIMÉ : {path}')
    for path in sorted(set(current) - set(expected)):
        errors.append(f'{label} AJOUTÉ : {path}')
    for path in sorted(set(expected) & set(current)):
        if expected[path] != current[path]:
            errors.append(f'{label} CONTENU MODIFIÉ : {path}')
    return errors


def library_differences(expected: dict[str, str], current: dict[str, str]) -> list[str]:
    errors = []
    removed = set(expected) - set(current)
    added = set(current) - set(expected)
    expected_hash_counts = Counter(expected.values())
    current_hash_counts = Counter(current.values())
    moves = []

    for old_path in sorted(removed):
        checksum = expected[old_path]
        candidates = [path for path in sorted(added) if current[path] == checksum]
        if (
            len(candidates) == 1
            and expected_hash_counts[checksum] == 1
            and current_hash_counts[checksum] == 1
        ):
            new_path = candidates[0]
            moves.append((old_path, new_path))
            removed.remove(old_path)
            added.remove(new_path)

    for old_path, new_path in moves:
        errors.append(f'PROTÉGÉ DÉPLACÉ : {old_path} -> {new_path}')
    for path in sorted(removed):
        errors.append(f'PROTÉGÉ SUPPRIMÉ : {path}')
    for path in sorted(added):
        errors.append(f'PROTÉGÉ AJOUTÉ : {path}')
    for path in sorted(set(expected) & set(current)):
        if expected[path] != current[path]:
            errors.append(f'PROTÉGÉ MODIFIÉ : {path}')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description='Contrôle Lua et protection stricte des bibliothèques')
    parser.add_argument('command', choices=('capture', 'capture-libraries', 'verify'))
    parser.add_argument('--root', type=Path, default=Path.cwd(), help='Racine du dépôt')
    args = parser.parse_args()
    root = args.root.resolve()
    baseline = root / 'docs' / 'code-audit' / 'BASELINE.json'

    if args.command == 'capture':
        if baseline.exists():
            print(f'ERREUR: {baseline} existe déjà. Ne pas remplacer une baseline active.', file=sys.stderr)
            return 2
        created = datetime.now(timezone.utc).isoformat()
        app_files = lua_sources(root)
        library_files = protected_library_files(root)
        library_state = git_library_worktree_changes(root)
        data = {
            'schema_version': SCHEMA_VERSION,
            'created_utc': created,
            'meaning': (
                'SHA256 des fichiers Lua hors bibliothèques, en ignorant uniquement les lignes '
                '-- @AUDIT valides; SHA256 strict des octets de tous les fichiers sous les '
                'répertoires libs (sans ignorer les annotations).'
            ),
            'files': {path: digest(file_path) for path, file_path in sorted(app_files.items())},
            'protected_libraries': {
                'captured_utc': created,
                'meaning': 'SHA256 strict des octets; aucune annotation, normalisation ou extension exclue.',
                'files': library_files,
                'initial_worktree_state': library_state,
            },
        }
        try:
            write_baseline(baseline, data)
        except OSError as exc:
            print(f'ERREUR: impossible d’écrire la baseline : {exc}', file=sys.stderr)
            return 2
        print(f'BASELINE créée : {len(app_files)} fichiers Lua hors bibliothèques.')
        print(f'Protection stricte initiale : {len(library_files)} fichiers/entrées.')
        if library_state.get('paths'):
            print(
                f'AVERTISSEMENT: {len(library_state["paths"])} changement(s) Git préexistant(s) '
                'sous libs capturés comme état initial; aucun fichier restauré.'
            )
        elif not library_state.get('available'):
            print(
                'AVERTISSEMENT: état Git préexistant sous libs indisponible; '
                'le contenu courant est capturé comme état initial.'
            )
        print(f'Fichier : {baseline.relative_to(root)}')
        return 0

    if not baseline.exists():
        print('ERREUR: baseline absente. Exécuter capture avant toute annotation.', file=sys.stderr)
        return 2
    try:
        data = read_baseline(baseline)
    except ValueError as exc:
        print(f'ERREUR: {exc}', file=sys.stderr)
        return 2

    if args.command == 'capture-libraries':
        if data.get('schema_version') != 1:
            print(
                'ERREUR: la migration additive exige une baseline Lua schema_version=1 '
                'sans protection libs existante.',
                file=sys.stderr,
            )
            return 2
        if 'protected_libraries' in data:
            print('ERREUR: la protection libs existe déjà; refus de la remplacer.', file=sys.stderr)
            return 2

        current_app = lua_sources(root)
        expected_app = {
            path: checksum for path, checksum in data['files'].items()
            if not has_library_component(path)
        }
        current_app_hashes = {
            path: digest(file_path) for path, file_path in sorted(current_app.items())
        }
        app_errors = differences(expected_app, current_app_hashes, 'LUA')
        if app_errors:
            for error in app_errors:
                print('ERREUR:', error)
            print('Migration annulée : les sources Lua hors libs diffèrent de la baseline existante.')
            return 1

        current_all_lua = lua_sources(root, include_libraries=True)
        protected_files = protected_library_files(root)
        legacy_differences = legacy_library_differences(data['files'], current_all_lua)
        library_state = git_library_worktree_changes(root)
        captured = datetime.now(timezone.utc).isoformat()
        data['schema_version'] = SCHEMA_VERSION
        data['meaning'] = (
            'SHA256 des fichiers Lua hors bibliothèques, en ignorant uniquement les lignes '
            '-- @AUDIT valides; SHA256 strict des octets de tous les fichiers sous les '
            'répertoires libs (sans ignorer les annotations).'
        )
        data['files'] = expected_app
        data['protected_libraries'] = {
            'captured_utc': captured,
            'meaning': 'SHA256 strict des octets; aucune annotation, normalisation ou extension exclue.',
            'files': protected_files,
            'initial_worktree_state': library_state,
            'differences_from_legacy_lua_baseline': legacy_differences,
        }
        try:
            write_baseline(baseline, data)
        except OSError as exc:
            print(f'ERREUR: impossible d’écrire la baseline : {exc}', file=sys.stderr)
            return 2

        print(
            f'Protection libs ajoutée à la baseline existante : {len(protected_files)} '
            'fichiers/entrées strictement empreintés.'
        )
        print(
            f'Baseline Lua conservée : {len(expected_app)} fichiers hors libs; '
            'aucune source applicative n’a été remplacée.'
        )
        if legacy_differences:
            print(
                f'AVERTISSEMENT: {len(legacy_differences)} écart(s) avec l’ancienne baseline '
                'Lua consignés comme état initial; aucun fichier restauré.'
            )
        if library_state.get('paths'):
            print(
                f'AVERTISSEMENT: {len(library_state["paths"])} changement(s) Git préexistant(s) '
                'sous libs consignés comme état initial; aucun fichier restauré.'
            )
        elif not library_state.get('available'):
            print(
                'AVERTISSEMENT: état Git préexistant sous libs indisponible; '
                'le contenu courant est consigné comme état initial.'
            )
        return 0

    if data.get('schema_version') != SCHEMA_VERSION:
        print(
            'ERREUR: baseline sans protection stricte libs. Exécuter capture-libraries '
            'pour la migrer sans remplacer les empreintes existantes.',
            file=sys.stderr,
        )
        return 2
    protected = data.get('protected_libraries')
    if not isinstance(protected, dict) or not isinstance(protected.get('files'), dict):
        print('ERREUR: section protected_libraries absente ou invalide.', file=sys.stderr)
        return 2

    current_app = {path: digest(file_path) for path, file_path in sorted(lua_sources(root).items())}
    current_libraries = protected_library_files(root)
    errors = differences(data['files'], current_app, 'LUA')
    errors.extend(library_differences(protected['files'], current_libraries))
    for error in errors:
        print('ERREUR:', error)
    if errors:
        print(
            f'ÉCHEC : {len(errors)} problème(s). Les fichiers ne peuvent PAS être déclarés '
            'intacts; ne rien restaurer automatiquement.'
        )
        return 1
    print(f'OK : {len(current_app)} fichiers Lua hors bibliothèques inchangés (annotations permises).')
    print(
        f'OK : {len(current_libraries)} fichiers/entrées sous libs inchangés '
        '(empreintes strictes, annotations interdites).'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
