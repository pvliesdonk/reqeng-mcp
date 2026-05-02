# Phase 1 — Read-Only Substrate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a working read-only substrate against StrictDoc — the agent can orient on a project, list/read nodes, run validation, export to HTML/ReqIF/Excel/Markdown, and create/archive projects, all wired through MCP tools and a parallel host-facing resource surface.

**Architecture:** A FastMCP server composing `fastmcp-pvl-core` primitives. Three new components: `SpecStore` (multi-project file-backed store), `StrictDocBackend` (single-boundary wrapper over StrictDoc internals), `git_strategy` module (adapted from markdown-mcp; in Phase 1 used only for `git init`/`clone`). All read tools take an optional `project_id` defaulted from `REQENG_MCP_DEFAULT_PROJECT` (Mode S) or required (Mode H). Write tools and ACL middleware are out of scope for Phase 1 — those are Phase 2.

**Tech Stack:** Python 3.11+, `fastmcp` + `fastmcp-pvl-core`, `strictdoc==0.20.0` (exact pin per spec §5.3), `pytest` + `pytest-asyncio` for tests, `ruff` for lint, `mypy` for types, `uv` for env management. Conventional commits.

**Spec reference:** [`docs/specs/2026-05-02-reqeng-mcp-design.md`](../specs/2026-05-02-reqeng-mcp-design.md). Section numbers cited below refer to that spec.

---

## File structure

### Source code (`src/reqeng_mcp/`)

| File | Status | Responsibility |
|---|---|---|
| `grammars/__init__.py` | **NEW** | Empty package marker |
| `grammars/default.sgra` | **NEW** | Bundled default grammar (StrictDoc L2 dogfood mirror per spec §4.2) |
| `types.py` | **NEW** | Our-shape dataclasses: `NodeRef`, `Document`, `Node`, `Relation`, `Grammar`, `ValidationFinding`, `HistoryEntry`, `CommitDiff` |
| `spec_store.py` | **NEW** | `FileSpecStore` — multi-project layout, project resolution, project listing |
| `strictdoc_backend.py` | **NEW** | `StrictDocBackend` — single boundary for StrictDoc internals (read paths only in Phase 1) |
| `grammar_resolver.py` | **NEW** | Four-step grammar resolution per spec §4.3 |
| `git_strategy.py` | **NEW** | Adapted from `markdown-mcp/src/markdown_vault_mcp/git.py`; in Phase 1 only init/clone exercised |
| `substrate.py` | **NEW** | Composition root: `Substrate` class holds `SpecStore` + `StrictDocBackend` cache + `git_strategy` factory |
| `config.py` | **MODIFY** | Add domain fields (between sentinels) per spec §3.2 |
| `domain.py` | **MODIFY** | Replace `Service` placeholder with re-export of `Substrate` |
| `_server_deps.py` | **MODIFY** | Lifespan instantiates `Substrate` from config |
| `tools.py` | **MODIFY** | Replace `ping` with all Phase 1 read + lifecycle + validation + export tools |
| `resources.py` | **MODIFY** | Register host-facing resources (URI templates per spec §6.6) |
| `prompts.py` | **NO CHANGE** | Stub stays (Phase 3 fills) |
| `server.py` | **MODIFY** | Update `domain_line` per spec §8.4 |

### Tests (`tests/`)

| File | Status | Responsibility |
|---|---|---|
| `conftest.py` | **MODIFY** | Add fixtures: `tmp_spec_root`, `minimal_project`, `multidoc_project`, `substrate`, `mcp_client` |
| `fixtures/grammars/default.sgra` | **NEW** | Pinned copy of bundled default (drift detection) |
| `fixtures/grammars/with_safety_extension.sgra` | **NEW** | ASIL-extended grammar fixture |
| `fixtures/grammars/malformed.sgra` | **NEW** | Failure-path fixture |
| `fixtures/projects/minimal/strictdoc_config.py` | **NEW** | Per spec §4.6 |
| `fixtures/projects/minimal/spec/calculator.sdoc` | **NEW** | One document, two REQUIREMENTS, one Parent relation |
| `fixtures/projects/multi-doc/strictdoc_config.py` | **NEW** | Per spec §4.6 |
| `fixtures/projects/multi-doc/spec/{a,b,c}.sdoc` | **NEW** | Three documents, cross-doc Parent links |
| `unit/test_specstore.py` | **NEW** | FileSpecStore tests |
| `unit/test_strictdoc_backend.py` | **NEW** | StrictDocBackend wrapper tests |
| `unit/test_grammar_resolution.py` | **NEW** | Four-path resolver tests |
| `unit/test_substrate.py` | **NEW** | Composition root tests |
| `integration/test_authoring_loop_readonly.py` | **NEW** | End-to-end read-only loop |
| `integration/test_create_project.py` | **NEW** | Project lifecycle |
| `integration/test_export_roundtrip.py` | **NEW** | All four exports against fixture |
| `contract/test_tool_schemas.py` | **NEW** | Tool schema/annotation contract |
| `contract/test_resource_uris.py` | **NEW** | Resource URI templates |
| `strictdoc_pin/test_strictdoc_internals.py` | **NEW** | Pin-validation lane |

### Configuration & docs

| File | Status | Responsibility |
|---|---|---|
| `pyproject.toml` | **MODIFY** | Add `strictdoc==0.20.0` to PROJECT-DEPS sentinels |
| `docs/configuration.md` | **MODIFY** | Document new env vars |
| `docs/tools/index.md` | **MODIFY** | Tool list |
| `docs/deployment/multi-project.md` | **NEW** | Multi-project deployment pattern |
| `README.md` | **MODIFY** | Quick-start substrate section |

---

## PR sequencing

For reviewability, group commits into PR-sized milestones (each PR closes one tracking sub-issue under the Phase 1 epic):

- **PR1** — Tasks 1–4 (foundation: deps, types, grammar, fixtures, SpecStore)
- **PR2** — Tasks 5–7 (StrictDocBackend, GrammarResolver, git_strategy adaptation)
- **PR3** — Tasks 8–9 (config + lifespan + Substrate composition)
- **PR4** — Tasks 10–13 (read tools)
- **PR5** — Tasks 14–15 (lifecycle + validation tools)
- **PR6** — Tasks 16–17 (export tools + resources)
- **PR7** — Tasks 18–20 (server integration + integration tests + docs)

≤10 sub-issues per epic per CLAUDE.md cap.

---

## Task 1: Foundation — dependency, types, default grammar, base test fixtures

**Files:**
- Modify: `pyproject.toml`
- Create: `src/reqeng_mcp/types.py`
- Create: `src/reqeng_mcp/grammars/__init__.py`
- Create: `src/reqeng_mcp/grammars/default.sgra`
- Create: `tests/fixtures/grammars/default.sgra` (copy of bundled)
- Create: `tests/unit/test_types.py`

- [ ] **Step 1: Add strictdoc to dependencies**

In `pyproject.toml`, between the `PROJECT-DEPS-START` and `PROJECT-DEPS-END` sentinels:

```toml
dependencies = [
    "fastmcp-pvl-core>=1.2.0,<2",
    "typer>=0.12",
    # PROJECT-DEPS-START — add domain dependencies below; kept across copier update
    "strictdoc==0.20.0",
    # PROJECT-DEPS-END
]
```

Then sync the lockfile:

```bash
uv lock
uv sync
```

- [ ] **Step 2: Verify strictdoc is importable**

```bash
uv run python -c "from strictdoc.backend.sdoc.reader import SDReader; print('ok')"
```

Expected: `ok`. If import fails, the pin is wrong or strictdoc internals moved — investigate before proceeding.

- [ ] **Step 3: Write the failing tests for types**

Create `tests/unit/test_types.py`:

```python
"""Tests for substrate-internal dataclass shapes."""
from __future__ import annotations

from pathlib import Path

import pytest

from reqeng_mcp.types import (
    CommitDiff,
    Document,
    Grammar,
    HistoryEntry,
    Node,
    NodeRef,
    Relation,
    ValidationFinding,
)


def test_node_ref_construction() -> None:
    ref = NodeRef(project_id="calc", uid="REQ-001")
    assert ref.project_id == "calc"
    assert ref.uid == "REQ-001"


def test_node_required_fields() -> None:
    node = Node(
        uid="REQ-001",
        mid="abc123",
        node_type="REQUIREMENT",
        fields={"TITLE": "Division by zero"},
        document="calculator.sdoc",
    )
    assert node.uid == "REQ-001"
    assert node.mid == "abc123"
    assert node.node_type == "REQUIREMENT"
    assert node.fields["TITLE"] == "Division by zero"
    assert node.document == "calculator.sdoc"
    assert node.relations == []


def test_relation_with_role() -> None:
    rel = Relation(
        source_uid="REQ-002",
        target="REQ-001",
        relation_type="Parent",
        role="Refines",
    )
    assert rel.relation_type == "Parent"
    assert rel.role == "Refines"


def test_relation_without_role() -> None:
    rel = Relation(source_uid="REQ-002", target="REQ-001", relation_type="Parent")
    assert rel.role is None


def test_grammar_listing() -> None:
    grammar = Grammar(
        source_path=Path("/tmp/grammar.sgra"),
        node_types=["SECTION", "TEXT", "REQUIREMENT"],
        roles_by_relation={"Parent": [None]},
    )
    assert "REQUIREMENT" in grammar.node_types
    assert grammar.roles_by_relation["Parent"] == [None]


def test_validation_finding_severity() -> None:
    f = ValidationFinding(
        severity="error",
        message="UID collision",
        location="calculator.sdoc:42",
    )
    assert f.severity == "error"


def test_history_entry_fields() -> None:
    entry = HistoryEntry(
        sha="abc1234567",
        short_sha="abc1234",
        timestamp="2026-05-02T10:00:00Z",
        author="local",
        message="add divisor invariant",
        paths_changed=["spec/calculator.sdoc"],
    )
    assert entry.short_sha == "abc1234"


def test_commit_diff_fields() -> None:
    diff = CommitDiff(
        sha="abc1234567",
        short_sha="abc1234",
        timestamp="2026-05-02T10:00:00Z",
        message="add divisor invariant",
        diff="--- a\n+++ b\n@@\n-foo\n+bar\n",
    )
    assert diff.diff.startswith("--- a")
```

- [ ] **Step 4: Run test, verify it fails**

```bash
uv run pytest tests/unit/test_types.py -v
```

Expected: ImportError on `reqeng_mcp.types`.

- [ ] **Step 5: Implement `src/reqeng_mcp/types.py`**

```python
"""Substrate-internal dataclasses.

These are the *our-shape* types exposed by `StrictDocBackend` and consumed
by tools/resources. They translate at the StrictDoc boundary so churn in
StrictDoc internals stays contained to `strictdoc_backend.py` (spec §5.1).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal


@dataclass(frozen=True)
class NodeRef:
    """A project-qualified node reference."""

    project_id: str
    uid: str


@dataclass
class Relation:
    """A typed relation from one node to another (or to a file path)."""

    source_uid: str
    target: str  # UID for Parent; path for File
    relation_type: Literal["Parent", "Child", "File"]
    role: str | None = None


@dataclass
class Node:
    """A single node parsed from a .sdoc document."""

    uid: str
    mid: str
    node_type: str
    fields: dict[str, str]
    document: str
    relations: list[Relation] = field(default_factory=list)


@dataclass
class Document:
    """A parsed .sdoc document."""

    path: Path
    title: str
    nodes: list[Node]


@dataclass
class Grammar:
    """The effective grammar for a project."""

    source_path: Path
    node_types: list[str]
    roles_by_relation: dict[str, list[str | None]]


@dataclass
class ValidationFinding:
    """A single validation issue surfaced by StrictDoc or substrate invariants."""

    severity: Literal["error", "warning", "info"]
    message: str
    location: str  # "<doc>:<line>" or "<doc>:<uid>" or "<doc>"


@dataclass
class HistoryEntry:
    """A git log entry scoped to a node's source file (spec §6.2 get_node_history)."""

    sha: str
    short_sha: str
    timestamp: str
    author: str
    message: str
    paths_changed: list[str]


@dataclass
class CommitDiff:
    """A per-commit diff (spec §6.2 get_node_diff with per_commit=True)."""

    sha: str
    short_sha: str
    timestamp: str
    message: str
    diff: str
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_types.py -v
```

Expected: all 8 tests pass.

- [ ] **Step 7: Create the bundled default grammar**

Create `src/reqeng_mcp/grammars/__init__.py` (empty file).

Create `src/reqeng_mcp/grammars/default.sgra` with the StrictDoc-L2-dogfood mirror per spec §4.2:

```text
[GRAMMAR]
ELEMENTS:
- TAG: SECTION
  PROPERTIES:
    IS_COMPOSITE: True
    VIEW_STYLE: Narrative
  FIELDS:
  - TITLE: MID
    TYPE: String
    REQUIRED: False
  - TITLE: UID
    TYPE: String
    REQUIRED: False
  - TITLE: TITLE
    TYPE: String
    REQUIRED: True

- TAG: TEXT
  FIELDS:
  - TITLE: MID
    TYPE: String
    REQUIRED: True
  - TITLE: UID
    TYPE: String
    REQUIRED: False
  - TITLE: STATEMENT
    TYPE: String
    REQUIRED: False

- TAG: REQUIREMENT
  PROPERTIES:
    VIEW_STYLE: Table
  FIELDS:
  - TITLE: MID
    TYPE: String
    REQUIRED: False
  - TITLE: UID
    TYPE: String
    REQUIRED: False
  - TITLE: STATUS
    TYPE: String
    REQUIRED: False
  - TITLE: TITLE
    TYPE: String
    REQUIRED: False
  - TITLE: STATEMENT
    TYPE: String
    REQUIRED: False
  - TITLE: RATIONALE
    TYPE: String
    REQUIRED: False
  - TITLE: COMMENT
    TYPE: String
    REQUIRED: False
  RELATIONS:
  - TYPE: Parent
  - TYPE: File
```

- [ ] **Step 8: Add the package-data wiring so the .sgra ships in the wheel**

In `pyproject.toml`, ensure the grammars directory is included:

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/reqeng_mcp"]

[tool.hatch.build.targets.wheel.force-include]
"src/reqeng_mcp/grammars/default.sgra" = "reqeng_mcp/grammars/default.sgra"
```

(Verify the existing `pyproject.toml` doesn't already cover this via wildcard; if it does, this step is a no-op.)

- [ ] **Step 9: Pin a copy in test fixtures (drift detection)**

```bash
cp src/reqeng_mcp/grammars/default.sgra tests/fixtures/grammars/default.sgra
```

A later test (Task 11) asserts the bundled and fixture copies match — drift triggers a deliberate pin update.

- [ ] **Step 10: Commit**

```bash
git add pyproject.toml uv.lock src/reqeng_mcp/types.py src/reqeng_mcp/grammars/ tests/fixtures/grammars/default.sgra tests/unit/test_types.py
git commit -m "feat(types): substrate dataclasses + bundled default grammar

- pin strictdoc==0.20.0 (exact pin per design spec §5.3)
- add Node/Relation/Document/Grammar/ValidationFinding/HistoryEntry/
  CommitDiff dataclasses in types.py
- ship default.sgra (StrictDoc L2 dogfood mirror, spec §4.2) inside
  the wheel and as a test fixture for drift detection

Refs design spec docs/specs/2026-05-02-reqeng-mcp-design.md §4, §5"
```

---

## Task 2: SpecStore — multi-project file-backed store

**Files:**
- Create: `src/reqeng_mcp/spec_store.py`
- Create: `tests/unit/test_specstore.py`
- Create: `tests/fixtures/projects/minimal/strictdoc_config.py`
- Create: `tests/fixtures/projects/minimal/spec/calculator.sdoc`
- Modify: `tests/conftest.py`

- [ ] **Step 1: Create the minimal fixture project**

Create `tests/fixtures/projects/minimal/strictdoc_config.py`:

```python
"""StrictDoc Python config for the minimal test fixture (spec §4.6).

Post-2025-Q4 migration uses Python config; TOML is deprecated.
"""
# Minimal config — substrate auto-imports default.sgra at load time.
```

Create `tests/fixtures/projects/minimal/spec/calculator.sdoc`:

```text
[DOCUMENT]
TITLE: Calculator Spec

