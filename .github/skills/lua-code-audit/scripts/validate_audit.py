#!/usr/bin/env python3
"""Valide la traçabilité des identifiants @AUDIT dans Lua et INDEX.md.

Zéro dépendance tierce. À lancer depuis la racine du projet.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path, PurePosixPath
from urllib.parse import unquote

SKIP_DIRS = {'.git', '.venv', 'venv', 'node_modules', '__pycache__', '.tox', '.mypy_cache'}
SKIP_DIRS_CASEFOLD = {name.casefold() for name in SKIP_DIRS}
LIBRARY_DIRECTORY = 'libs'
# @AUDIT RF-0023 status=FIXED doc=docs/code-audit/INDEX.md#rf-0023
# Le dépôt a dépassé le vocabulaire de refactorisation d'origine : une fiche
# peut aujourd'hui être corrigée, partiellement corrigée, ou rester ouverte.
# `FIXED`, `PARTIALLY_FIXED` et `OPEN` sont donc acceptés, en plus des cinq
# statuts de classification d'origine. Toute autre valeur reste refusée.
# RF-0023 : avant cet ajout, le validateur rejetait 10 tags `FIXED` /
# `PARTIALLY_FIXED` déjà présents dans le code applicatif.
STATUS = (
    'KEEP|TO_REMOVE|NEED_UPDATE|COULD_MERGE|RENAME_CANDIDATE'
    '|FIXED|PARTIALLY_FIXED|OPEN'
)
# `COULD_MERGE` est le seul statut qui exige une cible.
STATUS_REQUIRING_TARGET = {'COULD_MERGE'}
LIBRARY_TAG_RE = re.compile(rb'^[ \t]*--[ \t]*@AUDIT\b')
TAG_RE = re.compile(
    rf'^\s*--\s+@AUDIT\s+(RF-\d{{4,}})\s+status=({STATUS})'
    rf'(?:\s+target=(RF-\d{{4,}}))?'
    rf'\s+doc=docs/code-audit/INDEX\.md#(rf-\d{{4,}})\s*$'
)
ANCHOR_RE = re.compile(r'<a\s+id=["\'](rf-\d{4,})["\']\s*></a>', re.IGNORECASE)
SOURCE_RE = re.compile(r'^\s*[-*]\s+Source:\s*\[[^\]]+\]\(([^)]+)\)', re.MULTILINE)
STATUS_DOC_RE = re.compile(r'^\s*[-*]\s+Status:\s*(\S+)', re.MULTILINE)


def has_library_component(relative_path: str) -> bool:
    return any(part.casefold() == LIBRARY_DIRECTORY for part in PurePosixPath(relative_path).parts)


def main() -> int:
    parser = argparse.ArgumentParser(description='Validation tags Lua / index Markdown')
    parser.add_argument('--root', type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.root.resolve()
    index = root / 'docs' / 'code-audit' / 'INDEX.md'
    if not index.is_file():
        print('ERREUR: docs/code-audit/INDEX.md absent', file=sys.stderr)
        return 2

    errors = []
    warnings = []
    tags: dict[str, tuple[Path, int, str, str | None]] = {}
    for lua in root.rglob('*'):
        if not lua.is_file() or lua.suffix.lower() != '.lua':
            continue
        rel = lua.relative_to(root)
        if has_library_component(rel.as_posix()):
            try:
                lines = lua.read_bytes().splitlines()
            except OSError as exc:
                errors.append(f'Bibliothèque protégée illisible : {rel.as_posix()} ({exc})')
                continue
            for line_no, line in enumerate(lines, 1):
                if LIBRARY_TAG_RE.match(line):
                    errors.append(
                        f'Annotation @AUDIT interdite dans une bibliothèque externe : '
                        f'{rel.as_posix()}:{line_no}'
                    )
            continue
        if any(part.casefold() in SKIP_DIRS_CASEFOLD for part in rel.parts):
            continue
        try:
            lines = lua.read_text(encoding='utf-8-sig').splitlines()
        except UnicodeDecodeError:
            warnings.append(f'Encodage non UTF-8 non analysé : {rel.as_posix()}')
            continue
        for line_no, line in enumerate(lines, 1):
            if '@AUDIT' not in line:
                continue
            if not line.lstrip().startswith('--'):
                # Exemple : une chaîne contenant @AUDIT ne constitue pas un tag.
                continue
            if not re.match(r'^\s*--\s+@AUDIT\b', line):
                continue
            match = TAG_RE.fullmatch(line)
            if not match:
                errors.append(f'Tag mal formé : {rel.as_posix()}:{line_no}')
                continue
            tag_id, status, target, anchor = match.groups()
            if anchor != tag_id.lower():
                errors.append(f'Ancre différente de l’ID : {rel.as_posix()}:{line_no}')
            if tag_id in tags:
                prev_rel, prev_line, _, _ = tags[tag_id]
                errors.append(f'ID {tag_id} dupliqué : {prev_rel}:{prev_line} et {rel}:{line_no}')
            else:
                tags[tag_id] = (rel, line_no, status, target)
            if status in STATUS_REQUIRING_TARGET and target is None:
                errors.append(f'{tag_id} {status} doit avoir target=RF-XXXX')
            if status not in STATUS_REQUIRING_TARGET and target is not None:
                errors.append(f'{tag_id} ne doit pas avoir target=')
            if target == tag_id:
                errors.append(f'{tag_id} ne peut pas être sa propre cible')

    doc = index.read_text(encoding='utf-8')
    anchors = list(ANCHOR_RE.finditer(doc))
    counts = Counter(m.group(1).lower() for m in anchors)
    for anchor, count in counts.items():
        if count != 1:
            errors.append(f'Ancre {anchor} dupliquée ({count} fois) dans INDEX.md')
    cards = {}
    for i, anchor_match in enumerate(anchors):
        beg = anchor_match.end()
        end = anchors[i + 1].start() if i + 1 < len(anchors) else len(doc)
        cards[anchor_match.group(1).upper()] = doc[beg:end]

    for tag_id, (rel, line_no, status, target) in tags.items():
        if tag_id not in cards:
            errors.append(f'{tag_id} dans {rel}:{line_no} absent de INDEX.md')
            continue
        card = cards[tag_id]
        status_match = STATUS_DOC_RE.search(card)
        if not status_match or status_match.group(1) != status:
            errors.append(f'{tag_id}: statut INDEX.md différent ou manquant (attendu {status})')
        source_match = SOURCE_RE.search(card)
        if not source_match:
            errors.append(f'{tag_id}: lien « - Source: [nom](chemin) » absent dans INDEX.md')
        else:
            source_href = source_match.group(1).split('#', 1)[0]
            source_abs = (index.parent / unquote(source_href)).resolve()
            try:
                source_rel = source_abs.relative_to(root).as_posix()
            except ValueError:
                source_rel = None
            if source_rel is not None and has_library_component(source_rel):
                errors.append(f'{tag_id}: un constat RF ne peut pas cibler une bibliotheque ({source_rel})')
            if source_abs != (root / rel).resolve():
                errors.append(f'{tag_id}: mauvais lien source {source_href} (attendu {rel.as_posix()})')
        if not re.search(r'^\s*[-*]\s+Confidence:\s+(HIGH|MEDIUM|LOW)\s*$', card, re.MULTILINE):
            errors.append(f'{tag_id}: Confidence absent/invalide')
        if not re.search(r'^\s*[-*]\s+Risk:\s+(HIGH|MEDIUM|LOW)\s*$', card, re.MULTILINE):
            errors.append(f'{tag_id}: Risk absent/invalide')
        if target and target not in tags:
            errors.append(f'{tag_id}: target {target} sans annotation correspondante')
        if target and f'#{target.lower()}' not in card and target not in card:
            warnings.append(f'{tag_id}: cible {target} non mentionnée dans sa fiche')

    for card_id in cards:
        if card_id not in tags:
            errors.append(f'{card_id}: fiche INDEX.md sans annotation Lua associée')

    for msg in warnings:
        print('AVERTISSEMENT:', msg)
    for msg in errors:
        print('ERREUR:', msg)
    print(f'Contrôle : {len(tags)} tags Lua ; {len(cards)} fiches documentaires ; {len(warnings)} avertissements ; {len(errors)} erreurs.')
    if errors:
        return 1
    print('OK : IDs, statuts, cibles et liens Lua ↔ INDEX cohérents.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