[SECTION]
TITLE: Division semantics

[REQUIREMENT]
UID: REQ-DIV-001
TITLE: Division by zero raises
STATEMENT: >>>
When the divisor is zero, the operation MUST raise DivisionByZero.
<<<
RATIONALE: >>>
Sentinel return values silently propagate corrupt state downstream.
<<<

[REQUIREMENT]
UID: REQ-DIV-002
TITLE: Negative-zero handling matches IEEE 754
STATEMENT: >>>
Operations on negative zero MUST follow IEEE 754 semantics.
<<<
RELATIONS:
- TYPE: Parent
  VALUE: REQ-DIV-001

[/SECTION]
```

(Note: the document doesn't yet `IMPORT_FROM_FILE` a grammar — substrate's resolver injects the bundled default at load time; verified in Task 6.)

- [ ] **Step 2: Add fixtures to conftest.py**

Modify `tests/conftest.py` (existing file, append to it):

```python
"""Shared test fixtures."""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

# Existing fixtures preserved above this line.

FIXTURES_ROOT = Path(__file__).parent / "fixtures"


@pytest.fixture
def tmp_spec_root(tmp_path: Path) -> Path:
    """An empty <spec_root> directory."""
    root = tmp_path / "spec_root"
    root.mkdir()
    return root


@pytest.fixture
def minimal_project(tmp_spec_root: Path) -> Path:
    """A spec_root containing one project copied from the minimal fixture."""
    src = FIXTURES_ROOT / "projects" / "minimal"
    dst = tmp_spec_root / "minimal"
    shutil.copytree(src, dst)
    return tmp_spec_root  # caller uses tmp_spec_root + "minimal"
```

- [ ] **Step 3: Write the failing SpecStore tests**

Create `tests/unit/test_specstore.py`:

```python
"""Tests for FileSpecStore."""
from __future__ import annotations

from pathlib import Path

import pytest

from reqeng_mcp.spec_store import FileSpecStore, ProjectNotFoundError


def test_list_projects_empty(tmp_spec_root: Path) -> None:
    store = FileSpecStore(root=tmp_spec_root)
    assert store.list_projects() == []


def test_list_projects_finds_subdirs(minimal_project: Path) -> None:
    store = FileSpecStore(root=minimal_project)
    assert store.list_projects() == ["minimal"]


def test_list_projects_skips_archived(minimal_project: Path) -> None:
    (minimal_project / "archived" / "old-project").mkdir(parents=True)
    (minimal_project / "archived" / "old-project" / "spec").mkdir()
    store = FileSpecStore(root=minimal_project)
    # archived/ is not a project; it's a sibling subtree
    assert "old-project" not in store.list_projects()
    assert store.list_projects() == ["minimal"]


def test_list_projects_skips_dotdirs(minimal_project: Path) -> None:
    (minimal_project / ".hidden").mkdir()
    store = FileSpecStore(root=minimal_project)
    assert ".hidden" not in store.list_projects()


def test_get_project_path(minimal_project: Path) -> None:
    store = FileSpecStore(root=minimal_project)
    p = store.get_project_path("minimal")
    assert p == minimal_project / "minimal"
    assert p.is_dir()


def test_get_project_path_unknown_raises(minimal_project: Path) -> None:
    store = FileSpecStore(root=minimal_project)
    with pytest.raises(ProjectNotFoundError) as exc:
        store.get_project_path("does-not-exist")
    assert "does-not-exist" in str(exc.value)
    assert "minimal" in str(exc.value)  # message names available projects


def test_resolve_default_when_unset(minimal_project: Path) -> None:
    store = FileSpecStore(root=minimal_project, default_project=None)
    assert store.resolve_project_id(None) is None


def test_resolve_default_when_set(minimal_project: Path) -> None:
    store = FileSpecStore(root=minimal_project, default_project="minimal")
    assert store.resolve_project_id(None) == "minimal"


def test_resolve_explicit_overrides_default(minimal_project: Path) -> None:
    (minimal_project / "other").mkdir()
    (minimal_project / "other" / "spec").mkdir()
    store = FileSpecStore(root=minimal_project, default_project="minimal")
    assert store.resolve_project_id("other") == "other"


def test_resolve_unknown_raises(minimal_project: Path) -> None:
    store = FileSpecStore(root=minimal_project)
    with pytest.raises(ProjectNotFoundError):
        store.resolve_project_id("nope")
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
uv run pytest tests/unit/test_specstore.py -v
```

Expected: ImportError on `reqeng_mcp.spec_store`.

- [ ] **Step 5: Implement `src/reqeng_mcp/spec_store.py`**

```python
"""FileSpecStore — multi-project file-backed store (spec §3.1).

Layout: <root>/<project_id>/{strictdoc_config.py, spec/*.sdoc, grammar.sgra?, ...}

Single-project mode (Mode S) sets `default_project` so tools can omit the
`project_id` argument; multi-project mode (Mode H) leaves it None and
requires explicit `project_id`.
"""
from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


class ProjectNotFoundError(Exception):
    """Raised when a requested project_id does not resolve to a subtree."""


class FileSpecStore:
    """Indexed-by-project store backed by a parent directory of project subtrees."""

    def __init__(self, root: Path, default_project: str | None = None) -> None:
        self._root = root
        self._default_project = default_project

    @property
    def root(self) -> Path:
        return self._root

    def list_projects(self) -> list[str]:
        """Enumerate project_ids by scanning <root>/ for direct subdirectories.

        Skips dot-prefixed dirs and the reserved `archived/` subtree.
        """
        if not self._root.is_dir():
            return []
        projects: list[str] = []
        for entry in sorted(self._root.iterdir()):
            if not entry.is_dir():
                continue
            if entry.name.startswith("."):
                continue
            if entry.name == "archived":
                continue
            projects.append(entry.name)
        return projects

    def get_project_path(self, project_id: str) -> Path:
        """Return the directory for *project_id*; raise if it doesn't exist."""
        p = self._root / project_id
        if not p.is_dir():
            available = ", ".join(self.list_projects()) or "<none>"
            raise ProjectNotFoundError(
                f"project {project_id!r} not found under {self._root}; "
                f"available: {available}"
            )
        return p

    def resolve_project_id(self, requested: str | None) -> str | None:
        """Resolve a tool-supplied project_id, falling back to the default pin."""
        if requested is not None:
            # Validate it exists; raise if not
            self.get_project_path(requested)
            return requested
        if self._default_project is not None:
            self.get_project_path(self._default_project)
            return self._default_project
        return None
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_specstore.py -v
```

Expected: all 10 tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/reqeng_mcp/spec_store.py tests/unit/test_specstore.py tests/fixtures/projects/minimal/ tests/conftest.py
git commit -m "feat(spec-store): FileSpecStore for multi-project layout

- list_projects, get_project_path, resolve_project_id
- skips archived/ and dot-prefixed dirs
- minimal fixture project for downstream tests
- ProjectNotFoundError names available projects in its message

Refs design spec §3.1, §6.7"
```

---

## Task 3: StrictDocBackend — read paths, traceability index, validation, grammar

**Files:**
- Create: `src/reqeng_mcp/strictdoc_backend.py`
- Create: `tests/unit/test_strictdoc_backend.py`

This task wraps StrictDoc's internal API per spec §5.2. The wrapper is the *only* place in the codebase that imports from `strictdoc.*`. All public methods take/return our-shape types from `types.py`.

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_strictdoc_backend.py`:

```python
"""Tests for StrictDocBackend wrapper (spec §5)."""
from __future__ import annotations

from pathlib import Path

import pytest

from reqeng_mcp.strictdoc_backend import StrictDocBackend
from reqeng_mcp.types import Document, Grammar, Node, Relation, ValidationFinding


@pytest.fixture
def backend(minimal_project: Path) -> StrictDocBackend:
    project_root = minimal_project / "minimal"
    return StrictDocBackend(project_root=project_root)


def test_read_document_returns_our_types(backend: StrictDocBackend) -> None:
    doc_path = backend.project_root / "spec" / "calculator.sdoc"
    doc = backend.read_document(doc_path)
    assert isinstance(doc, Document)
    assert doc.title == "Calculator Spec"
    uids = {n.uid for n in doc.nodes if n.uid}
    assert "REQ-DIV-001" in uids
    assert "REQ-DIV-002" in uids


def test_read_document_extracts_relations(backend: StrictDocBackend) -> None:
    doc_path = backend.project_root / "spec" / "calculator.sdoc"
    doc = backend.read_document(doc_path)
    req002 = next(n for n in doc.nodes if n.uid == "REQ-DIV-002")
    assert any(
        r.relation_type == "Parent" and r.target == "REQ-DIV-001"
        for r in req002.relations
    )


def test_get_index_resolves_uids(backend: StrictDocBackend) -> None:
    index = backend.get_index()
    assert index.has_uid("REQ-DIV-001")
    assert index.has_uid("REQ-DIV-002")
    assert not index.has_uid("REQ-DOES-NOT-EXIST")


def test_get_index_dependents(backend: StrictDocBackend) -> None:
    index = backend.get_index()
    dependents = index.dependents_of("REQ-DIV-001")
    assert any(n.uid == "REQ-DIV-002" for n in dependents)


def test_get_index_caches_until_invalidated(backend: StrictDocBackend) -> None:
    index_a = backend.get_index()
    index_b = backend.get_index()
    assert index_a is index_b
    backend.invalidate_index()
    index_c = backend.get_index()
    assert index_c is not index_a


def test_validate_clean_fixture_returns_no_errors(backend: StrictDocBackend) -> None:
    findings = backend.validate()
    errors = [f for f in findings if f.severity == "error"]
    assert errors == []


def test_get_effective_grammar_returns_default(backend: StrictDocBackend) -> None:
    grammar = backend.get_effective_grammar()
    assert isinstance(grammar, Grammar)
    assert "REQUIREMENT" in grammar.node_types
    assert "SECTION" in grammar.node_types
    assert "TEXT" in grammar.node_types
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/unit/test_strictdoc_backend.py -v
```

Expected: ImportError on `reqeng_mcp.strictdoc_backend`.

- [ ] **Step 3: Implement `src/reqeng_mcp/strictdoc_backend.py`**

```python
"""StrictDocBackend — single-boundary wrapper over StrictDoc internals.

This is the ONLY module in reqeng-mcp that imports from `strictdoc.*`.
All other code consumes our-shape types defined in `types.py`. When
StrictDoc internals churn (no documented public API per upstream),
churn is contained here. See design spec §5.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

# StrictDoc internal touch points — all imports localised to this module.
from strictdoc.backend.sdoc.reader import SDReader
from strictdoc.core.project_config import ProjectConfig as StrictDocProjectConfig
from strictdoc.core.traceability_index_builder import TraceabilityIndexBuilder
from strictdoc.helpers.parallelizer import Parallelizer

from reqeng_mcp.types import (
    Document,
    Grammar,
    Node,
    Relation,
    ValidationFinding,
)

logger = logging.getLogger(__name__)


@dataclass
class _IndexView:
    """Our-shape view over StrictDoc's TraceabilityIndex (spec §5.4 cache target)."""

    _strictdoc_index: object  # opaque to callers; type omitted to avoid cross-coupling
    _nodes_by_uid: dict[str, Node]
    _inbound_by_uid: dict[str, list[Node]]
    _outbound_by_uid: dict[str, list[Node]]

    def has_uid(self, uid: str) -> bool:
        return uid in self._nodes_by_uid

    def get_node(self, uid: str) -> Node | None:
        return self._nodes_by_uid.get(uid)

    def all_nodes(self) -> list[Node]:
        return list(self._nodes_by_uid.values())

    def dependents_of(self, uid: str) -> list[Node]:
        return list(self._inbound_by_uid.get(uid, []))

    def dependencies_of(self, uid: str) -> list[Node]:
        return list(self._outbound_by_uid.get(uid, []))


class StrictDocBackend:
    """Per-project wrapper. One instance per project; caches the index lazily."""

    def __init__(
        self,
        project_root: Path,
        parallelizer: Parallelizer | None = None,
    ) -> None:
        self.project_root = project_root
        self._parallelizer = parallelizer or Parallelizer.create(parallelize=False)
        self._strictdoc_config: StrictDocProjectConfig | None = None
        self._index: _IndexView | None = None

    # ------------------------------------------------------------------
    # Public read API
    # ------------------------------------------------------------------

    def read_document(self, path: Path) -> Document:
        """Parse a single .sdoc file into our Document type."""
        config = self._get_strictdoc_config()
        reader = SDReader()
        sdoc_doc = reader.read_from_file(str(path), config)
        return self._adapt_document(sdoc_doc, path)

    def get_index(self) -> _IndexView:
        """Lazy-build the traceability index; cache until invalidated."""
        if self._index is None:
            self._index = self._build_index()
        return self._index

    def invalidate_index(self) -> None:
        """Drop the cached index; next get_index() rebuilds."""
        self._index = None

    def validate(self) -> list[ValidationFinding]:
        """Run StrictDoc's native validation; return our-typed findings."""
        try:
            self._build_index()  # validation runs transitively
            return []
        except Exception as exc:
            logger.warning("validation_failed message=%s", exc)
            return [
                ValidationFinding(
                    severity="error",
                    message=str(exc),
                    location=str(self.project_root),
                )
            ]

    def get_effective_grammar(self) -> Grammar:
        """Return the project's effective grammar as our-shape Grammar."""
        # The grammar is encoded inside the document or imported via .sgra.
        # We surface the structurally observable parts: node types and
        # roles per relation type.
        config = self._get_strictdoc_config()
        # Locate any document to read its declared grammar; if the project
        # has no documents yet, fall back to the inferred default-grammar
        # surface (SECTION, TEXT, REQUIREMENT).
        sdocs = list((self.project_root / "spec").glob("*.sdoc"))
        if not sdocs:
            return Grammar(
                source_path=self.project_root / "grammar.sgra",
                node_types=["SECTION", "TEXT", "REQUIREMENT"],
                roles_by_relation={"Parent": [None], "File": [None]},
            )
        reader = SDReader()
        sdoc_doc = reader.read_from_file(str(sdocs[0]), config)
        node_types: list[str] = []
        roles_by_relation: dict[str, list[str | None]] = {}
        if hasattr(sdoc_doc, "grammar") and sdoc_doc.grammar is not None:
            for element in getattr(sdoc_doc.grammar, "elements", []):
                tag = getattr(element, "tag", None)
                if tag and tag not in node_types:
                    node_types.append(tag)
                for relation in getattr(element, "relations", []):
                    rel_type = getattr(relation, "relation_type", None)
                    role = getattr(relation, "relation_role", None)
                    if rel_type:
                        roles_by_relation.setdefault(rel_type, []).append(role)
        # Fall back to defaults when the grammar block is absent
        if not node_types:
            node_types = ["SECTION", "TEXT", "REQUIREMENT"]
        if not roles_by_relation:
            roles_by_relation = {"Parent": [None], "File": [None]}
        return Grammar(
            source_path=sdocs[0],
            node_types=node_types,
            roles_by_relation=roles_by_relation,
        )

    # ------------------------------------------------------------------
    # Internal: index build + adaptation
    # ------------------------------------------------------------------

    def _get_strictdoc_config(self) -> StrictDocProjectConfig:
        if self._strictdoc_config is None:
            # StrictDoc's ProjectConfig is loaded from strictdoc_config.py
            # (or strictdoc.toml as legacy fallback) at the project root.
            # Falls back to defaults if neither exists.
            self._strictdoc_config = StrictDocProjectConfig.load_from_path_or_get_default(
                str(self.project_root)
            )
        return self._strictdoc_config

    def _build_index(self) -> _IndexView:
        config = self._get_strictdoc_config()
        sd_index = TraceabilityIndexBuilder.create(
            project_config=config,
            parallelizer=self._parallelizer,
        )
        nodes_by_uid: dict[str, Node] = {}
        inbound: dict[str, list[Node]] = {}
        outbound: dict[str, list[Node]] = {}

        # Walk all parsed documents through the index
        for sdoc_doc in getattr(sd_index, "document_tree", []):
            doc_path = Path(getattr(sdoc_doc, "meta", {}).get("file_path", "<unknown>"))
            for sdoc_node in self._walk_document_nodes(sdoc_doc):
                node = self._adapt_node(sdoc_node, doc_path.name)
                if node.uid:
                    nodes_by_uid[node.uid] = node

        # Pre-compute inbound/outbound graphs from Parent relations
        for node in nodes_by_uid.values():
            for rel in node.relations:
                if rel.relation_type == "Parent":
                    outbound.setdefault(node.uid, []).append(
                        nodes_by_uid.get(rel.target, node)
                    )
                    inbound.setdefault(rel.target, []).append(node)
        return _IndexView(
            _strictdoc_index=sd_index,
            _nodes_by_uid=nodes_by_uid,
            _inbound_by_uid=inbound,
            _outbound_by_uid=outbound,
        )

    def _walk_document_nodes(self, sdoc_doc: object) -> list[object]:
        """Flatten a StrictDoc document's section tree into a list of leaf nodes."""
        out: list[object] = []
        stack: list[object] = list(getattr(sdoc_doc, "section_contents", []) or [])
        while stack:
            item = stack.pop(0)
            if hasattr(item, "section_contents") and item.section_contents:
                stack.extend(item.section_contents)
            else:
                out.append(item)
        return out

    def _adapt_document(self, sdoc_doc: object, path: Path) -> Document:
        title = getattr(sdoc_doc, "title", path.stem)
        nodes = [
            self._adapt_node(sdoc_node, path.name)
            for sdoc_node in self._walk_document_nodes(sdoc_doc)
        ]
        return Document(path=path, title=title, nodes=nodes)

    def _adapt_node(self, sdoc_node: object, document: str) -> Node:
        uid = getattr(sdoc_node, "reserved_uid", "") or ""
        mid = getattr(sdoc_node, "reserved_mid", "") or ""
        node_type = type(sdoc_node).__name__.upper().replace("SDOC", "")
        # Walk the node's attribute fields
        fields: dict[str, str] = {}
        for fname, attr_name in (
            ("TITLE", "title"),
            ("STATEMENT", "reserved_statement"),
            ("RATIONALE", "rationale"),
            ("STATUS", "reserved_status"),
            ("COMMENT", "comments"),
        ):
            value = getattr(sdoc_node, attr_name, None)
            if value:
                fields[fname] = str(value)
        # Walk relations
        relations: list[Relation] = []
        for sdoc_rel in getattr(sdoc_node, "relations", []) or []:
            relations.append(
                Relation(
                    source_uid=uid,
                    target=getattr(sdoc_rel, "uid", "") or getattr(sdoc_rel, "value", ""),
                    relation_type=getattr(sdoc_rel, "relation_type", "Parent"),
                    role=getattr(sdoc_rel, "relation_role", None),
                )
            )
        return Node(
            uid=uid,
            mid=mid,
            node_type=node_type or "UNKNOWN",
            fields=fields,
            document=document,
            relations=relations,
        )
```

> **Implementation note:** the StrictDoc internals (`reserved_uid`, `section_contents`, `document_tree`, etc.) reflect StrictDoc 0.20.0's structure as of design time; if 0.20.x releases change attribute names, the wrapper is the only place to adjust. The defensive `getattr(..., "", None)` patterns absorb minor API drift without breaking callers.

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_strictdoc_backend.py -v
```

Expected: all 7 tests pass. If any fail because StrictDoc internals have shifted, adjust `_adapt_node` / `_walk_document_nodes` / `_build_index` accordingly — these are the parts isolated to this module precisely so changes stay contained.

- [ ] **Step 5: Commit**

```bash
git add src/reqeng_mcp/strictdoc_backend.py tests/unit/test_strictdoc_backend.py
git commit -m "feat(strictdoc-backend): wrapper over StrictDoc internals (read paths)

- single-boundary import from strictdoc.* (spec §5.1)
- read_document, get_index (cached), invalidate_index, validate,
  get_effective_grammar
- _IndexView our-shape view over StrictDoc's TraceabilityIndex
- adapter functions translate SDoc nodes -> our Node/Relation/Document

Refs design spec §5"
```

---

## Task 4: StrictDocBackend — exports

**Files:**
- Modify: `src/reqeng_mcp/strictdoc_backend.py`
- Modify: `tests/unit/test_strictdoc_backend.py`

Phase 1 includes all four export tools (HTML, ReqIF, Excel, Markdown). The wrapper exposes one method per export format; tools call them in Task 16 and route the produced files through file-exchange.

- [ ] **Step 1: Write failing tests for export methods**

Append to `tests/unit/test_strictdoc_backend.py`:

```python
def test_export_html_produces_files(
    backend: StrictDocBackend, tmp_path: Path
) -> None:
    out_dir = tmp_path / "html_out"
    out_dir.mkdir()
    result_path = backend.export_html(out_dir)
    assert result_path.is_dir() or result_path.is_file()
    assert any(out_dir.rglob("*.html"))


def test_export_reqif_produces_file(
    backend: StrictDocBackend, tmp_path: Path
) -> None:
    out_dir = tmp_path / "reqif_out"
    out_dir.mkdir()
    result_path = backend.export_reqif(out_dir)
    assert result_path.exists()
    assert result_path.suffix in (".reqif", ".reqifz", ".xml")


def test_export_excel_produces_file(
    backend: StrictDocBackend, tmp_path: Path
) -> None:
    out_dir = tmp_path / "excel_out"
    out_dir.mkdir()
    result_path = backend.export_excel(out_dir)
    assert result_path.exists()
    assert result_path.suffix in (".xlsx", ".xls")


def test_export_markdown_produces_files(
    backend: StrictDocBackend, tmp_path: Path
) -> None:
    out_dir = tmp_path / "md_out"
    out_dir.mkdir()
    result_path = backend.export_markdown(out_dir)
    assert result_path.is_dir() or result_path.is_file()
    assert any(out_dir.rglob("*.md"))
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
uv run pytest tests/unit/test_strictdoc_backend.py -k export -v
```

Expected: AttributeError — methods don't exist.

- [ ] **Step 3: Implement export methods**

Append to `src/reqeng_mcp/strictdoc_backend.py`:

```python
    # ------------------------------------------------------------------
    # Public export API
    # ------------------------------------------------------------------

    def export_html(self, output_dir: Path) -> Path:
        """Generate StrictDoc HTML export. Returns the output directory."""
        from strictdoc.export.html.html_generator import HTMLGenerator
        config = self._get_strictdoc_config()
        # Force HTML export to write under output_dir
        config.export_output_dir = str(output_dir)
        index = self._build_index()._strictdoc_index
        html_gen = HTMLGenerator(project_config=config)
        html_gen.export_complete_tree(traceability_index=index, parallelizer=self._parallelizer)
        return output_dir

    def export_reqif(self, output_dir: Path) -> Path:
        """Generate StrictDoc ReqIF export. Returns the produced file path."""
        from strictdoc.backend.reqif.reqif_export import ReqIFExport
        config = self._get_strictdoc_config()
        config.export_output_dir = str(output_dir)
        index = self._build_index()._strictdoc_index
        ReqIFExport(project_config=config).export(traceability_index=index)
        # Find the produced file (StrictDoc's filename varies by version; pick latest .reqif)
        produced = sorted(output_dir.rglob("*.reqif")) + sorted(output_dir.rglob("*.reqifz"))
        if not produced:
            raise RuntimeError(f"ReqIF export produced no output under {output_dir}")
        return produced[-1]

    def export_excel(self, output_dir: Path) -> Path:
        """Generate StrictDoc Excel export. Returns the produced file path."""
        from strictdoc.export.excel.excel_generator import ExcelGenerator
        config = self._get_strictdoc_config()
        config.export_output_dir = str(output_dir)
        index = self._build_index()._strictdoc_index
        ExcelGenerator(project_config=config).export_tree(
            traceability_index=index, parallelizer=self._parallelizer
        )
        produced = sorted(output_dir.rglob("*.xlsx"))
        if not produced:
            raise RuntimeError(f"Excel export produced no output under {output_dir}")
        return produced[-1]

    def export_markdown(self, output_dir: Path) -> Path:
        """Generate StrictDoc Markdown export. Returns the output directory."""
        # StrictDoc's MD export class name varies; locate dynamically.
        try:
            from strictdoc.export.html2pdf.html2pdf_generator import HTML2PDFGenerator  # noqa: F401
        except ImportError:
            pass
        from strictdoc.export.html.html_generator import HTMLGenerator
        config = self._get_strictdoc_config()
        config.export_output_dir = str(output_dir)
        config.export_format = "markdown"
        index = self._build_index()._strictdoc_index
        HTMLGenerator(project_config=config).export_complete_tree(
            traceability_index=index, parallelizer=self._parallelizer
        )
        return output_dir
```

> **Implementation note:** export class names and method signatures vary across StrictDoc minor versions. If a method doesn't exist in the pinned 0.20.0, find the equivalent — `from strictdoc.core.actions.export_action import ExportAction` is the higher-level umbrella that may be cleaner. Adjust the wrapper; do NOT propagate the change to tools or callers.

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_strictdoc_backend.py -k export -v
```

Expected: all 4 export tests pass. If they fail because StrictDoc 0.20.0's export classes have different names, fix the wrapper imports — pinning to 0.20.0 means the surface is stable for the duration of this PR.

- [ ] **Step 5: Commit**

```bash
git add src/reqeng_mcp/strictdoc_backend.py tests/unit/test_strictdoc_backend.py
git commit -m "feat(strictdoc-backend): HTML/ReqIF/Excel/Markdown export methods

- one method per export format, returning Path to produced file/dir
- callers route the result through the existing file-exchange middleware
- export-class imports localised inside methods (lazy) so import-time
  cost is zero for projects that never export

Refs design spec §6.5"
```

---

## Task 5: GrammarResolver — four-step resolution

**Files:**
- Create: `src/reqeng_mcp/grammar_resolver.py`
- Create: `tests/unit/test_grammar_resolution.py`

Implements the resolution order from spec §4.3: inline → project `.sgra` → env-default → bundled.

- [ ] **Step 1: Write failing tests**

Create `tests/unit/test_grammar_resolution.py`:

```python
"""Tests for GrammarResolver four-step resolution (spec §4.3)."""
from __future__ import annotations

from pathlib import Path

import pytest

from reqeng_mcp.grammar_resolver import GrammarResolver, GrammarSource


def test_resolves_to_bundled_when_nothing_overrides(
    tmp_path: Path,
) -> None:
    resolver = GrammarResolver(env_default_path=None)
    project_root = tmp_path / "minimal"
    project_root.mkdir()
    (project_root / "spec").mkdir()
    source = resolver.resolve(project_root)
    assert source.kind == "bundled"
    assert source.path.name == "default.sgra"
    assert source.path.read_text().lstrip().startswith("[GRAMMAR]")


def test_env_default_overrides_bundled(tmp_path: Path) -> None:
    custom = tmp_path / "custom.sgra"
    custom.write_text("[GRAMMAR]\nELEMENTS: []\n")
    resolver = GrammarResolver(env_default_path=custom)
    project_root = tmp_path / "minimal"
    project_root.mkdir()
    (project_root / "spec").mkdir()
    source = resolver.resolve(project_root)
    assert source.kind == "env_default"
    assert source.path == custom


def test_project_grammar_overrides_env_default(tmp_path: Path) -> None:
    custom = tmp_path / "custom.sgra"
    custom.write_text("[GRAMMAR]\nELEMENTS: []\n")
    resolver = GrammarResolver(env_default_path=custom)
    project_root = tmp_path / "minimal"
    project_root.mkdir()
    (project_root / "spec").mkdir()
    project_grammar = project_root / "grammar.sgra"
    project_grammar.write_text("[GRAMMAR]\nELEMENTS: []\n")
    source = resolver.resolve(project_root)
    assert source.kind == "project"
    assert source.path == project_grammar


def test_inline_grammar_in_document_takes_precedence(
    tmp_path: Path,
) -> None:
    resolver = GrammarResolver(env_default_path=None)
    project_root = tmp_path / "minimal"
    project_root.mkdir()
    spec_dir = project_root / "spec"
    spec_dir.mkdir()
    doc = spec_dir / "with_inline_grammar.sdoc"
    doc.write_text(
        "[DOCUMENT]\nTITLE: X\n\n[GRAMMAR]\nELEMENTS:\n- TAG: REQUIREMENT\n  FIELDS:\n  - TITLE: STATEMENT\n    TYPE: String\n    REQUIRED: True\n"
    )
    source = resolver.resolve(project_root)
    assert source.kind == "inline"
    # Inline grammar's source path is the document itself
    assert source.path == doc


def test_resolve_creates_project_sgra_symlink_when_env_default(
    tmp_path: Path,
) -> None:
    """When env-default is in effect and project has no grammar.sgra, the resolver
    materialises one (copy or symlink) so StrictDoc's IMPORT_FROM_FILE works.

    This is the behaviour the substrate needs for projects to pick up a
    docker-mounted env-default automatically.
    """
    custom = tmp_path / "custom.sgra"
    custom.write_text("[GRAMMAR]\nELEMENTS: []\n")
    resolver = GrammarResolver(env_default_path=custom, materialise_project_sgra=True)
    project_root = tmp_path / "minimal"
    project_root.mkdir()
    (project_root / "spec").mkdir()
    resolver.resolve(project_root)
    materialised = project_root / "grammar.sgra"
    assert materialised.exists()
    assert materialised.read_text() == custom.read_text()
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
uv run pytest tests/unit/test_grammar_resolution.py -v
```

Expected: ImportError on `reqeng_mcp.grammar_resolver`.

- [ ] **Step 3: Implement `src/reqeng_mcp/grammar_resolver.py`**

```python
"""Four-step grammar resolution (spec §4.3).

Resolution order:
1. Inline [GRAMMAR] block in a project document → use it.
2. <project_root>/grammar.sgra → use it.
3. REQENG_MCP_DEFAULT_GRAMMAR_PATH env var (passed in as env_default_path) → use it.
4. Bundled reqeng_mcp/grammars/default.sgra → use it.
"""
from __future__ import annotations

import logging
import shutil
from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path
from typing import Literal

logger = logging.getLogger(__name__)


GrammarKind = Literal["inline", "project", "env_default", "bundled"]


@dataclass(frozen=True)
class GrammarSource:
    """Where the project's effective grammar came from."""

    kind: GrammarKind
    path: Path


class GrammarResolver:
    """Resolve a project's effective grammar at load time."""

    def __init__(
        self,
        env_default_path: Path | None = None,
        materialise_project_sgra: bool = True,
    ) -> None:
        self._env_default = env_default_path
        self._materialise = materialise_project_sgra

    def resolve(self, project_root: Path) -> GrammarSource:
        # Step 1: inline grammar in any document
        spec_dir = project_root / "spec"
        if spec_dir.is_dir():
            for doc in sorted(spec_dir.glob("*.sdoc")):
                if "[GRAMMAR]" in doc.read_text():
                    return GrammarSource(kind="inline", path=doc)

        # Step 2: project-level .sgra
        project_sgra = project_root / "grammar.sgra"
        if project_sgra.is_file():
            return GrammarSource(kind="project", path=project_sgra)

        # Step 3: env-default
        if self._env_default is not None and self._env_default.is_file():
            if self._materialise:
                shutil.copy(self._env_default, project_sgra)
                logger.info(
                    "grammar_materialised src=%s dst=%s",
                    self._env_default,
                    project_sgra,
                )
            return GrammarSource(kind="env_default", path=self._env_default)

        # Step 4: bundled default
        bundled = self._bundled_path()
        if self._materialise and not project_sgra.is_file():
            shutil.copy(bundled, project_sgra)
            logger.info("grammar_materialised_default dst=%s", project_sgra)
        return GrammarSource(kind="bundled", path=bundled)

    def _bundled_path(self) -> Path:
        """Resolve the wheel-bundled default grammar via importlib.resources."""
        return Path(str(files("reqeng_mcp.grammars").joinpath("default.sgra")))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_grammar_resolution.py -v
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/reqeng_mcp/grammar_resolver.py tests/unit/test_grammar_resolution.py
git commit -m "feat(grammar-resolver): four-step resolution order

- inline -> project sgra -> env default -> bundled (spec §4.3)
- materialises grammar.sgra into project root when env-default or
  bundled wins, so StrictDoc's IMPORT_FROM_FILE picks it up
- importlib.resources locates the wheel-bundled default

Refs design spec §4.3"
```

---

## Task 6: git_strategy module — adapt from markdown-mcp

**Files:**
- Create: `src/reqeng_mcp/git_strategy.py`
- Create: `tests/unit/test_git_strategy_init.py`

Phase 1 only exercises **init/clone semantics** (per spec Phase 1 scope). The full write-callback / push-timer / pull-loop machinery is present but not wired to any tool until Phase 2.

- [ ] **Step 1: Copy markdown-mcp's git.py as a starting point**

```bash
cp /mnt/code/markdown-mcp/src/markdown_vault_mcp/git.py src/reqeng_mcp/git_strategy.py
```

- [ ] **Step 2: Adapt the import + identifier names**

Open `src/reqeng_mcp/git_strategy.py` and:

1. Replace `markdown_vault_mcp.exceptions` import with our local error class:

   ```python
   # OLD:
   from markdown_vault_mcp.exceptions import ConfigurationError
   # NEW:
   class ConfigurationError(Exception):
       """Raised on git-strategy misconfiguration."""
   ```

2. Replace `markdown_vault_mcp.types` import with our local types:

   ```python
   # OLD:
   from markdown_vault_mcp.types import CommitDiff, HistoryEntry
   # NEW:
   from reqeng_mcp.types import CommitDiff, HistoryEntry
   ```

3. Update env-var names from `MVMCP_*` to `REQENG_MCP_*` in the askpass script and DEFAULT_COMMIT_NAME / DEFAULT_COMMIT_EMAIL:

   ```python
   DEFAULT_COMMIT_NAME = "reqeng-mcp"
   DEFAULT_COMMIT_EMAIL = "noreply@reqeng-mcp"
   ```

4. Drop the `frontmatter` import + use — it's specific to markdown vaults; the conflict-saving path needs to be generalised. For Phase 1 the conflict path is unused (no writes). Leave the method bodies referencing `frontmatter` but mark them `pragma: no cover` and add a TODO referencing Phase 2 — the Phase 2 plan will replace `frontmatter`-based conflict semantics with a `.sdoc`-aware variant.

   Add at the top of `_write_conflict_files`:

   ```python
   def _write_conflict_files(self, ...):
       """Write conflict files... (Phase 2 TODO: replace frontmatter with .sdoc-aware metadata.)"""
       # In Phase 1 this path is unreachable: no writes, no rebases.
       # Phase 2 issue: <to-be-filed>
       ...  # body unchanged from markdown-mcp; covered later.
   ```

5. Update class docstring to reference reqeng-mcp + spec section.

- [ ] **Step 3: Write a minimal failing test**

Create `tests/unit/test_git_strategy_init.py`:

```python
"""Phase 1: only exercise init/managed-mode semantics of the git strategy."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from reqeng_mcp.git_strategy import ConfigurationError, GitWriteStrategy


def test_managed_clone_into_empty_dir_succeeds(tmp_path: Path) -> None:
    # Build a local "remote" repo to clone from
    remote = tmp_path / "remote.git"
    subprocess.run(["git", "init", "--bare", str(remote)], check=True)
    work = tmp_path / "remote_work"
    work.mkdir()
    subprocess.run(["git", "init", str(work)], check=True)
    (work / "README.md").write_text("hello\n")
    subprocess.run(["git", "-C", str(work), "add", "README.md"], check=True)
    subprocess.run(
        ["git", "-C", str(work), "-c", "user.name=t", "-c", "user.email=t@t",
         "commit", "-m", "init"],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(work), "remote", "add", "origin", str(remote)], check=True
    )
    subprocess.run(["git", "-C", str(work), "push", "origin", "HEAD:main"], check=True)

    target = tmp_path / "managed_clone"
    strategy = GitWriteStrategy(
        repo_url=str(remote),
        managed=True,
        enable_pull=False,
        enable_push=False,
        repo_path=target,
    )
    assert (target / ".git").is_dir()
    assert (target / "README.md").exists()


def test_managed_mismatched_origin_raises(tmp_path: Path) -> None:
    work = tmp_path / "existing"
    work.mkdir()
    subprocess.run(["git", "init", str(work)], check=True)
    subprocess.run(
        ["git", "-C", str(work), "remote", "add", "origin", "https://other.example/x.git"],
        check=True,
    )
    with pytest.raises(ConfigurationError, match="remote mismatch"):
        GitWriteStrategy(
            repo_url="https://expected.example/y.git",
            managed=True,
            enable_pull=False,
            enable_push=False,
            repo_path=work,
        )
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_git_strategy_init.py -v
```

Expected: both tests pass (the markdown-mcp logic is well-tested upstream; our adaptation should preserve init/managed semantics).

If `_normalize_remote` in the original logic is too lenient or the `ConfigurationError` message text differs, adjust the test's regex match — the spec only requires the error happens, not a specific phrasing.

- [ ] **Step 5: Run the test suite to ensure no other tests broke**

```bash
uv run pytest -x -q
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add src/reqeng_mcp/git_strategy.py tests/unit/test_git_strategy_init.py
git commit -m "feat(git-strategy): adapt markdown-mcp GitWriteStrategy

- copied from /mnt/code/markdown-mcp/src/markdown_vault_mcp/git.py
- replaced MVMCP_* env vars with REQENG_MCP_*
- replaced markdown_vault_mcp.{exceptions,types} imports with locals
- DEFAULT_COMMIT_NAME/EMAIL set to reqeng-mcp identity
- conflict-file path (frontmatter-based) deferred to Phase 2; the path
  is unreachable in Phase 1 (no writes)

Phase 1 only exercises init/managed-mode clone semantics; per-write
commit + idle push timer + pull loop tests come in Phase 2.

Refs design spec §3.1, §10.1"
```

---

## Task 7: Substrate composition root

**Files:**
- Create: `src/reqeng_mcp/substrate.py`
- Create: `tests/unit/test_substrate.py`

The `Substrate` is the composition root — a single object that the lifespan creates and that all tool dependencies route through. It owns the `SpecStore`, lazily creates `StrictDocBackend` instances per project, and holds the `GitWriteStrategy` factory for project lifecycle.

- [ ] **Step 1: Write failing tests**

Create `tests/unit/test_substrate.py`:

```python
"""Tests for the Substrate composition root."""
from __future__ import annotations

from pathlib import Path

import pytest

from reqeng_mcp.spec_store import FileSpecStore
from reqeng_mcp.strictdoc_backend import StrictDocBackend
from reqeng_mcp.substrate import Substrate


def test_substrate_lists_projects(minimal_project: Path) -> None:
    sub = Substrate(spec_root=minimal_project, default_project=None)
    assert sub.spec_store.list_projects() == ["minimal"]


def test_substrate_returns_backend_per_project(minimal_project: Path) -> None:
    sub = Substrate(spec_root=minimal_project, default_project=None)
    backend = sub.get_backend("minimal")
    assert isinstance(backend, StrictDocBackend)
    backend2 = sub.get_backend("minimal")
    assert backend is backend2  # cached


def test_substrate_separate_backend_per_project(minimal_project: Path) -> None:
    (minimal_project / "second").mkdir()
    (minimal_project / "second" / "spec").mkdir()
    sub = Substrate(spec_root=minimal_project, default_project=None)
    a = sub.get_backend("minimal")
    b = sub.get_backend("second")
    assert a is not b


def test_substrate_resolve_with_default(minimal_project: Path) -> None:
    sub = Substrate(spec_root=minimal_project, default_project="minimal")
    assert sub.resolve_project_id(None) == "minimal"
```

- [ ] **Step 2: Run tests, verify failure**

```bash
uv run pytest tests/unit/test_substrate.py -v
```

Expected: ImportError on `reqeng_mcp.substrate`.

- [ ] **Step 3: Implement `src/reqeng_mcp/substrate.py`**

```python
"""Substrate — composition root for reqeng-mcp's domain layer.

One Substrate per server process. Holds:
- A SpecStore (multi-project layout)
- An LRU cache of StrictDocBackend instances per project
- A GrammarResolver
- Configuration for git/autocommit/push behaviour (consumed in Phase 2)
"""
from __future__ import annotations

import logging
from pathlib import Path

from reqeng_mcp.grammar_resolver import GrammarResolver
from reqeng_mcp.spec_store import FileSpecStore
from reqeng_mcp.strictdoc_backend import StrictDocBackend

logger = logging.getLogger(__name__)


class Substrate:
    """Composition root accessed by tools and resources."""

    def __init__(
        self,
        spec_root: Path,
        default_project: str | None = None,
        default_grammar_path: Path | None = None,
        autocommit: bool = False,
        git_push_delay_s: float = 0.0,
    ) -> None:
        self.spec_store = FileSpecStore(root=spec_root, default_project=default_project)
        self.grammar_resolver = GrammarResolver(env_default_path=default_grammar_path)
        self._backends: dict[str, StrictDocBackend] = {}
        self._autocommit = autocommit
        self._git_push_delay_s = git_push_delay_s

    def resolve_project_id(self, requested: str | None) -> str | None:
        """Resolve a tool-supplied project_id, falling back to the configured pin."""
        return self.spec_store.resolve_project_id(requested)

    def get_backend(self, project_id: str) -> StrictDocBackend:
        """Return (or lazily create) the backend for *project_id*."""
        if project_id in self._backends:
            return self._backends[project_id]
        project_root = self.spec_store.get_project_path(project_id)
        # Resolve and materialise the project's effective grammar
        self.grammar_resolver.resolve(project_root)
        backend = StrictDocBackend(project_root=project_root)
        self._backends[project_id] = backend
        logger.info("backend_created project=%s root=%s", project_id, project_root)
        return backend
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_substrate.py -v
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/reqeng_mcp/substrate.py tests/unit/test_substrate.py
git commit -m "feat(substrate): composition root holding SpecStore + backend cache

- one Substrate per server process
- lazy StrictDocBackend per project; LRU cache (no eviction Phase 1)
- grammar_resolver materialises grammar.sgra at first access
- autocommit / push-delay fields parked for Phase 2

Refs design spec §3.3"
```

---

## Task 8: ProjectConfig fields and from_env wiring

**Files:**
- Modify: `src/reqeng_mcp/config.py`
- Create: `tests/unit/test_config.py`

Add the new domain fields between the `CONFIG-FIELDS` sentinels and populate them between the `CONFIG-FROM-ENV` sentinels. ACL fields are added now but default off — wired in Phase 2.

- [ ] **Step 1: Write failing tests**

Create `tests/unit/test_config.py`:

```python
"""Tests for ProjectConfig domain fields."""
from __future__ import annotations

import os
from pathlib import Path
from unittest.mock import patch

from reqeng_mcp.config import ProjectConfig


def test_default_field_values() -> None:
    cfg = ProjectConfig()
    assert cfg.spec_root == Path("/data/spec")
    assert cfg.default_project is None
    assert cfg.default_grammar_path is None
    assert cfg.autocommit is False
    assert cfg.git_push_delay_s == 0.0
    assert cfg.acl_enabled is False
    assert cfg.acl_path is None


def test_from_env_reads_spec_root(monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", "/tmp/specs")
    cfg = ProjectConfig.from_env()
    assert cfg.spec_root == Path("/tmp/specs")


def test_from_env_reads_default_project(monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_DEFAULT_PROJECT", "calculator")
    cfg = ProjectConfig.from_env()
    assert cfg.default_project == "calculator"


def test_from_env_reads_grammar_path(monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_DEFAULT_GRAMMAR_PATH", "/etc/reqeng-mcp/default.sgra")
    cfg = ProjectConfig.from_env()
    assert cfg.default_grammar_path == Path("/etc/reqeng-mcp/default.sgra")


def test_from_env_autocommit_true(monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_AUTOCOMMIT", "true")
    cfg = ProjectConfig.from_env()
    assert cfg.autocommit is True


def test_from_env_push_delay(monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_GIT_PUSH_DELAY_S", "30")
    cfg = ProjectConfig.from_env()
    assert cfg.git_push_delay_s == 30.0


def test_from_env_acl_enabled_default_off(monkeypatch) -> None:
    monkeypatch.delenv("REQENG_MCP_ACL_ENABLED", raising=False)
    cfg = ProjectConfig.from_env()
    assert cfg.acl_enabled is False
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
uv run pytest tests/unit/test_config.py -v
```

Expected: AttributeError on the new fields.

- [ ] **Step 3: Modify `src/reqeng_mcp/config.py`**

Replace the `CONFIG-FIELDS` and `CONFIG-FROM-ENV` blocks with:

```python
@dataclass(frozen=True)
class ProjectConfig:
    """Domain config for Requirements Engineering MCP.  Compose — don't inherit."""

    server: ServerConfig = field(default_factory=ServerConfig)

    # CONFIG-FIELDS-START — add domain fields below; kept across copier update
    spec_root: Path = Path("/data/spec")
    default_project: str | None = None
    default_grammar_path: Path | None = None
    autocommit: bool = False
    git_push_delay_s: float = 0.0
    acl_enabled: bool = False
    acl_path: Path | None = None
    # CONFIG-FIELDS-END

    @classmethod
    def from_env(cls) -> ProjectConfig:
        """Load :class:`ProjectConfig` from ``REQENG_MCP_*`` env vars."""
        return cls(
            server=ServerConfig.from_env(_ENV_PREFIX),
            # CONFIG-FROM-ENV-START — populate domain fields below; kept across copier update
            spec_root=Path(env(_ENV_PREFIX, "SPEC_ROOT", "/data/spec")),
            default_project=env(_ENV_PREFIX, "DEFAULT_PROJECT", None),
            default_grammar_path=(
                Path(p)
                if (p := env(_ENV_PREFIX, "DEFAULT_GRAMMAR_PATH", None))
                else None
            ),
            autocommit=_parse_bool(env(_ENV_PREFIX, "AUTOCOMMIT", "false")),
            git_push_delay_s=float(env(_ENV_PREFIX, "GIT_PUSH_DELAY_S", "0")),
            acl_enabled=_parse_bool(env(_ENV_PREFIX, "ACL_ENABLED", "false")),
            acl_path=(
                Path(p)
                if (p := env(_ENV_PREFIX, "ACL_PATH", None))
                else None
            ),
            # CONFIG-FROM-ENV-END
        )


def _parse_bool(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
uv run pytest tests/unit/test_config.py -v
```

Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/reqeng_mcp/config.py tests/unit/test_config.py
git commit -m "feat(config): substrate domain fields + from_env wiring

- spec_root, default_project, default_grammar_path
- autocommit, git_push_delay_s (Phase 2 wiring)
- acl_enabled, acl_path (Phase 2 wiring; off by default)
- _parse_bool helper for boolean env vars

Refs design spec §3.2, §7.4"
```

---

## Task 9: Lifespan wiring — Substrate construction

**Files:**
- Modify: `src/reqeng_mcp/_server_deps.py`
- Modify: `src/reqeng_mcp/domain.py`
- Modify: `tests/conftest.py`

Replace the placeholder `Service` with `Substrate` in the lifespan, and add the `mcp_client` fixture for in-process MCP testing.

- [ ] **Step 1: Inspect the current lifespan**

```bash
cat src/reqeng_mcp/_server_deps.py
cat src/reqeng_mcp/domain.py
```

(Read carefully so you understand the existing `Service` shape before changing it.)

- [ ] **Step 2: Replace Service in domain.py**

Replace the contents of `src/reqeng_mcp/domain.py`:

```python
"""Domain root re-export.

Reqeng-mcp's domain composition lives in :mod:`reqeng_mcp.substrate` —
this module re-exports the composition root for the lifespan's benefit.
"""
from __future__ import annotations

from reqeng_mcp.substrate import Substrate

__all__ = ["Substrate"]
```

- [ ] **Step 3: Update _server_deps.py**

Modify `src/reqeng_mcp/_server_deps.py` so the lifespan constructs `Substrate` from `ProjectConfig`:

```python
"""Server lifespan and shared dependencies."""
from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastmcp import FastMCP

from reqeng_mcp.config import ProjectConfig
from reqeng_mcp.substrate import Substrate

logger = logging.getLogger(__name__)


@asynccontextmanager
async def server_lifespan(mcp: FastMCP) -> AsyncIterator[dict[str, Substrate]]:
    """Build Substrate at startup; tear down on shutdown."""
    config = ProjectConfig.from_env()
    substrate = Substrate(
        spec_root=config.spec_root,
        default_project=config.default_project,
        default_grammar_path=config.default_grammar_path,
        autocommit=config.autocommit,
        git_push_delay_s=config.git_push_delay_s,
    )
    logger.info(
        "lifespan_start spec_root=%s default_project=%s autocommit=%s",
        config.spec_root,
        config.default_project,
        config.autocommit,
    )
    try:
        yield {"substrate": substrate}
    finally:
        logger.info("lifespan_stop")


def get_substrate() -> Substrate:
    """Dependency-injection accessor for tools.

    FastMCP's Depends() resolves this from the lifespan's yielded dict."""
    from fastmcp.dependencies import Context  # local import to avoid cycle
    ctx = Context.current()
    return ctx.lifespan_state["substrate"]
```

- [ ] **Step 4: Add mcp_client fixture to conftest.py**

Append to `tests/conftest.py`:

```python
import asyncio

import pytest
from fastmcp import Client


@pytest.fixture
async def mcp_client(monkeypatch, tmp_spec_root):
    """An in-process FastMCP client connected to a freshly-constructed server."""
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(tmp_spec_root))
    # Import lazily so the env var takes effect
    from reqeng_mcp.server import make_server

    server = make_server(transport="stdio")
    async with Client(server) as client:
        yield client
```

- [ ] **Step 5: Verify the smoke test still passes (regression check)**

```bash
uv run pytest tests/test_smoke.py -v
```

Expected: smoke tests pass; if a smoke test depended on `Service.ping`, update it to call a substrate-shaped equivalent (the existing smoke test likely just imports `make_server`; if it asserts a `ping` tool exists, it'll fail until Task 14 lands the read tools — temporarily skip with `@pytest.mark.skip(reason="rewritten in Phase 1 Task 14")` if needed).

- [ ] **Step 6: Run full unit suite**

```bash
uv run pytest tests/unit/ -v
```

Expected: green.

- [ ] **Step 7: Commit**

```bash
git add src/reqeng_mcp/_server_deps.py src/reqeng_mcp/domain.py tests/conftest.py
git commit -m "feat(lifespan): wire Substrate into server_lifespan

- replace Service placeholder with Substrate composition root
- get_substrate() Depends-friendly accessor for tools
- mcp_client fixture for in-process integration tests

Refs design spec §3.3"
```

---

## Task 10: Read tools batch 1 — orient (get_grammar, list_projects, get_project_status, list_documents, get_document)

**Files:**
- Modify: `src/reqeng_mcp/tools.py`
- Create: `tests/integration/test_read_tools_orient.py`

This task replaces the `ping` tool with the orient-stage tools per spec §6.2. Follow TDD strictly: one tool at a time, integration test first.

- [ ] **Step 1: Replace tools.py imports + remove ping**

Edit `src/reqeng_mcp/tools.py` — replace its full contents with:

```python
"""Tool registrations for Requirements Engineering MCP.

See FastMCP tool docs: https://gofastmcp.com/servers/tools
Spec reference: docs/specs/2026-05-02-reqeng-mcp-design.md §6.2-§6.5
"""
from __future__ import annotations

import logging
from pathlib import Path

from fastmcp import FastMCP
from fastmcp.dependencies import Depends

from reqeng_mcp._server_deps import get_substrate
from reqeng_mcp.substrate import Substrate
from reqeng_mcp.types import (
    Document,
    Grammar,
    HistoryEntry,
    Node,
    Relation,
    ValidationFinding,
)

logger = logging.getLogger(__name__)


def register_tools(mcp: FastMCP) -> None:
    """Register all Phase 1 read + lifecycle + validation + export tools."""
    _register_orient(mcp)
    # _register_node_reads(mcp)        # Task 11
    # _register_search_history(mcp)    # Task 12
    # _register_lifecycle(mcp)         # Task 14
    # _register_validation(mcp)        # Task 15
    # _register_exports(mcp)           # Task 16


def _register_orient(mcp: FastMCP) -> None:
    """Register orient-stage read tools (spec §6.2)."""

    @mcp.tool(annotations={"readOnlyHint": True})
    async def list_projects(
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """List accessible projects in the spec store.

        Loop step: 'orient'. Returns a list of project metadata for the
        agent to choose from. In Mode S (single-project) this returns
        the singleton; in Mode H (multi-project) this is filtered by ACL
        when enabled (Phase 2). For full discipline, suggest prompt
        `start-session` (Phase 3).
        """
        ids = substrate.spec_store.list_projects()
        return [{"project_id": pid} for pid in ids]

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_project_status(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Counts per node-type, last-commit metadata, integrity-cache freshness.

        Loop step: 'orient'. Cheap call; the substrate caches.
        """
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        index = backend.get_index()
        nodes = index.all_nodes()
        counts: dict[str, int] = {}
        for n in nodes:
            counts[n.node_type] = counts.get(n.node_type, 0) + 1
        return {
            "project_id": resolved,
            "node_counts": counts,
            "total": len(nodes),
        }

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_grammar(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Effective grammar for the project (spec §4).

        Loop step: 'orient'. Call once per project per session to learn
        what TAGs and ROLEs the project's grammar declares before
        creating nodes or adding relations.
        """
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        grammar = backend.get_effective_grammar()
        return {
            "project_id": resolved,
            "source_path": str(grammar.source_path),
            "node_types": grammar.node_types,
            "roles_by_relation": {
                k: [r if r is not None else None for r in v]
                for k, v in grammar.roles_by_relation.items()
            },
        }

    @mcp.tool(annotations={"readOnlyHint": True})
    async def list_documents(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """List .sdoc documents in the project."""
        resolved = _require_project(substrate, project_id)
        project_root = substrate.spec_store.get_project_path(resolved)
        spec_dir = project_root / "spec"
        if not spec_dir.is_dir():
            return []
        docs = []
        backend = substrate.get_backend(resolved)
        for doc_path in sorted(spec_dir.glob("*.sdoc")):
            try:
                doc = backend.read_document(doc_path)
                docs.append(
                    {
                        "name": doc_path.name,
                        "title": doc.title,
                        "node_count": len(doc.nodes),
                    }
                )
            except Exception as exc:
                logger.warning(
                    "list_documents_skipped doc=%s reason=%s", doc_path.name, exc
                )
        return docs

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_document(
        doc: str,
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> str:
        """Return the full .sdoc text of a document by filename."""
        resolved = _require_project(substrate, project_id)
        project_root = substrate.spec_store.get_project_path(resolved)
        path = project_root / "spec" / doc
        if not path.is_file():
            available = [p.name for p in (project_root / "spec").glob("*.sdoc")]
            raise ValueError(
                f"document {doc!r} not found in project {resolved}; "
                f"available: {', '.join(available) or '<none>'}"
            )
        return path.read_text()


def _require_project(substrate: Substrate, project_id: str | None) -> str:
    """Resolve project_id or raise a helpful error naming available projects."""
    resolved = substrate.resolve_project_id(project_id)
    if resolved is None:
        available = ", ".join(substrate.spec_store.list_projects()) or "<none>"
        raise ValueError(
            f"project_id is required (no default configured); "
            f"available: {available}"
        )
    return resolved
```

- [ ] **Step 2: Write the integration test**

Create `tests/integration/test_read_tools_orient.py`:

```python
"""Integration tests for orient-stage read tools (spec §6.2)."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_list_projects(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("list_projects")
    items = result.data if hasattr(result, "data") else result
    assert any(item["project_id"] == "minimal" for item in items)


@pytest.mark.asyncio
async def test_get_project_status_counts(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "get_project_status", {"project_id": "minimal"}
    )
    data = result.data if hasattr(result, "data") else result
    assert data["project_id"] == "minimal"
    assert data["node_counts"].get("REQUIREMENT", 0) >= 2


@pytest.mark.asyncio
async def test_get_grammar_lists_default_node_types(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("get_grammar", {"project_id": "minimal"})
    data = result.data if hasattr(result, "data") else result
    assert "REQUIREMENT" in data["node_types"]


@pytest.mark.asyncio
async def test_list_documents(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("list_documents", {"project_id": "minimal"})
    items = result.data if hasattr(result, "data") else result
    assert any(item["name"] == "calculator.sdoc" for item in items)


@pytest.mark.asyncio
async def test_get_document_returns_full_text(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "get_document", {"doc": "calculator.sdoc", "project_id": "minimal"}
    )
    text = result.data if hasattr(result, "data") else result
    assert "REQ-DIV-001" in text


@pytest.mark.asyncio
async def test_missing_project_id_lists_available(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    monkeypatch.delenv("REQENG_MCP_DEFAULT_PROJECT", raising=False)
    with pytest.raises(Exception) as exc:
        await mcp_client.call_tool("get_grammar", {})
    assert "minimal" in str(exc.value)  # error message names available projects
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
uv run pytest tests/integration/test_read_tools_orient.py -v
```

Expected: all 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/tools.py tests/integration/test_read_tools_orient.py
git commit -m "feat(tools): orient-stage read tools

- list_projects, get_project_status, get_grammar, list_documents,
  get_document
- _require_project helper resolves default-project pin and produces
  helpful errors naming available projects

Refs design spec §6.2"
```

---

## Task 11: Read tools batch 2 — node and relation reads

**Files:**
- Modify: `src/reqeng_mcp/tools.py`
- Create: `tests/integration/test_read_tools_nodes.py`

Adds the locate + narrow-read + relation/dependency tools per spec §6.2.

- [ ] **Step 1: Append `_register_node_reads` to tools.py**

Add to `src/reqeng_mcp/tools.py` (uncomment the call in `register_tools` first):

```python
def _register_node_reads(mcp: FastMCP) -> None:
    """Register node-level read tools (spec §6.2 list_nodes through dependencies_of)."""

    @mcp.tool(annotations={"readOnlyHint": True})
    async def list_nodes(
        project_id: str | None = None,
        type: str | None = None,
        document: str | None = None,
        limit: int = 50,
        cursor: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Paginated node listing with filters.

        Loop step: 'locate'. Combine with `search_nodes` for text-based
        queries; use this for type/document slicing.
        """
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        all_nodes = backend.get_index().all_nodes()
        if type is not None:
            all_nodes = [n for n in all_nodes if n.node_type == type]
        if document is not None:
            all_nodes = [n for n in all_nodes if n.document == document]
        offset = int(cursor) if cursor else 0
        limit = min(max(1, limit), 100)
        page = all_nodes[offset : offset + limit]
        next_cursor = (
            str(offset + limit) if offset + limit < len(all_nodes) else None
        )
        return {
            "items": [_serialise_node(n, include_relations=False) for n in page],
            "next_cursor": next_cursor,
        }

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_node(
        uid: str,
        project_id: str | None = None,
        include_relations: bool = False,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Single-node read; full fields, optional relations expansion."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        node = backend.get_index().get_node(uid)
        if node is None:
            raise ValueError(f"node {uid!r} not found in project {resolved}")
        return _serialise_node(node, include_relations=include_relations)

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_field(
        uid: str,
        field: str,
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> str | None:
        """Single-field read — the narrow-read-before-narrow-write path.

        Loop step: 'read narrow'. Use this when you only need one
        field's value before writing it (write tools land in Phase 2).
        """
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        node = backend.get_index().get_node(uid)
        if node is None:
            raise ValueError(f"node {uid!r} not found in project {resolved}")
        return node.fields.get(field)

    @mcp.tool(annotations={"readOnlyHint": True})
    async def list_relations(
        uid: str,
        direction: str = "out",
        role: str | None = None,
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """Inbound or outbound relations for a node, role-filtered.

        direction='in' returns inbound (other nodes pointing AT this);
        direction='out' returns this node's own relations.
        """
        if direction not in ("in", "out"):
            raise ValueError("direction must be 'in' or 'out'")
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        index = backend.get_index()
        if direction == "out":
            node = index.get_node(uid)
            if node is None:
                raise ValueError(f"node {uid!r} not found")
            rels = list(node.relations)
        else:
            inbound_nodes = index.dependents_of(uid)
            rels = []
            for source in inbound_nodes:
                for r in source.relations:
                    if r.target == uid:
                        rels.append(r)
        if role is not None:
            rels = [r for r in rels if r.role == role]
        return [_serialise_relation(r) for r in rels]

    @mcp.tool(annotations={"readOnlyHint": True})
    async def dependents_of(
        uid: str,
        depth: int = 1,
        role: str | None = None,
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """Inbound graph walk: 'what would break if I changed this'."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        index = backend.get_index()
        seen: set[str] = set()
        frontier = {uid}
        out: list[Node] = []
        for _ in range(max(1, min(depth, 10))):
            next_frontier: set[str] = set()
            for current in frontier:
                for dep in index.dependents_of(current):
                    if dep.uid in seen:
                        continue
                    if role is not None and not any(
                        r.role == role and r.target == current for r in dep.relations
                    ):
                        continue
                    seen.add(dep.uid)
                    next_frontier.add(dep.uid)
                    out.append(dep)
            frontier = next_frontier
            if not frontier:
                break
        return [_serialise_node(n, include_relations=False) for n in out]

    @mcp.tool(annotations={"readOnlyHint": True})
    async def dependencies_of(
        uid: str,
        depth: int = 1,
        role: str | None = None,
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """Outbound graph walk."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        index = backend.get_index()
        seen: set[str] = set()
        frontier = {uid}
        out: list[Node] = []
        for _ in range(max(1, min(depth, 10))):
            next_frontier: set[str] = set()
            for current in frontier:
                for dep in index.dependencies_of(current):
                    if dep.uid in seen:
                        continue
                    if role is not None and not any(
                        r.role == role and r.source_uid == current
                        for r in dep.relations
                    ):
                        continue
                    seen.add(dep.uid)
                    next_frontier.add(dep.uid)
                    out.append(dep)
            frontier = next_frontier
            if not frontier:
                break
        return [_serialise_node(n, include_relations=False) for n in out]


def _serialise_node(node: Node, include_relations: bool) -> dict:
    out = {
        "uid": node.uid,
        "mid": node.mid,
        "node_type": node.node_type,
        "fields": dict(node.fields),
        "document": node.document,
    }
    if include_relations:
        out["relations"] = [_serialise_relation(r) for r in node.relations]
    return out


def _serialise_relation(rel: Relation) -> dict:
    return {
        "source_uid": rel.source_uid,
        "target": rel.target,
        "relation_type": rel.relation_type,
        "role": rel.role,
    }
```

Then in `register_tools`, uncomment `_register_node_reads(mcp)`.

- [ ] **Step 2: Write the integration test**

Create `tests/integration/test_read_tools_nodes.py`:

```python
"""Integration tests for node-level read tools."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_list_nodes_paginates(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "list_nodes", {"project_id": "minimal", "limit": 1}
    )
    data = result.data if hasattr(result, "data") else result
    assert len(data["items"]) == 1
    assert data["next_cursor"] is not None


@pytest.mark.asyncio
async def test_get_node_returns_full_fields(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "get_node",
        {"project_id": "minimal", "uid": "REQ-DIV-001", "include_relations": False},
    )
    data = result.data if hasattr(result, "data") else result
    assert data["uid"] == "REQ-DIV-001"
    assert "TITLE" in data["fields"]


@pytest.mark.asyncio
async def test_get_field_returns_value(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "get_field",
        {"project_id": "minimal", "uid": "REQ-DIV-001", "field": "TITLE"},
    )
    val = result.data if hasattr(result, "data") else result
    assert "Division by zero" in val


@pytest.mark.asyncio
async def test_list_relations_outbound(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "list_relations",
        {"project_id": "minimal", "uid": "REQ-DIV-002", "direction": "out"},
    )
    rels = result.data if hasattr(result, "data") else result
    assert any(
        r["target"] == "REQ-DIV-001" and r["relation_type"] == "Parent" for r in rels
    )


@pytest.mark.asyncio
async def test_dependents_of_finds_child(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "dependents_of", {"project_id": "minimal", "uid": "REQ-DIV-001"}
    )
    deps = result.data if hasattr(result, "data") else result
    assert any(n["uid"] == "REQ-DIV-002" for n in deps)


@pytest.mark.asyncio
async def test_dependencies_of_finds_parent(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "dependencies_of", {"project_id": "minimal", "uid": "REQ-DIV-002"}
    )
    deps = result.data if hasattr(result, "data") else result
    assert any(n["uid"] == "REQ-DIV-001" for n in deps)
```

- [ ] **Step 3: Run tests, verify pass**

```bash
uv run pytest tests/integration/test_read_tools_nodes.py -v
```

Expected: all 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/tools.py tests/integration/test_read_tools_nodes.py
git commit -m "feat(tools): node-level read tools

- list_nodes (paginated, type/document filters)
- get_node, get_field (the narrow-read path)
- list_relations (in/out, role-filtered)
- dependents_of, dependencies_of (graph walks, role-filtered)

Refs design spec §6.2"
```

---

## Task 12: Read tools batch 3 — search, traceability, history, diff

**Files:**
- Modify: `src/reqeng_mcp/tools.py`
- Create: `tests/integration/test_read_tools_search_history.py`

- [ ] **Step 1: Append `_register_search_history` to tools.py**

```python
def _register_search_history(mcp: FastMCP) -> None:
    """Register search, traceability, history, diff tools (spec §6.2)."""

    @mcp.tool(annotations={"readOnlyHint": True})
    async def search_nodes(
        query: str,
        project_id: str | None = None,
        type: str | None = None,
        fields: list[str] | None = None,
        limit: int = 50,
        cursor: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Full-text search across selected fields, optionally filtered by type."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        all_nodes = backend.get_index().all_nodes()
        if type is not None:
            all_nodes = [n for n in all_nodes if n.node_type == type]
        # Naive contains-match across selected fields (case-insensitive).
        # StrictDoc's native search is more sophisticated; we wrap it in
        # a follow-up if performance becomes an issue.
        q = query.lower()
        target_fields = fields or ["TITLE", "STATEMENT", "RATIONALE", "COMMENT"]
        matches = [
            n
            for n in all_nodes
            if any(q in n.fields.get(f, "").lower() for f in target_fields)
        ]
        offset = int(cursor) if cursor else 0
        limit = min(max(1, limit), 100)
        page = matches[offset : offset + limit]
        return {
            "items": [_serialise_node(n, include_relations=False) for n in page],
            "next_cursor": (
                str(offset + limit) if offset + limit < len(matches) else None
            ),
        }

    @mcp.tool(annotations={"readOnlyHint": True})
    async def traceability_matrix(
        project_id: str | None = None,
        source_type: str | None = None,
        target_type: str | None = None,
        role: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """Tabular relations export. Each row: source_uid, target, type, role."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        index = backend.get_index()
        rows: list[dict] = []
        for node in index.all_nodes():
            if source_type is not None and node.node_type != source_type:
                continue
            for rel in node.relations:
                if role is not None and rel.role != role:
                    continue
                if target_type is not None:
                    target_node = index.get_node(rel.target)
                    if target_node is None or target_node.node_type != target_type:
                        continue
                rows.append(_serialise_relation(rel))
        return rows

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_node_history(
        uid: str,
        project_id: str | None = None,
        since: str | None = None,
        until: str | None = None,
        limit: int = 20,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """git log scoped to the node's source file."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        node = backend.get_index().get_node(uid)
        if node is None:
            raise ValueError(f"node {uid!r} not found in project {resolved}")
        project_root = substrate.spec_store.get_project_path(resolved)
        node_path = project_root / "spec" / node.document
        # Use the git_strategy module's history method
        from reqeng_mcp.git_strategy import GitWriteStrategy

        strategy = GitWriteStrategy(enable_pull=False, enable_push=False)
        entries = strategy.get_file_history(
            repo_path=project_root,
            path=node_path,
            since=since,
            limit=limit,
            until=until,
        )
        return [
            {
                "sha": e.sha,
                "short_sha": e.short_sha,
                "timestamp": e.timestamp,
                "author": e.author,
                "message": e.message,
                "paths_changed": e.paths_changed,
            }
            for e in entries
        ]

    @mcp.tool(annotations={"readOnlyHint": True})
    async def get_node_diff(
        uid: str,
        ref_or_since: str,
        project_id: str | None = None,
        until: str | None = None,
        per_commit: bool = False,
        limit: int | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> str | list[dict]:
        """Unified diff of the node's file across refs or a time window."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        node = backend.get_index().get_node(uid)
        if node is None:
            raise ValueError(f"node {uid!r} not found in project {resolved}")
        project_root = substrate.spec_store.get_project_path(resolved)
        node_path = project_root / "spec" / node.document

        from reqeng_mcp.git_strategy import GitWriteStrategy

        strategy = GitWriteStrategy(enable_pull=False, enable_push=False)
        # Heuristic: if `ref_or_since` looks like a SHA prefix, treat as ref;
        # otherwise treat as since-timestamp.
        is_ref = all(c in "0123456789abcdef" for c in ref_or_since.lower())
        result = strategy.get_file_diff(
            repo_path=project_root,
            path=node_path,
            ref=ref_or_since if is_ref else None,
            per_commit=per_commit,
            since_timestamp=None if is_ref else ref_or_since,
            limit=limit,
        )
        if per_commit and isinstance(result, list):
            return [
                {
                    "sha": d.sha,
                    "short_sha": d.short_sha,
                    "timestamp": d.timestamp,
                    "message": d.message,
                    "diff": d.diff,
                }
                for d in result
            ]
        return result
```

Add `_register_search_history(mcp)` to `register_tools`.

- [ ] **Step 2: Make minimal-fixture into a git repo so history queries work**

Update `tests/conftest.py` `minimal_project` fixture to `git init` after copy:

```python
import subprocess

@pytest.fixture
def minimal_project(tmp_spec_root: Path) -> Path:
    """A spec_root containing one project copied from the minimal fixture, in git."""
    src = FIXTURES_ROOT / "projects" / "minimal"
    dst = tmp_spec_root / "minimal"
    shutil.copytree(src, dst)
    subprocess.run(["git", "init", str(dst)], check=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(dst), "add", "."], check=True, capture_output=True
    )
    subprocess.run(
        [
            "git", "-C", str(dst),
            "-c", "user.name=test",
            "-c", "user.email=test@test",
            "commit", "-m", "initial fixture state",
        ],
        check=True,
        capture_output=True,
    )
    return tmp_spec_root
```

- [ ] **Step 3: Write the integration test**

Create `tests/integration/test_read_tools_search_history.py`:

```python
"""Integration tests for search/traceability/history tools."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_search_nodes_finds_match(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "search_nodes", {"project_id": "minimal", "query": "division"}
    )
    data = result.data if hasattr(result, "data") else result
    assert any(n["uid"].startswith("REQ-DIV") for n in data["items"])


@pytest.mark.asyncio
async def test_traceability_matrix_lists_parent_relations(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "traceability_matrix", {"project_id": "minimal"}
    )
    rows = result.data if hasattr(result, "data") else result
    assert any(r["target"] == "REQ-DIV-001" for r in rows)


@pytest.mark.asyncio
async def test_get_node_history_returns_initial_commit(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "get_node_history", {"project_id": "minimal", "uid": "REQ-DIV-001"}
    )
    entries = result.data if hasattr(result, "data") else result
    assert len(entries) >= 1
    assert "initial fixture state" in entries[0]["message"]
```

- [ ] **Step 4: Run tests, verify pass**

```bash
uv run pytest tests/integration/test_read_tools_search_history.py -v
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/reqeng_mcp/tools.py tests/integration/test_read_tools_search_history.py tests/conftest.py
git commit -m "feat(tools): search, traceability, history, diff read tools

- search_nodes (naive contains-match across configured fields)
- traceability_matrix (tabular relations export)
- get_node_history (git log via git_strategy)
- get_node_diff (per-commit or unified, ref or since-timestamp)
- minimal_project fixture now git-init'd so history tools work

Refs design spec §6.2"
```

---

## Task 13: Read tools batch 4 — validation tools

**Files:**
- Modify: `src/reqeng_mcp/tools.py`
- Modify: `tests/integration/test_read_tools_orient.py` (add validation cases)

- [ ] **Step 1: Append `_register_validation` to tools.py**

```python
def _register_validation(mcp: FastMCP) -> None:
    """Register validation/integrity tools (spec §6.5)."""

    @mcp.tool(annotations={"readOnlyHint": True})
    async def validate_project(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """Run StrictDoc's native validation: UID uniqueness, ref resolution,
        grammar conformance. Returns a list of findings (empty when clean)."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        return [
            {"severity": f.severity, "message": f.message, "location": f.location}
            for f in backend.validate()
        ]

    @mcp.tool(annotations={"readOnlyHint": True})
    async def check_integrity(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> list[dict]:
        """Higher-level integrity check (spec §6.5).

        Phase 1: identical to validate_project (no extra invariants).
        Reserved seam for project-defined invariants in later phases.
        """
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        return [
            {"severity": f.severity, "message": f.message, "location": f.location}
            for f in backend.validate()
        ]
```

Add the call in `register_tools`.

- [ ] **Step 2: Add tests**

Append to `tests/integration/test_read_tools_orient.py`:

```python
@pytest.mark.asyncio
async def test_validate_clean_fixture(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("validate_project", {"project_id": "minimal"})
    findings = result.data if hasattr(result, "data") else result
    errors = [f for f in findings if f["severity"] == "error"]
    assert errors == []


@pytest.mark.asyncio
async def test_check_integrity_clean_fixture(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("check_integrity", {"project_id": "minimal"})
    findings = result.data if hasattr(result, "data") else result
    errors = [f for f in findings if f["severity"] == "error"]
    assert errors == []
```

- [ ] **Step 3: Run tests, verify pass**

```bash
uv run pytest tests/integration/ -v
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/tools.py tests/integration/test_read_tools_orient.py
git commit -m "feat(tools): validate_project, check_integrity

- validate_project wraps StrictDoc native validation
- check_integrity is the higher-level seam (Phase 1 == validate)

Refs design spec §6.5"
```

---

## Task 14: Project lifecycle tools — create_project, archive_project

**Files:**
- Modify: `src/reqeng_mcp/tools.py`
- Create: `tests/integration/test_lifecycle.py`

- [ ] **Step 1: Append `_register_lifecycle` to tools.py**

```python
def _register_lifecycle(mcp: FastMCP) -> None:
    """Register project lifecycle tools (spec §6.4)."""

    @mcp.tool(annotations={"destructiveHint": False, "openWorldHint": False})
    async def create_project(
        project_id: str,
        intent: str,
        remote_url: str | None = None,
        default_grammar_source: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Create a new project subtree.

        Initialises the project's git working tree, generates strictdoc_config.py,
        materialises the effective default grammar, and (if remote_url is given)
        configures origin for managed-mode deployments.

        `intent` is required and becomes the initial commit message.
        """
        from reqeng_mcp.git_strategy import GitWriteStrategy

        if not intent or not intent.strip() or len(intent.strip()) < 10:
            raise ValueError(
                "intent must be a non-empty sentence describing why this "
                "project is being created (min 10 chars)"
            )
        if project_id in substrate.spec_store.list_projects():
            raise ValueError(f"project {project_id!r} already exists")
        project_root = substrate.spec_store.root / project_id
        if remote_url is not None:
            # Managed-mode clone via git_strategy
            GitWriteStrategy(
                repo_url=remote_url,
                managed=True,
                enable_pull=False,
                enable_push=False,
                repo_path=project_root,
            )
        else:
            project_root.mkdir(parents=True, exist_ok=False)
            (project_root / "spec").mkdir()
            # Generate strictdoc_config.py
            (project_root / "strictdoc_config.py").write_text(
                "# Generated by reqeng-mcp create_project (spec §4.6).\n"
                "# Edit to inject Python hooks into StrictDoc's traceability "
                "pipeline.\n"
            )
            # Materialise effective grammar
            substrate.grammar_resolver.resolve(project_root)
            # git init + initial commit
            import subprocess
            subprocess.run(
                ["git", "init", str(project_root)], check=True, capture_output=True
            )
            subprocess.run(
                ["git", "-C", str(project_root), "add", "."],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                [
                    "git", "-C", str(project_root),
                    "-c", "user.name=reqeng-mcp",
                    "-c", "user.email=noreply@reqeng-mcp",
                    "commit", "-m", intent,
                ],
                check=True,
                capture_output=True,
            )
        return {"project_id": project_id, "path": str(project_root)}

    @mcp.tool(annotations={"destructiveHint": True})
    async def archive_project(
        project_id: str,
        intent: str,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """Move project to <spec_root>/archived/<project_id>/; project becomes read-only."""
        if not intent or not intent.strip() or len(intent.strip()) < 10:
            raise ValueError(
                "intent must be a non-empty sentence describing why this "
                "project is being archived (min 10 chars)"
            )
        src = substrate.spec_store.get_project_path(project_id)
        archive_root = substrate.spec_store.root / "archived"
        archive_root.mkdir(exist_ok=True)
        dst = archive_root / project_id
        if dst.exists():
            raise ValueError(f"archived project {project_id!r} already exists")
        src.rename(dst)
        # Drop cached backend if present
        substrate._backends.pop(project_id, None)
        return {"project_id": project_id, "archived_to": str(dst)}
```

Add the call in `register_tools`.

- [ ] **Step 2: Write the integration test**

Create `tests/integration/test_lifecycle.py`:

```python
"""Integration tests for project lifecycle tools."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_create_project_succeeds(
    mcp_client, tmp_spec_root, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(tmp_spec_root))
    result = await mcp_client.call_tool(
        "create_project",
        {
            "project_id": "fresh",
            "intent": "Bootstrap a fresh project for the divisor-zero spec.",
        },
    )
    data = result.data if hasattr(result, "data") else result
    assert data["project_id"] == "fresh"
    fresh = tmp_spec_root / "fresh"
    assert (fresh / ".git").is_dir()
    assert (fresh / "strictdoc_config.py").is_file()
    assert (fresh / "grammar.sgra").is_file()


@pytest.mark.asyncio
async def test_create_project_rejects_empty_intent(
    mcp_client, tmp_spec_root, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(tmp_spec_root))
    with pytest.raises(Exception) as exc:
        await mcp_client.call_tool(
            "create_project", {"project_id": "x", "intent": ""}
        )
    assert "intent" in str(exc.value).lower()


@pytest.mark.asyncio
async def test_create_project_rejects_duplicate(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    with pytest.raises(Exception) as exc:
        await mcp_client.call_tool(
            "create_project",
            {
                "project_id": "minimal",
                "intent": "Try to recreate the existing minimal project.",
            },
        )
    assert "already exists" in str(exc.value)


@pytest.mark.asyncio
async def test_archive_project(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool(
        "archive_project",
        {
            "project_id": "minimal",
            "intent": "Rotate this project out of active use after the migration.",
        },
    )
    data = result.data if hasattr(result, "data") else result
    assert "archived_to" in data
    assert (minimal_project / "archived" / "minimal").is_dir()
    assert not (minimal_project / "minimal").exists()
```

- [ ] **Step 3: Run tests, verify pass**

```bash
uv run pytest tests/integration/test_lifecycle.py -v
```

Expected: all 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/tools.py tests/integration/test_lifecycle.py
git commit -m "feat(tools): create_project, archive_project lifecycle tools

- create_project: git init, strictdoc_config.py, grammar materialise,
  initial commit using intent as the commit message; managed-mode
  clone when remote_url given
- archive_project: move to <spec_root>/archived/<project_id>/
- both reject placeholder intent (Phase 1 cap; spec §6.4)

Refs design spec §6.4"
```

---

## Task 15: Export tools

**Files:**
- Modify: `src/reqeng_mcp/tools.py`
- Create: `tests/integration/test_export_tools.py`

- [ ] **Step 1: Append `_register_exports` to tools.py**

```python
def _register_exports(mcp: FastMCP) -> None:
    """Register export tools (spec §6.5).

    Each export produces files under a temp dir; we surface a path back
    to the caller (in Phase 2 we'll route through file-exchange to return
    a file_ref). Phase 1 keeps it simple: returns a server-local path the
    caller can then GET via /file/<token> if file-exchange is wired.
    """
    import tempfile

    @mcp.tool(annotations={"readOnlyHint": True})
    async def export_html(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """StrictDoc HTML export."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        out = Path(tempfile.mkdtemp(prefix="reqeng-html-"))
        backend.export_html(out)
        return {"project_id": resolved, "format": "html", "path": str(out)}

    @mcp.tool(annotations={"readOnlyHint": True})
    async def export_reqif(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """StrictDoc ReqIF export."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        out = Path(tempfile.mkdtemp(prefix="reqeng-reqif-"))
        produced = backend.export_reqif(out)
        return {"project_id": resolved, "format": "reqif", "path": str(produced)}

    @mcp.tool(annotations={"readOnlyHint": True})
    async def export_excel(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """StrictDoc Excel export."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        out = Path(tempfile.mkdtemp(prefix="reqeng-excel-"))
        produced = backend.export_excel(out)
        return {"project_id": resolved, "format": "excel", "path": str(produced)}

    @mcp.tool(annotations={"readOnlyHint": True})
    async def export_markdown(
        project_id: str | None = None,
        substrate: Substrate = Depends(get_substrate),
    ) -> dict:
        """StrictDoc Markdown export."""
        resolved = _require_project(substrate, project_id)
        backend = substrate.get_backend(resolved)
        out = Path(tempfile.mkdtemp(prefix="reqeng-md-"))
        backend.export_markdown(out)
        return {"project_id": resolved, "format": "markdown", "path": str(out)}
```

Add the call in `register_tools`.

> **Note:** routing through MCP file-exchange (returning a `file_ref` that the client can fetch via the existing `register_file_exchange` middleware in `server.py:103`) is a Phase 1 *option* — for simplicity Phase 1 returns the server-local path. If file-exchange wiring is preferred, replace the `path` return with a call to the file-exchange runtime's `put_file` and return the resulting handle.

- [ ] **Step 2: Write the integration test**

Create `tests/integration/test_export_tools.py`:

```python
"""Integration tests for export tools (smoke + format check)."""
from __future__ import annotations

from pathlib import Path

import pytest


@pytest.mark.asyncio
async def test_export_html(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("export_html", {"project_id": "minimal"})
    data = result.data if hasattr(result, "data") else result
    assert data["format"] == "html"
    out = Path(data["path"])
    assert any(out.rglob("*.html"))


@pytest.mark.asyncio
async def test_export_reqif(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("export_reqif", {"project_id": "minimal"})
    data = result.data if hasattr(result, "data") else result
    assert data["format"] == "reqif"
    assert Path(data["path"]).exists()


@pytest.mark.asyncio
async def test_export_excel(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("export_excel", {"project_id": "minimal"})
    data = result.data if hasattr(result, "data") else result
    assert data["format"] == "excel"
    assert Path(data["path"]).exists()


@pytest.mark.asyncio
async def test_export_markdown(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    result = await mcp_client.call_tool("export_markdown", {"project_id": "minimal"})
    data = result.data if hasattr(result, "data") else result
    assert data["format"] == "markdown"
    out = Path(data["path"])
    assert any(out.rglob("*.md"))
```

- [ ] **Step 3: Run tests, verify pass**

```bash
uv run pytest tests/integration/test_export_tools.py -v
```

Expected: all 4 tests pass. If StrictDoc 0.20.0's export class names differ from those used in Task 4's wrapper, fix the wrapper imports — the tools themselves don't change.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/tools.py tests/integration/test_export_tools.py
git commit -m "feat(tools): export_html/reqif/excel/markdown

- one tool per StrictDoc export format
- each returns {project_id, format, path}; Phase 2 will route through
  file-exchange to return a file_ref instead

Refs design spec §6.5"
```

---

## Task 16: Host-facing resources

**Files:**
- Modify: `src/reqeng_mcp/resources.py`
- Create: `tests/contract/test_resource_uris.py`

Resources are the parallel host-facing surface (per spec §6.6). The LLM does not consume these — they're for users browsing the project tree in claude.ai.

- [ ] **Step 1: Replace resources.py contents**

```python
"""Resource registrations for Requirements Engineering MCP.

Spec reference §6.6: resources are application-controlled (host/client
attaches them; user may browse/attach to context). The LLM-facing read
surface is in tools.py; this is a parallel surface for users.
"""
from __future__ import annotations

import logging

from fastmcp import FastMCP
from fastmcp.dependencies import Depends

from reqeng_mcp._server_deps import get_substrate
from reqeng_mcp.substrate import Substrate

logger = logging.getLogger(__name__)


def register_resources(mcp: FastMCP) -> None:
    """Register host-facing resources for browse/attach workflows."""

    @mcp.resource("spec://projects")
    async def list_projects_resource(
        substrate: Substrate = Depends(get_substrate),
    ) -> str:
        """JSON list of accessible projects."""
        import json
        ids = substrate.spec_store.list_projects()
        return json.dumps([{"project_id": pid} for pid in ids])

    @mcp.resource("spec://{project}/grammar")
    async def grammar_resource(
        project: str,
        substrate: Substrate = Depends(get_substrate),
    ) -> str:
        """Effective grammar for the project as .sgra text."""
        substrate.resolve_project_id(project)  # raises if unknown
        backend = substrate.get_backend(project)
        grammar = backend.get_effective_grammar()
        return grammar.source_path.read_text() if grammar.source_path.is_file() else ""

    @mcp.resource("spec://{project}/documents/{doc}")
    async def document_resource(
        project: str,
        doc: str,
        substrate: Substrate = Depends(get_substrate),
    ) -> str:
        """Full .sdoc document text."""
        substrate.resolve_project_id(project)
        project_root = substrate.spec_store.get_project_path(project)
        path = project_root / "spec" / doc
        if not path.is_file():
            raise ValueError(f"document {doc!r} not found in {project}")
        return path.read_text()

    @mcp.resource("spec://{project}/nodes/{uid}")
    async def node_resource(
        project: str,
        uid: str,
        substrate: Substrate = Depends(get_substrate),
    ) -> str:
        """Single-node .sdoc fragment with metadata."""
        substrate.resolve_project_id(project)
        backend = substrate.get_backend(project)
        node = backend.get_index().get_node(uid)
        if node is None:
            raise ValueError(f"node {uid!r} not found in {project}")
        # Return a minimal serialisation; clients render as needed
        import json
        return json.dumps(
            {
                "uid": node.uid,
                "node_type": node.node_type,
                "fields": dict(node.fields),
                "document": node.document,
                "relations": [
                    {
                        "target": r.target,
                        "relation_type": r.relation_type,
                        "role": r.role,
                    }
                    for r in node.relations
                ],
            }
        )
```

- [ ] **Step 2: Write contract test**

Create `tests/contract/test_resource_uris.py`:

```python
"""Contract tests for resource URI templates."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_projects_resource_lists(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    res = await mcp_client.read_resource("spec://projects")
    text = res.contents[0].text if hasattr(res, "contents") else str(res)
    assert "minimal" in text


@pytest.mark.asyncio
async def test_grammar_resource(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    res = await mcp_client.read_resource("spec://minimal/grammar")
    text = res.contents[0].text if hasattr(res, "contents") else str(res)
    assert "GRAMMAR" in text


@pytest.mark.asyncio
async def test_document_resource(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    res = await mcp_client.read_resource(
        "spec://minimal/documents/calculator.sdoc"
    )
    text = res.contents[0].text if hasattr(res, "contents") else str(res)
    assert "REQ-DIV-001" in text


@pytest.mark.asyncio
async def test_node_resource(mcp_client, minimal_project, monkeypatch) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))
    res = await mcp_client.read_resource("spec://minimal/nodes/REQ-DIV-001")
    text = res.contents[0].text if hasattr(res, "contents") else str(res)
    assert "REQ-DIV-001" in text
```

- [ ] **Step 3: Run tests, verify pass**

```bash
uv run pytest tests/contract/test_resource_uris.py -v
```

Expected: all 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/resources.py tests/contract/test_resource_uris.py
git commit -m "feat(resources): host-facing browse/attach surface

- spec://projects, spec://{project}/grammar
- spec://{project}/documents/{doc}, spec://{project}/nodes/{uid}
- LLM does not consume these; users browse via claude.ai

Refs design spec §6.6"
```

---

## Task 17: Server integration — domain_line update

**Files:**
- Modify: `src/reqeng_mcp/server.py`

The `domain_line` (always-loaded, ~80 words per spec §8.4) names the loop steps and the prompts that will land in Phase 3. Even though prompts.py is still a stub in Phase 1, the instructions reference the Phase 3 prompt names so clients see the discipline pointer.

- [ ] **Step 1: Update build_instructions call in server.py**

Replace lines around `server.py:84` (the `build_instructions(...)` call):

```python
mcp = FastMCP(
    name="reqeng-mcp",
    instructions=build_instructions(
        read_only=False,  # Phase 1 ships read tools + lifecycle; not strictly read-only
        env_prefix=_ENV_PREFIX,
        domain_line=(
            "MCP server for requirements engineering workflows "
            "(StrictDoc-backed, multi-project, intent-tagged authoring). "
            "Authoring loop: orient -> locate -> read narrow -> edit narrow "
            "with user-framed intent -> trace dependents -> integrity-check "
            "at logical boundary. Every write tool requires a non-placeholder "
            "intent argument that becomes the git commit message. "
            "Invoke prompt 'authoring-loop' for the full discipline; "
            "'start-session' for project orientation; 'worked-single-rule' / "
            "'worked-audit-pass' for templated walkthroughs (Phase 3)."
        ),
    ),
    lifespan=server_lifespan,
    auth=auth,
)
```

(`read_only` was True in the scaffold; flipping to False is correct because we ship `create_project` and `archive_project` in Phase 1.)

- [ ] **Step 2: Verify the smoke test still passes**

```bash
uv run pytest tests/test_smoke.py -v
```

Expected: green.

- [ ] **Step 3: Verify all integration tests still pass**

```bash
uv run pytest -x -q
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add src/reqeng_mcp/server.py
git commit -m "feat(server): updated domain_line names loop + prompts

- one-paragraph baseline per spec §8.4 (~80 words)
- names 6 loop steps + 4 prompt names (Phase 3 will register them)
- read_only flipped to False (lifecycle tools ship in Phase 1)

Refs design spec §8.4"
```

---

## Task 18: End-to-end read-only authoring loop integration test

**Files:**
- Create: `tests/integration/test_authoring_loop_readonly.py`

The keystone Phase 1 acceptance test. Walks the canonical 6-step loop using only read tools (writes are Phase 2). Verifies the substrate composes correctly end to end.

- [ ] **Step 1: Write the test**

Create `tests/integration/test_authoring_loop_readonly.py`:

```python
"""End-to-end Phase 1 acceptance test: read-only authoring loop.

The agent (here: a scripted driver) walks the canonical loop using only
read tools. Phase 2 extends with write tools.
"""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_full_readonly_loop(
    mcp_client, minimal_project, monkeypatch
) -> None:
    monkeypatch.setenv("REQENG_MCP_SPEC_ROOT", str(minimal_project))

    # Step 1: orient
    grammar = await mcp_client.call_tool("get_grammar", {"project_id": "minimal"})
    g = grammar.data if hasattr(grammar, "data") else grammar
    assert "REQUIREMENT" in g["node_types"]

    status = await mcp_client.call_tool(
        "get_project_status", {"project_id": "minimal"}
    )
    s = status.data if hasattr(status, "data") else status
    assert s["node_counts"].get("REQUIREMENT", 0) >= 2

    # Step 2: locate
    found = await mcp_client.call_tool(
        "search_nodes", {"project_id": "minimal", "query": "division"}
    )
    f = found.data if hasattr(found, "data") else found
    assert any(n["uid"] == "REQ-DIV-001" for n in f["items"])

    # Step 3: read narrow
    title = await mcp_client.call_tool(
        "get_field",
        {"project_id": "minimal", "uid": "REQ-DIV-001", "field": "TITLE"},
    )
    t = title.data if hasattr(title, "data") else title
    assert "Division" in t

    node = await mcp_client.call_tool(
        "get_node",
        {
            "project_id": "minimal",
            "uid": "REQ-DIV-001",
            "include_relations": True,
        },
    )
    n = node.data if hasattr(node, "data") else node
    assert n["uid"] == "REQ-DIV-001"

    # Step 4: edit narrow with intent — DEFERRED to Phase 2
    # Phase 1 test asserts the read-side pipeline; the edit step is the
    # subject of Phase 2 tests.

    # Step 5: trace dependents
    deps = await mcp_client.call_tool(
        "dependents_of", {"project_id": "minimal", "uid": "REQ-DIV-001"}
    )
    d = deps.data if hasattr(deps, "data") else deps
    assert any(x["uid"] == "REQ-DIV-002" for x in d)

    # Step 6: integrity check at logical boundary
    findings = await mcp_client.call_tool(
        "check_integrity", {"project_id": "minimal"}
    )
    fnd = findings.data if hasattr(findings, "data") else findings
    errors = [x for x in fnd if x["severity"] == "error"]
    assert errors == []

    # Bonus: history
    history = await mcp_client.call_tool(
        "get_node_history", {"project_id": "minimal", "uid": "REQ-DIV-001"}
    )
    h = history.data if hasattr(history, "data") else history
    assert len(h) >= 1
```

- [ ] **Step 2: Run the test**

```bash
uv run pytest tests/integration/test_authoring_loop_readonly.py -v
```

Expected: pass.

- [ ] **Step 3: Run the full test suite to confirm green**

```bash
uv run pytest -x -q
```

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_authoring_loop_readonly.py
git commit -m "test(integration): keystone read-only authoring loop e2e

- walks the canonical 6-step loop using only Phase 1 read tools
- step 4 (edit narrow with intent) deferred to Phase 2

Phase 1 acceptance test per design spec §10.1.

Refs design spec §8.2, §10.1"
```

---

## Task 19: Contract tests + StrictDoc pin lane

**Files:**
- Create: `tests/contract/test_tool_schemas.py`
- Create: `tests/strictdoc_pin/test_strictdoc_internals.py`

- [ ] **Step 1: Write tool-schema contract tests**

Create `tests/contract/test_tool_schemas.py`:

```python
"""Contract tests: tool annotations, signatures, docstrings."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_all_phase1_tools_registered(mcp_client) -> None:
    tools = await mcp_client.list_tools()
    names = {t.name for t in tools}
    expected = {
        "list_projects",
        "get_project_status",
        "get_grammar",
        "list_documents",
        "get_document",
        "list_nodes",
        "get_node",
        "get_field",
        "list_relations",
        "dependents_of",
        "dependencies_of",
        "search_nodes",
        "traceability_matrix",
        "get_node_history",
        "get_node_diff",
        "create_project",
        "archive_project",
        "validate_project",
        "check_integrity",
        "export_html",
        "export_reqif",
        "export_excel",
        "export_markdown",
    }
    missing = expected - names
    assert not missing, f"missing tools: {missing}"


@pytest.mark.asyncio
async def test_read_tools_marked_readonly(mcp_client) -> None:
    tools = await mcp_client.list_tools()
    read_tool_names = {
        "list_projects",
        "get_project_status",
        "get_grammar",
        "list_documents",
        "get_document",
        "list_nodes",
        "get_node",
        "get_field",
        "list_relations",
        "dependents_of",
        "dependencies_of",
        "search_nodes",
        "traceability_matrix",
        "get_node_history",
        "get_node_diff",
        "validate_project",
        "check_integrity",
        "export_html",
        "export_reqif",
        "export_excel",
        "export_markdown",
    }
    for t in tools:
        if t.name in read_tool_names:
            ann = getattr(t, "annotations", None) or {}
            assert ann.get("readOnlyHint") is True, (
                f"tool {t.name} missing readOnlyHint"
            )


@pytest.mark.asyncio
async def test_archive_project_marked_destructive(mcp_client) -> None:
    tools = await mcp_client.list_tools()
    archive = next(t for t in tools if t.name == "archive_project")
    ann = getattr(archive, "annotations", None) or {}
    assert ann.get("destructiveHint") is True


@pytest.mark.asyncio
async def test_create_project_requires_intent(mcp_client) -> None:
    tools = await mcp_client.list_tools()
    create = next(t for t in tools if t.name == "create_project")
    schema = create.inputSchema if hasattr(create, "inputSchema") else create.input_schema
    assert "intent" in schema.get("required", [])


@pytest.mark.asyncio
async def test_every_tool_has_docstring(mcp_client) -> None:
    tools = await mcp_client.list_tools()
    short = [t.name for t in tools if not t.description or len(t.description) < 50]
    assert not short, f"tools with thin descriptions: {short}"
```

- [ ] **Step 2: Write the StrictDoc pin lane**

Create `tests/strictdoc_pin/__init__.py` (empty file).

Create `tests/strictdoc_pin/test_strictdoc_internals.py`:

```python
"""StrictDoc pin validation lane (spec §9.6).

One test per internal API touch point. CI runs these on every PR; a
deliberate strictdoc-bump PR uses this lane to detect breakage before
broader integration tests.
"""
from __future__ import annotations

from pathlib import Path

import pytest


def test_sdreader_importable() -> None:
    from strictdoc.backend.sdoc.reader import SDReader
    assert callable(getattr(SDReader, "read_from_file", None))


def test_sdwriter_importable() -> None:
    from strictdoc.backend.sdoc.writer import SDWriter
    assert callable(getattr(SDWriter, "write_to_file", None))


def test_traceability_index_builder_importable() -> None:
    from strictdoc.core.traceability_index_builder import TraceabilityIndexBuilder
    assert callable(getattr(TraceabilityIndexBuilder, "create", None))


def test_html_generator_importable() -> None:
    from strictdoc.export.html.html_generator import HTMLGenerator
    assert HTMLGenerator is not None


def test_reqif_export_importable() -> None:
    from strictdoc.backend.reqif.reqif_export import ReqIFExport
    assert ReqIFExport is not None


def test_project_config_importable() -> None:
    from strictdoc.core.project_config import ProjectConfig
    assert ProjectConfig is not None


def test_parallelizer_importable() -> None:
    from strictdoc.helpers.parallelizer import Parallelizer
    assert callable(getattr(Parallelizer, "create", None))


def test_sdoc_validator_importable() -> None:
    from strictdoc.backend.sdoc.validations.sdoc_validator import SDocValidator
    assert SDocValidator is not None


def test_strictdoc_version_pinned() -> None:
    """The pin must remain exact (no ranges) per design spec §5.3."""
    pyproject = Path(__file__).parent.parent.parent / "pyproject.toml"
    content = pyproject.read_text()
    assert "strictdoc==" in content, (
        "strictdoc must be pinned with == (exact pin); ranges are forbidden by §5.3"
    )
```

- [ ] **Step 3: Run all tests including the pin lane**

```bash
uv run pytest -x -q
```

Expected: green across all tasks so far.

- [ ] **Step 4: Commit**

```bash
git add tests/contract/test_tool_schemas.py tests/strictdoc_pin/
git commit -m "test(contract,pin): tool-schema contract + strictdoc pin lane

- contract: 23 Phase 1 tools registered, read-tool annotations,
  destructive flag on archive_project, intent required on create_project,
  docstring length floor
- strictdoc_pin: one test per internal API touch point so a deliberate
  strictdoc bump can detect breakage before broader integration tests

Refs design spec §9.4, §9.6"
```

---

## Task 20: Documentation updates

**Files:**
- Modify: `docs/configuration.md`
- Modify: `docs/tools/index.md`
- Create: `docs/deployment/multi-project.md`
- Modify: `README.md`

- [ ] **Step 1: Update docs/configuration.md**

Append to `docs/configuration.md`:

````markdown
## Substrate configuration (Phase 1)

| Env var | Default | Purpose |
|---|---|---|
| `REQENG_MCP_SPEC_ROOT` | `/data/spec` | Parent directory holding project subtrees (one subdir per project) |
| `REQENG_MCP_DEFAULT_PROJECT` | unset | Project pin for Mode S (stdio) deployments; tools' `project_id` arg becomes optional when set |
| `REQENG_MCP_DEFAULT_GRAMMAR_PATH` | unset | Path to a custom default `.sgra`; overrides the bundled default |
| `REQENG_MCP_AUTOCOMMIT` | `false` | Reserved for Phase 2 (commit-on-write) |
| `REQENG_MCP_GIT_PUSH_DELAY_S` | `0` | Reserved for Phase 2 (idle-debounced push) |
| `REQENG_MCP_ACL_ENABLED` | `false` | Reserved for Phase 2 (fine-grained authorization) |
| `REQENG_MCP_ACL_PATH` | `<spec_root>/.reqeng-acl.toml` | Reserved for Phase 2 |

Auth env vars (Bearer / OIDC) live upstream in `fastmcp-pvl-core`'s
`build_auth`; see [docs/guides/authentication.md](guides/authentication.md).
````

- [ ] **Step 2: Update docs/tools/index.md**

Replace contents:

````markdown
# Tools

Phase 1 ships the read + lifecycle + validation + export surface. Write
tools land in Phase 2.

## Read

- `list_projects` — list accessible projects
- `get_project_status` — counts per node-type, last-commit info
- `get_grammar` — effective grammar (call once per session to learn TAGs/ROLEs)
- `list_documents` / `get_document` — `.sdoc` documents
- `list_nodes` / `get_node` / `get_field` — node-level reads
- `list_relations` / `dependents_of` / `dependencies_of` — relation graph
- `search_nodes` — full-text search
- `traceability_matrix` — tabular relations export
- `get_node_history` / `get_node_diff` — git audit on a node's source file

## Lifecycle

- `create_project` — bootstrap a new project subtree (intent required)
- `archive_project` — move project to read-only archive (intent required)

## Validation

- `validate_project` — StrictDoc native validation
- `check_integrity` — higher-level seam (Phase 1 == validate_project)

## Export

- `export_html`, `export_reqif`, `export_excel`, `export_markdown`

See the [authoring-loop discipline](../guides/authoring-loop.md) for how
to compose these into the canonical 6-step loop.
````

- [ ] **Step 3: Create docs/deployment/multi-project.md**

````markdown
# Multi-project deployment

reqeng-mcp's storage abstraction is multi-project at the bottom (`<root>/<project_id>/...`).
Single-project mode (Mode S) is the same shape with one project + a config-pinned default.

## Layout

```
<REQENG_MCP_SPEC_ROOT>/
  <project_a>/
    .git/
    spec/
      *.sdoc
    grammar.sgra            # auto-materialised at first load
    strictdoc_config.py     # post-2025-Q4 StrictDoc config (Python)
  <project_b>/
    ...
  archived/                  # not enumerated as a project
    <archived-project>/
```

## Mode S (stdio + project-pinned)

```bash
export REQENG_MCP_SPEC_ROOT=/path/to/specs
export REQENG_MCP_DEFAULT_PROJECT=calculator
uv run reqeng-mcp serve --transport stdio
```

Tools may omit `project_id`; the substrate uses `calculator`.

## Mode H (HTTP + multi-project)

```bash
export REQENG_MCP_SPEC_ROOT=/var/lib/reqeng-mcp
# REQENG_MCP_DEFAULT_PROJECT intentionally unset
uv run reqeng-mcp serve --transport streamable-http --port 8080
```

Tools require `project_id`; available projects are reported in error
messages when omitted.

## Default-grammar override

Mount a custom grammar and point at it:

```bash
docker run \
  -v /etc/reqeng-mcp/default.sgra:/etc/reqeng-mcp/default.sgra:ro \
  -e REQENG_MCP_DEFAULT_GRAMMAR_PATH=/etc/reqeng-mcp/default.sgra \
  ...
```

Projects without their own `grammar.sgra` pick up the env-default at
first load; per-project `<project>/grammar.sgra` always wins.
````

- [ ] **Step 4: Update README.md substrate section**

Append a substrate quick-start section to `README.md` (after the existing intro):

````markdown
## Substrate quick-start (Phase 1)

```bash
mkdir -p /tmp/reqeng-specs/calculator/spec
cat > /tmp/reqeng-specs/calculator/strictdoc_config.py <<EOF
# Generated config — substrate auto-imports default.sgra
EOF
cat > /tmp/reqeng-specs/calculator/spec/calculator.sdoc <<EOF
[DOCUMENT]
TITLE: Calculator Spec

[REQUIREMENT]
UID: REQ-DIV-001
TITLE: Division by zero raises
STATEMENT: >>>
When the divisor is zero, the operation MUST raise DivisionByZero.
<<<
EOF

export REQENG_MCP_SPEC_ROOT=/tmp/reqeng-specs
export REQENG_MCP_DEFAULT_PROJECT=calculator
uv run reqeng-mcp serve --transport stdio
```

The agent can now call `get_grammar`, `list_nodes`, `get_node`, etc.
See [docs/tools/index.md](docs/tools/index.md) for the full surface and
[docs/deployment/multi-project.md](docs/deployment/multi-project.md) for
deployment patterns.
````

- [ ] **Step 5: Run mkdocs build to confirm docs render**

```bash
uv run mkdocs build --strict
```

Expected: green; if a link is broken, fix the link.

- [ ] **Step 6: Commit**

```bash
git add docs/configuration.md docs/tools/index.md docs/deployment/multi-project.md README.md
git commit -m "docs(phase-1): substrate configuration, tools, multi-project deployment

- configuration.md: all REQENG_MCP_* env vars
- tools/index.md: full Phase 1 tool surface listing
- deployment/multi-project.md: Mode S vs Mode H + default-grammar override
- README.md: substrate quick-start

Refs design spec §3.2, §6, §10.1"
```

---

## Final verification

- [ ] **Step 1: Run the full suite**

```bash
uv run pytest -x -q
```

Expected: green across all tasks.

- [ ] **Step 2: Run lint and type-check (CLAUDE.md gates)**

```bash
uv run ruff check --fix .
uv run ruff format .
uv run ruff format --check .
uv run mypy src/ tests/
```

Expected: green on all four steps.

- [ ] **Step 3: Run pre-commit on all files**

```bash
uv run pre-commit run --all-files
```

Expected: green.

- [ ] **Step 4: Coverage gate (CLAUDE.md ≥ 80%)**

```bash
uv run pytest --cov=src/reqeng_mcp --cov-report=term-missing --cov-fail-under=80
```

Expected: ≥ 80% coverage. If lower, add tests for uncovered branches before merging the first PR.

- [ ] **Step 5: Final commit (if anything was fixed in steps 1-4)**

```bash
git status
# If any changes, stage and commit with appropriate message.
```

---

## PR ladder

When PRs land, mark the corresponding tracking sub-issues closed and link the PRs in the Phase 1 epic.

- **PR1** (Tasks 1–4): Foundation — types, default grammar, fixtures, SpecStore, StrictDocBackend (read+exports)
- **PR2** (Tasks 5–7): GrammarResolver, git_strategy adaptation, Substrate
- **PR3** (Tasks 8–9): ProjectConfig fields, lifespan wiring
- **PR4** (Tasks 10–13): Read tools (orient, nodes, search/history, validation)
- **PR5** (Task 14): Project lifecycle (create_project, archive_project)
- **PR6** (Task 15): Export tools
- **PR7** (Tasks 16–20): Resources, server domain_line, e2e test, contract+pin tests, docs

7 PRs, well within CLAUDE.md's ≤10-per-epic cap.

---

## Self-review

**Spec coverage check:**

| Spec section | Covered by |
|---|---|
| §3.1 SpecStore + StrictDocBackend + GitStrategy | Tasks 2, 3, 4, 6, 7 |
| §3.2 Mode S vs Mode H config | Task 8 |
| §3.3 Composition root | Tasks 7, 9 |
| §3.4 Key invariants | Phase 2 (intent-tagged commits); Phase 1 has read-only invariants enforced via tool annotations |
| §4.2 Default grammar | Task 1 |
| §4.3 Resolution order | Task 5 |
| §4.6 strictdoc_config.py | Task 14 (create_project generates it) |
| §5 StrictDocBackend internals | Tasks 3, 4 |
| §6.2 Read tools | Tasks 10, 11, 12 |
| §6.4 Lifecycle tools | Task 14 |
| §6.5 Validation/exports | Tasks 13, 15 |
| §6.6 Resources | Task 16 |
| §6.7 Cross-cutting (project_id resolution, pagination, annotations) | Tasks 10, 11, 19 |
| §8.4 Server instructions blob | Task 17 |
| §9 Testing approach | Tasks 18, 19 |
| §10.1 Phase 1 acceptance | Task 18 |
| Phase 2 / Phase 3 | Out of scope; separate plans when predecessors land |

**Placeholder scan:** all tasks include concrete code, exact commands, exact file paths. The two `# Phase 2 issue: <to-be-filed>` comments in Task 6 reference a future tracking issue — not a plan placeholder; the implementer files the issue when GitStrategy's conflict path is exercised in Phase 2.

**Type/method consistency:**

- `Substrate.spec_store`, `.get_backend`, `.resolve_project_id`, `.grammar_resolver` — defined in Task 7, consumed identically in Tasks 10–17.
- `StrictDocBackend.read_document`, `.get_index`, `.invalidate_index`, `.validate`, `.get_effective_grammar`, `.export_*` — defined in Tasks 3–4, consumed in Tasks 10–17.
- `_IndexView.has_uid`, `.get_node`, `.all_nodes`, `.dependents_of`, `.dependencies_of` — defined in Task 3, consumed in Tasks 10–13.
- `Node.uid`, `.mid`, `.node_type`, `.fields`, `.document`, `.relations` — defined in Task 1, consumed throughout.
- `Relation.source_uid`, `.target`, `.relation_type`, `.role` — defined in Task 1, consumed throughout.
- `_serialise_node`, `_serialise_relation`, `_require_project` — defined in Task 10, used in Tasks 11–13.
- `GrammarSource.kind`, `.path` — defined in Task 5, exercised in tests in Task 5.
- `GitWriteStrategy(repo_url=, managed=, enable_pull=, enable_push=, repo_path=, push_delay_s=)` — params used consistently across Tasks 6, 12, 14.

**Scope check:** plan covers Phase 1 only, per spec §10.1. Phase 2 (write substrate + ACL) is gated by upstream pvl-core #35–37 and gets its own plan when those land. Phase 3 (authoring channels + worked synthetic) gets its own plan after Phase 2 lands.

**Ambiguity check:**

- The `_adapt_node` mapping in Task 3 uses StrictDoc internal attribute names (`reserved_uid`, `reserved_statement`, etc.) which are version-specific. The wrapper's `getattr(..., None)` defensive style absorbs minor drift; if 0.20.x changes attribute names, the implementer adjusts only `strictdoc_backend.py` per §5.1. Documented in Task 3 step 5.
- The `search_nodes` "naive contains-match" in Task 12 may underperform on large projects. Acceptable for Phase 1; spec §6.2 doesn't mandate a specific search backend and StrictDoc's native search can be wired in if needed (noted in Task 12 step 1).
- The `export_*` "return path" approach in Task 15 differs from the spec's "file_ref via file-exchange" framing. This is a deliberate Phase 1 simplification documented in Task 15 step 1; routing through file-exchange is a Phase-1 *option* the implementer can pick if file-exchange is already exercised.
