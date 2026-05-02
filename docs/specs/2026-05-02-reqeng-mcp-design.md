# Reqeng-MCP — Authoring Substrate for LLM-Drafted Technical Specifications

**Status:** Design — approved for implementation in phases (see Section 10)
**Date:** 2026-05-02
**Authors:** Peter van Liesdonk, with Claude Opus 4.7 as drafting partner
**Related repos:** `pvliesdonk/fastmcp-pvl-core`, `pvliesdonk/fastmcp-server-template`, `pvliesdonk/markdown-mcp` (pattern source for git strategy)

---

## 1. Problem

Drafting a non-trivial technical specification with an LLM as primary author breaks down at the same point every time: the LLM holds either the high-level structure or the local detail, but not both. When asked to fix a low-level inconsistency, it slips into synthesis mode and produces text that no longer matches its own stated intent. When asked to extend a section, it loses track of cross-references it made three sections earlier.

The diagnosis is not that the LLM cannot reason about the content — capable models can. The diagnosis is that the LLM is being asked to do two jobs simultaneously: reason about the actual subject matter, and maintain the structural integrity of the document (stable identifiers, cross-references, applicability scopes, supersedes chains, schema compliance of embedded data). With nothing else maintaining the structure, every fragment of context spent on bookkeeping is context not spent on the substance. Beyond a certain spec size, this becomes unrecoverable, and the LLM produces output that looks plausible but is internally inconsistent.

This project addresses the bottleneck for one specific class of work — technical specifications with rich internal structure — where the failure pattern is well-characterised and the intervention is concrete: an MCP server that wraps an existing requirements-management tool (StrictDoc) and exposes a typed read/write surface that takes structural bookkeeping off the LLM's plate.

## 2. What this is and is not

**This is** an authoring substrate that sits between an LLM coding agent and a typed specification store. The substrate consists of three layers:

1. A typed storage backend (StrictDoc) with custom grammars per project, stable identifiers, typed relations, schema validation, and git-friendly serialisation.
2. An MCP server exposing field-level read/write operations, applicability and dependency queries, and integrity checks.
3. Discipline carriers (server `instructions`, tool docstrings, MCP prompts, optional Claude Code skill) that teach the agent how to use the substrate without prescribing what the user must say.

**This is not** another requirements management tool. Existing tools (StrictDoc, Doorstop, Sphinx-Needs, Polarion, DOORS, Jama) are built for humans authoring specs and machines auditing them. The reverse problem — machines authoring specs under human review — is what this addresses.

**Out of scope** (deliberate, not deferred):

- GUI editing beyond what StrictDoc's webapp already provides. Co-hosting StrictDoc's webapp under the same HTTP server is a tracked future enhancement (see Section 10.2).
- Multi-user concurrent editing of the same node. Last-writer-wins via git; conflict files surface divergence; no CRDT or live-collab layer.
- Full ReqIF interchange round-trip beyond StrictDoc-native ReqIF export.
- Safety-critical certification fitness (DO-178C, ISO 26262 tool qualification). The substrate hosts ASIL-extended grammars but is not itself certified.
- OIDC group-mapping in v1 (subject-string ACLs only).
- Per-document or per-node ACLs. Project-grain only.
- A bespoke spec-authoring UI for humans. The substrate is for LLM authoring; humans review via git diffs and StrictDoc's existing exports.

## 3. Architecture overview

### 3.1 System shape

A FastMCP server composing `fastmcp-pvl-core` primitives, with three substantive components added on top:

- **`SpecStore`** — uniform multi-project storage abstraction. Indexed by `project_id`. Concrete impl `FileSpecStore`, layout `<root>/<project_id>/...`. Always multi-project at the storage layer; single-project mode is one project plus a config-pinned default.
- **`StrictDocBackend`** — wraps StrictDoc's Python API for parse / serialise / query / validate operations. The only place in the codebase that imports `strictdoc.*`. Exposes our-shape types (`Document`, `Node`, `Relation`, `Grammar`, `ValidationFinding`) to the rest of the substrate; translates at the boundary.
- **`GitStrategy`** — adapted from `markdown-mcp/src/markdown_vault_mcp/git.py`. Per-project working tree, commit-on-write with intent message, idle-debounced push timer, fetch+ff-only pull loop with rebase fallback, conflict-saved-as-`*.conflict-mcp-<ts>.sdoc` files, token auth via `GIT_ASKPASS`, managed-mode startup clone validated against `repo_url`.

### 3.2 Deployment modes

Same code path; deployment behaviour driven by config flags:

| Concern | Mode S (stdio + project-pinned) | Mode H (HTTP + multi-project) |
|---|---|---|
| Transport | stdio | streamable HTTP |
| Auth | none | none / Bearer / OIDC (deployment choice) |
| Authorization (ACL) | n/a | optional, off by default |
| `REQENG_MCP_SPEC_ROOT` | parent dir of one project subtree | parent dir of many project subtrees |
| `REQENG_MCP_DEFAULT_PROJECT` | set (pin) — `project_id` arg optional | unset — `project_id` arg required |
| `REQENG_MCP_AUTOCOMMIT` | default `false` (user-driven git) | default `true` (server-owned working tree) |
| `REQENG_MCP_GIT_PUSH_DELAY_S` | default `0` (no auto-push) | default `30` (idle-debounced) |
| Pull loop | off | on (configurable interval) |
| Project lifecycle | manual subdir layout | `create_project` / `archive_project` tools |

Auth choice is a deployment decision, not transport-determined. fastmcp-pvl-core's `build_auth` already returns `None` when no auth env vars are set; HTTP can run unauthenticated behind a VPN/mTLS gateway. The full deployment matrix is in Section 7.

### 3.3 Composition

```
make_server()
├── fastmcp_pvl_core: configure_logging_from_env, build_auth, wire_middleware_stack
├── SpecStore (FileSpecStore root=<spec_root>)
├── StrictDocBackend (per-project, lazy, owns TraceabilityIndex cache)
├── GitStrategy (per-project, lazy on first write)
├── AuthorizationMiddleware (optional, when config.acl_enabled — see Section 7)
├── register_tools / register_resources / register_prompts / register_apps
└── register_file_exchange (existing, for export downloads)
```

### 3.4 Key invariants

- Tools never touch the file system or git directly; all I/O routes through `SpecStore` + `StrictDocBackend` + `GitStrategy`.
- Every successful write commits; every commit message is the agent's `intent` argument verbatim. Failed writes leave no trace (validate → write → commit pipeline; if validation fails, no write, no commit).
- Reads are always available (subject to ACL when enabled); writes go through validate → write → commit → schedule-push.

## 4. Data model and grammar

### 4.1 Approach: minimalist canonical default, per-project extension

The default grammar mirrors **StrictDoc's own L2 dogfooded grammar** (from `docs/strictdoc_21_L2_StrictDoc_Requirements.sdoc`), which itself reflects canonical RE practice per ISO/IEC/IEEE 29148:2018. Three node types: `SECTION` (composite, narrative), `TEXT` (free prose between requirements), `REQUIREMENT` (the normative nodes). REQUIREMENT fields: `MID`, `UID`, `STATUS`, `TITLE`, `STATEMENT`, `RATIONALE`, `COMMENT` — all optional. Relations: `Parent` and `File`, no roles pre-declared.

Domain-specific node types (FAILURE_MODE, CONTRACT, NOTE-with-kind enums, ASIL-classified safety requirements, etc.) are **not** in the default. They are project-level grammar extensions. The substrate's value is the MCP surface and authoring loop, not a built-in vocabulary; projects extend at will.

Sources for the canonical grounding:
- [StrictDoc dogfooded grammar (`strictdoc_21_L2_StrictDoc_Requirements.sdoc`)](https://github.com/strictdoc-project/strictdoc/blob/main/docs/strictdoc_21_L2_StrictDoc_Requirements.sdoc)
- [StrictDoc user guide — custom grammar / roles / `.sgra` import](https://github.com/strictdoc-project/strictdoc/blob/main/docs/sphinx/source/strictdoc_01_user_guide.md)
- [ISO/IEC/IEEE 29148:2018 — Requirements engineering](https://standards.ieee.org/ieee/29148/6937/)

### 4.2 Default grammar (`reqeng_mcp/grammars/default.sgra`)

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

`MID` is StrictDoc's machine-stable internal ID, distinct from the user-facing `UID`. Substrate auto-assigns on create.

### 4.3 Default grammar replacement (per server instance)

Resolution order at project load:

1. Project documents declare an inline `[GRAMMAR]` block — use it (StrictDoc-native).
2. Project ships `<project_id>/grammar.sgra` — substrate auto-imports it.
3. `REQENG_MCP_DEFAULT_GRAMMAR_PATH` env var is set — substrate uses that file as the project's default at first load.
4. None of the above — substrate uses the bundled `reqeng_mcp/grammars/default.sgra`.

Docker pattern: mount custom default at `/etc/reqeng-mcp/default.sgra`, set `REQENG_MCP_DEFAULT_GRAMMAR_PATH=/etc/reqeng-mcp/default.sgra`. Projects start with that as their default; can still override per-project.

### 4.4 Per-project grammar extension

Projects add roles to existing relations or new node types via per-project `.sgra` imports. Examples:

- **Roles on Parent relations:** `Refines`, `Verifies`, `Implements`, `Satisfies` — canonical RE traceability roles per IEEE 29148.
- **New node types:** `SAFETY_REQUIREMENT` with `ASIL: SingleChoice(A, B, C, D)` and `VERIFICATION: MultipleChoice(Review, Analysis, Inspection, Test)` for automotive projects.

The substrate treats every project's grammar as data — no code changes required for project-specific types.

### 4.5 Audit metadata is git, not fields

Per-node "created_at / last_modified_at / who / why" is **not** declared in the grammar. Every write commits with the agent's `intent` argument as the commit message; committer identity = authenticated subject (Mode H) or `local` (Mode S). The audit log is `git log --follow <node-file>` exposed by `get_node_history(uid)`. This keeps grammar declarations clean — projects don't redeclare audit fields.

### 4.6 Project-level config — `strictdoc_config.py`

Each `<spec_root>/<project_id>/strictdoc_config.py` is a Python file (post-2025-Q4 StrictDoc migration; TOML deprecated, removal expected 2026-Q1). `create_project` generates a minimal default; users can edit to inject Python hooks into StrictDoc's traceability pipeline if needed.

## 5. StrictDoc backend

### 5.1 The single boundary

All StrictDoc internal-API touch points live in one class: `reqeng_mcp.strictdoc_backend.StrictDocBackend`. Nothing else in the codebase imports from `strictdoc.*`. When upstream churns its internals, churn is contained.

The class exposes our-shape types — `Document`, `TraceabilityIndex`, `Grammar`, `ValidationFinding` are reqeng-mcp dataclasses, not re-exports.

### 5.2 Internal touch points

Verified against current StrictDoc main ([deepwiki query](https://deepwiki.com/search/list-the-actual-python-class-e_74de9af3-6b79-45d4-8b86-df3ba39257c4); StrictDoc explicitly notes "no formally documented public Python API, no guarantee of stability"):

| Operation | Internal entry point |
|---|---|
| Parse `.sdoc` | `strictdoc.backend.sdoc.reader.SDReader.read_from_file(path, project_config)` |
| Serialise `.sdoc` | `strictdoc.backend.sdoc.writer.SDWriter.write_to_file(doc)` / `.write(doc)` |
| Project-wide index | `strictdoc.core.traceability_index_builder.TraceabilityIndexBuilder.create(project_config, parallelizer)` |
| Validate explicitly | `strictdoc.backend.sdoc.validations.sdoc_validator.SDocValidator` (transitive via index) |
| HTML export | `strictdoc.export.html.html_generator.HTMLGenerator` |
| ReqIF export | `strictdoc.backend.reqif.reqif_export.ReqIFExport` |
| Project config | `strictdoc.core.project_config.ProjectConfig` |
| Parallelism | `strictdoc.helpers.parallelizer.Parallelizer` (process singleton) |

Reference for embedding patterns: `strictdoc/server/routers/main_router.py` (their own web server's use of these classes).

### 5.3 Pinning policy

`pyproject.toml`: `strictdoc==<X.Y.Z>` (exact pin, no ranges, no carets). New StrictDoc release → file an issue, bump in a branch, run the `strictdoc_pin/` test lane (Section 9.6), merge if green. Bumps are deliberate; no automated dependency updates for this single dep.

### 5.4 Per-project caching and concurrency

- **One `StrictDocBackend` per project**, lazily instantiated, held in an LRU dict on `SpecStore`.
- **Per-project `asyncio.Lock`**: reads share the lock; writes acquire exclusively. Cross-project: no contention.
- **`Parallelizer` is process-wide singleton.**
- **Git lock** orthogonal to backend lock. Order: validate → write document file → release backend lock → git stage+commit (under git lock) → schedule push.

### 5.5 Subprocess CLI fallback contract

If internal-API churn becomes painful, the wrapper's interface (async-shaped, our-typed dataclasses out) leaves room to swap to subprocess `strictdoc` invocations. Cost: 50–200 ms per call; we stay in-process by default. The CLI fallback is the escape hatch, not the primary path; not implemented Phase 1.

### 5.6 Wrapper failure modes

| Cause | Wrapped as | Surfaced as |
|---|---|---|
| Parse error | `SpecParseError` | Validation finding (file path + line) |
| Missing project root | `ProjectNotFoundError` | Tool error naming available projects |
| Schema mismatch on write | `GrammarViolationError` | Tool-level validation failure |
| StrictDoc internal exception | `BackendError` | Generic 500 + `ERROR` log + issue trigger |

## 6. MCP surface

### 6.1 Tools for the LLM, resources for the user

Per the MCP control hierarchy ([spec, 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/server)):

| Primitive | Control | Audience |
|---|---|---|
| Tools | Model-controlled | LLM invokes during agent loop |
| Resources | Application-controlled | Client/host attaches; user may browse |
| Prompts | User-controlled | User invokes (via slash command, picker, or client auto-injection) |

The LLM's authoring surface is **all tools**. Resources are a parallel, thinner surface for host/user-driven attachment. Prompts are user-controlled templates that may be auto-injected by smart clients.

### 6.2 LLM-facing read tools

| Tool | Purpose |
|---|---|
| `list_projects()` | List of projects accessible to the caller (ACL-filtered when enabled). |
| `get_project_status(project_id?)` | Counts per node-type, last-commit metadata, integrity-cache freshness, push-pending. |
| `get_grammar(project_id?)` | Effective `.sgra` content. Agent calls once per session to learn TAGs and ROLEs. |
| `list_documents(project_id?)` | Index of `.sdoc` documents in the project. |
| `get_document(project_id?, doc)` | Full document text. |
| `list_nodes(project_id?, type?, status?, tag?, document?, limit?, cursor?)` | Paginated, filtered. |
| `get_node(project_id?, uid, include_relations=False)` | Single node, all fields, optional relations. |
| `get_field(project_id?, uid, field)` | Single-field read — narrow-read-before-narrow-write path. |
| `list_relations(project_id?, uid, direction, role?)` | Inbound or outbound, role-filtered. |
| `search_nodes(project_id?, query, type?, fields?, limit?, cursor?)` | Full-text, wraps StrictDoc search. |
| `traceability_matrix(project_id?, source_type?, target_type?, role?)` | Tabular relations export. |
| `dependents_of(project_id?, uid, depth=1, role?)` | Inbound graph walk. |
| `dependencies_of(project_id?, uid, depth=1, role?)` | Outbound graph walk. |
| `get_node_history(project_id?, uid, since?, until?, limit?)` | git log scoped to the node's file. |
| `get_node_diff(project_id?, uid, ref_or_since, until?, per_commit=False)` | Unified diff. |

### 6.3 LLM-facing write tools

Every write takes `intent: str` — the agent's one-sentence reason for the change in the user's framing. Becomes the git commit message verbatim. Validated non-empty + length ≥ 10 + normalised. Substrate refuses writes with empty/placeholder intent.

| Tool | Purpose |
|---|---|
| `create_node(project_id?, type, fields, parent_uid?, document?, intent)` | Create node. Returns `{uid, mid}`. |
| `set_fields(project_id?, uid, updates, intent)` | `updates: {field: value | None}`. None clears optional fields. |
| `add_relation(project_id?, source_uid, type, target, role?, intent)` | Add `Parent` (target=UID) or `File` (target=path), optional role. |
| `remove_relation(project_id?, source_uid, type, target, role?, intent)` | Remove matching relation. |
| `move_node(project_id?, uid, new_parent_uid?, new_document?, intent)` | Relocate without changing fields. |
| `rename_uid(project_id?, old_uid, new_uid, intent)` | Rewrite UID; MID stable; inbound `Parent` references rewritten transactionally. |
| `delete_node(project_id?, uid, cascade=False, intent)` | Hard delete. Refused if inbound relations and `cascade=False`. With `cascade=True`, dependents surfaced — agent calls per-dependent. No implicit recursion. |

No `upsert_node` — conflating create vs edit is a foot-gun for the LLM.

### 6.4 Project lifecycle

| Tool | Purpose |
|---|---|
| `create_project(project_id, remote_url?, default_grammar_source?, intent)` | Create subtree, init git, generate `strictdoc_config.py`, link/copy effective default grammar. If `remote_url`, configure origin and clone (managed-mode pattern). |
| `archive_project(project_id, intent)` | Move to `<spec_root>/archived/<project_id>/`; project becomes read-only. |

### 6.5 Validation, integrity, export

| Tool | Purpose |
|---|---|
| `validate_project(project_id?, scope?)` | StrictDoc native validation — UID uniqueness, ref resolution, grammar conformance. |
| `check_integrity(project_id?)` | Currently `== validate_project()`. Reserved seam for future invariants. |
| `export_html(project_id?)` | StrictDoc HTML export → `file_ref` via existing file-exchange middleware (`server.py:103`). |
| `export_reqif(project_id?)` | StrictDoc ReqIF export → `file_ref`. |
| `export_excel(project_id?)` | StrictDoc Excel export → `file_ref`. |
| `export_markdown(project_id?)` | StrictDoc Markdown export → `file_ref`. |

### 6.6 Host/user-facing resources

A user on claude.ai with this MCP server connected sees a browsable project tree they can attach to their conversation. The LLM does not read these — they exist for user-driven context attachment.

| URI | Returns |
|---|---|
| `spec://projects` | List of accessible projects (ACL-filtered) |
| `spec://{project}/documents` | List of `.sdoc` documents |
| `spec://{project}/documents/{doc}` | Full `.sdoc` text |
| `spec://{project}/grammar` | Effective `.sgra` |
| `spec://{project}/nodes/{uid}` | Single-node `.sdoc` fragment |

Resources are ACL-checked the same way as tools.

### 6.7 Cross-cutting conventions

- **`project_id` resolution.** Optional in tool schemas; defaulted from `REQENG_MCP_DEFAULT_PROJECT` (Mode S). Unresolved → tool error names available projects.
- **Pagination.** `{items, next_cursor}`, opaque cursor, `limit` honoured up to a fixed cap (~100).
- **Annotations.** Read tools `readOnlyHint: True`. Idempotent edits `idempotentHint: True`. `delete_node` / `archive_project` / `rename_uid` `destructiveHint: True`.
- **Errors.** `ErrorHandlingMiddleware` catches; validation failures return user-readable strings; authz failures explicit (subject + project + missing scope).

### 6.8 Out of the surface

- No `upsert_node`.
- No node-type-specific tools (`create_failure_mode` etc.) — generic by node type.
- No transaction tool — each write is its own intent-tagged commit; that *is* the audit trail.
- No subscriptions in Phase 1 (fastmcp resource updates wire on later for live-view consumers).

## 7. Authentication, authorization, and upstream split

### 7.1 Auth and ACL are separate concerns

| Layer | Concern | Surface |
|---|---|---|
| Authentication | Is this connection allowed? Who is on the other end? | OIDC / Bearer via existing `fastmcp_pvl_core.build_auth(config.server)`. No new auth code in this repo. |
| Authorization (ACL) | Given an authenticated caller, which projects/operations may they touch? | New optional `AuthorizationMiddleware` (upstream — see Section 7.3). Off by default. |

The user's stated pattern: OIDC/Bearer has only ever been used for connection-level auth, never for fine-grained per-project access control. ACL is a separate concept introduced here; `subject` happens to be the same value at the decision point.

### 7.2 Auth modes and subject extraction

| Auth mode | Subject extraction | Suitable for ACL? |
|---|---|---|
| `none` | Synthetic `local` | Trivially (single subject) |
| Bearer (single token, current) | Default constant `bearer-anon` | Coarse: all-or-nothing per-token |
| Bearer (mapped, via `FASTMCP_BEARER_TOKENS_FILE`) | Mapped value from token file | Yes: per-user attribution |
| OIDC | `sub` claim | Yes: per-user attribution |

Bearer-mapped requires `pvliesdonk/fastmcp-pvl-core#35` — see Section 7.3.

### 7.3 Upstream split — what belongs in pvl-core, what in the template, what in this repo

Walking through the components, separating reusable from domain-specific:

| Component | Where | Issue |
|---|---|---|
| Subject extraction across auth modes | **fastmcp-pvl-core** | [pvl-core #36](https://github.com/pvliesdonk/fastmcp-pvl-core/issues/36) |
| Bearer token → subject mapping | **fastmcp-pvl-core** | [pvl-core #35](https://github.com/pvliesdonk/fastmcp-pvl-core/issues/35) |
| `AuthorizationMiddleware`, `TenantResolver` protocol, ACL TOML loader, `requires_scope` annotation, `register_acl_admin_tools(mcp)` helper, three-scope vocabulary | **fastmcp-pvl-core** | [pvl-core #37](https://github.com/pvliesdonk/fastmcp-pvl-core/issues/37) |
| Commented `acl_enabled` field stub in `config.py.jinja` | **fastmcp-server-template** | [template #94](https://github.com/pvliesdonk/fastmcp-server-template/issues/94) |
| Commented authorization wiring stanza in `server.py.jinja` | **fastmcp-server-template** | [template #95](https://github.com/pvliesdonk/fastmcp-server-template/issues/95) |
| README multi-tenant deployment section | **fastmcp-server-template** | [template #96](https://github.com/pvliesdonk/fastmcp-server-template/issues/96) |
| Domain `TenantResolver` impl ("project_id from `<spec_root>/<project_id>/`") | **reqeng-mcp** | (this repo, Phase 2) |
| ACL file path convention (`.reqeng-acl.toml` at `<spec_root>/`) | **reqeng-mcp** | (this repo, Phase 2) |
| Domain config flag `REQENG_MCP_ACL_ENABLED` | **reqeng-mcp** | (this repo, Phase 2) |

### 7.4 ACL design (when enabled)

- Three flat scopes: `read` ⊂ `write` ⊂ `admin`.
- Per-tool `requires_scope` annotation drives the middleware check.
- Single TOML file at `<spec_root>/.reqeng-acl.toml` (path overridable). Schema:
  ```toml
  [subjects."user:peter@liesdonk.nl"]
  projects = { "*" = ["read", "write", "admin"] }

  [subjects."service:ci-bot"]
  projects = { "*" = ["read"] }

  [default]
  projects = {}  # default-deny
  ```
- Wildcard `*` on the project side; not on the subject side.
- Reloaded on each request (cheap; file-watch out of scope).
- Schema-validated on load; bad ACL fails the request with a clear error rather than silent denial.

### 7.5 ACL administration tools (admin scope only)

| Tool | Purpose |
|---|---|
| `acl_list_subjects()` | Returns ACL filtered to projects the caller admins. |
| `acl_grant(subject, project_id, scopes, intent)` | Adds/extends grants. |
| `acl_revoke(subject, project_id, scopes, intent)` | Removes grants. |
| `acl_set_default(scopes, intent)` | Changes the `[default]`. |

ACL writes are intent-tagged like any other write and committed to a special `acl/` git branch on the spec store.

### 7.6 Deployment matrix

| Deployment | Transport | Auth | Subject source | ACL | Use case |
|---|---|---|---|---|---|
| Local coding agent | stdio | none | `local` | off | Mode S baseline |
| Hosted private | HTTP | none | `local` | off | Behind VPN/mTLS gateway |
| Shared bearer (single) | HTTP | Bearer single | `bearer-anon` | off | One shared secret |
| Shared bearer (mapped) | HTTP | Bearer file | mapped | on | Per-user via mapped tokens |
| Hosted multi-user | HTTP | OIDC | `sub` claim | on | Standard production with IdP |

Operator picks a row at deploy time via env vars. No code changes.

### 7.7 Mode S behaviour

When `auth_mode == "none"`, the `AuthorizationMiddleware` short-circuits — every request is authorised as if by a synthetic `local` subject with `admin` on every project. Documented at startup `INFO`:

```
auth=none — all requests authorised as 'local' subject (Mode S behaviour)
```

When `auth=none` and ACL is enabled (rarely intentional), startup `WARNING` surfaces the combination.

## 8. Authoring discipline — server instructions, tool docstrings, prompts (skill nice-to-have)

### 8.1 Channels and audiences

The discipline must reach the model through channels every spec-compliant client supports, because most clients connect over HTTP and have no skill ecosystem.

| Channel | Carries | Always-on across clients? |
|---|---|---|
| Server `instructions` blob (handshake) | One-paragraph baseline: server purpose + named loop steps + prompt-name pointers | Yes |
| Tool docstrings | Per-tool spec + per-tool reminder | Yes (when tools listed) |
| MCP prompts (`register_prompts(mcp)`) | Full loop + worked examples + session-opener templates | Client-mediated: may auto-inject, may surface for user to pick, may be reachable via `PromptsAsTools` for tool-only clients |
| Optional Claude Code skill | Same content as `authoring-loop` prompt | Only in CC plugin installs |

The three-actor model: model can autonomously invoke tools, but cannot pull prompts/resources/skills — the **client** mediates. Smart clients may auto-inject prompts; less-smart clients require user action; tool-only clients need `PromptsAsTools` fallback. Designing for the floor (instructions + tool descriptions guarantee reach) gives smart clients amplification beyond.

### 8.2 The canonical loop

Six steps, lives in `src/reqeng_mcp/prompt_content/authoring_loop.md`:

1. **Orient** — `get_grammar`, `get_project_status` once per project per session.
2. **Locate** — `search_nodes` / `list_nodes` to find UIDs.
3. **Read narrow** — `get_field` for one field; `get_node` only when multiple needed.
4. **Edit narrow with intent** — `set_fields` / `add_relation` / etc. `intent` is user's "why" in their framing. One logical change per call.
5. **Trace dependents** — after substantive writes, `dependents_of(uid)`; consider each, write per-dependent intent if updates needed; "no update needed" is a deliberate decision.
6. **Integrity check at logical boundary** — `check_integrity` when the user request is satisfied, not after every write.

### 8.3 Anti-patterns (named in the prompt body)

| Anti-pattern | Correct move |
|---|---|
| Whole-document rewrites | Per-node edits via `set_fields` / `add_relation` |
| Placeholder intent ("updated", "see above") | Articulate user's "why"; if you can't, you're not ready to write |
| Blind dependent cascading | Walk dependents, decide per-node, write each with its own intent |
| Confusing create vs edit (the `upsert` mindset) | Call `get_node(uid)` first if uncertain |
| Skipping orient on a new-to-you project | One `get_grammar` call. Done. |
| Calling `validate_project` after every write | Only `check_integrity` at logical boundaries |

### 8.4 Server `instructions` blob (always loaded)

Composed via `build_instructions()` (`server.py:84`). The `domain_line`, ~80 words:

> MCP server for requirements engineering workflows (StrictDoc-backed, multi-project, intent-tagged authoring). **Authoring loop:** orient → locate → read narrow → edit narrow with user-framed intent → trace dependents → integrity-check at logical boundary. Every write tool requires a non-placeholder `intent` argument that becomes the git commit message. Invoke prompt `authoring-loop` for the full discipline; `start-session` for project orientation; `worked-single-rule` / `worked-audit-pass` for templated walkthroughs.

### 8.5 Tool docstrings (per-tool reminders)

Every write tool's docstring includes a 1–2 sentence reminder citing the loop step it serves and naming relevant prompts. Example for `set_fields`:

```
Update one or more fields on an existing node, atomically.

Loop step: 'edit narrow with intent'. Read the field(s) first via
get_field/get_node if the current values are not in your context.

`intent` MUST be the user's "why" in their framing. It becomes the
git commit message and is the load-bearing audit record.

If the user wants the full authoring discipline, suggest prompt
`authoring-loop`; for project orientation, `start-session`.
```

The "suggest the prompt" line is doing real work: the agent learns prompt names from tool descriptions even though it cannot invoke prompts itself; it can route the user there.

### 8.6 Prompts

Four prompts registered, bodies in `src/reqeng_mcp/prompt_content/`:

| Prompt | Parameters | Body | Use |
|---|---|---|---|
| `authoring-loop` | none | `authoring_loop.md` | User invokes; agent has the full loop in context |
| `start-session` | `project_id` (optional in Mode S) | `session_opener.md` (templated) | Calls `get_grammar` + `get_project_status`; primes orientation |
| `worked-single-rule` | `project_id`, `subject` | `worked_single_rule.md` (templated) | "Add a rule about X" walkthrough |
| `worked-audit-pass` | `project_id`, `scope`, `concern` | `worked_audit_pass.md` (templated) | Cross-cutting refinement walkthrough |

`PromptsAsTools` transform wired so tool-only clients can reach prompts via `list_prompts` / `get_prompt` tools.

### 8.7 Optional skill (Claude Code only)

If shipped: `.claude-plugin/plugin/skills/reqeng-authoring/SKILL.md`. Body = `prompt_content/authoring_loop.md`, copied at build time. Same content as the prompt; auto-triggers in Claude Code; no value beyond convenience.

### 8.8 Drift prevention

Test `tests/drift/test_discipline_consistency.py`:

- Loads `prompt_content/authoring_loop.md`; parses out the 6 step headers.
- Asserts server `instructions` mentions every step name and prompt name.
- Asserts every write tool's docstring cites at least one named step and at least one prompt name.
- Asserts the registered prompt `authoring-loop` round-trips the markdown body.
- (When skill artifact exists) asserts skill body == prompt body.

## 9. Testing approach

### 9.1 Layout

```
tests/
  conftest.py
  fixtures/
    grammars/{default.sgra, with_safety_extension.sgra, malformed.sgra}
    projects/{minimal/, multi-doc/, with-acl/}
    bearer-tokens.toml
    acls/{simple.toml, wildcard.toml, malformed.toml}
  unit/
  integration/
  contract/
  drift/
  strictdoc_pin/
```

### 9.2 Unit tests

Per-component isolation; tmp project trees per test; fast (< 5s suite). Notable areas:

- `test_intent_validation.py` — load-bearing pitch enforcement: empty/whitespace/placeholder rejection, length floor, multi-line normalisation.
- `test_grammar_resolution.py` — verifies all four resolution paths (inline → project `.sgra` → env-default → bundled).

### 9.3 Integration tests

Black-box exercise of the substrate from the MCP layer down via FastMCP's in-process client.

`test_authoring_loop.py::test_full_loop` — keystone test walking the canonical 6-step loop: get_grammar, list_nodes, create_node with intent, get_node, dependents_of, check_integrity. Asserts: tool returns, fixture state, git log content, committer identity.

Failure variants: empty intent → tool error + clean working tree; malformed field type → `GrammarViolationError`; broken ref → resolution error.

### 9.4 Contract tests

`test_tool_schemas.py` — every write tool has `intent: str` last-position required; read tools have `readOnlyHint`; destructive tools have `destructiveHint`; every tool has docstring length ≥ 100.

`test_resource_uris.py` — every documented URI template resolves on a fixture project; ACL-denied URIs absent from `resources/list` for unprivileged subjects (when ACL impl lands).

### 9.5 End-to-end "agent loop" test

`test_worked_single_rule_e2e.py` — scripted-agent driver replays the `worked-single-rule` prompt narrative verbatim. Asserts substrate state matches expected fixture, intent-tagged commit log matches expected sequence. Substrate test, not LLM test.

### 9.6 StrictDoc pin validation lane

`test_strictdoc_internals.py` — one test per internal API touch point from Section 5.2. Runs on every PR. Pin-bump PRs use this lane to detect breakage before broader integration.

### 9.7 Drift-prevention tests

Per Section 8.8.

### 9.8 Auth/ACL tests (Phase 2 onward)

`test_acl_default_deny.py`, `test_acl_wildcard.py`, `test_acl_scope_ordering.py`, `test_acl_admin_tools.py`, `test_acl_disabled.py`, `test_bearer_subject_mapping.py`.

### 9.9 CI gates (per CLAUDE.md)

- `uv run pytest -x -q`
- `uv run pytest --cov=src/reqeng_mcp --cov-report=term-missing --cov-fail-under=80` (diff-coverage)
- `uv run mypy src/ tests/`
- `uv run ruff check --fix .` then `uv run ruff format .` then `uv run ruff format --check .`

Pre-commit hook runs lint + mypy + drift tests as a fast pre-push lane.

### 9.10 CLI fallback validation

Opt-in via `REQENG_TEST_USE_CLI=1`; nightly CI lane swaps `StrictDocBackend` for a CLI-shelling variant. Validates the fallback contract from Section 5.5.

## 10. Phasing and tracking

Phases are temporal delivery slices, **not scope reductions**. Everything in Sections 1–9 is in scope from day one.

### 10.1 Phase summary

| Phase | Delivers | Depends on | Acceptance |
|---|---|---|---|
| **1 — Read substrate** | `SpecStore`, `StrictDocBackend`, default grammar + override resolution, all read tools, project lifecycle, validation, exports, server `instructions` + read-tool docstrings, fixture project, integration suite | None outside this repo | Read-only path of `test_authoring_loop.py` green; CLAUDE.md gates green |
| **2 — Write substrate + ACL** | All write tools with `intent`-validation, `GitStrategy` integration, conflict semantics, `check_integrity` seam, `AuthorizationMiddleware` wired, bearer-mapping support, ACL admin tools | pvl-core #35, #36, #37 | Full loop test green; ACL tests green; CLAUDE.md gates green |
| **3 — Authoring channels + worked synthetic** | All MCP prompts, `prompt_content/*.md`, optional CC skill, drift tests, end-to-end synthetic-spec walkthrough | Phase 2 | Drift tests green; worked-single-rule e2e test green; CLAUDE.md gates green |

### 10.2 Tracking issues to file in this repo (after design approval)

| Title | Phase | Depends on |
|---|---|---|
| epic: Phase 1 — read-only substrate (per design doc Section 10) | 1 | — |
| epic: Phase 2 — write substrate + ACL (per design doc Section 10) | 2 | epic 1; pvl-core #35, #36, #37 |
| epic: Phase 3 — authoring channels + worked synthetic (per design doc Section 10) | 3 | epic 2 |
| future: host StrictDoc webapp under the same HTTP server (`/mcp/` + `/ui/<project>/`) | future | epic 1 |

Per-PR sub-issues created during the writing-plans step from each epic, capped at ≤10 per epic per CLAUDE.md.

### 10.3 Upstream dependencies and status

- [pvl-core #35](https://github.com/pvliesdonk/fastmcp-pvl-core/issues/35) — bearer subject mapping (filed)
- [pvl-core #36](https://github.com/pvliesdonk/fastmcp-pvl-core/issues/36) — `get_subject(request)` helper (filed)
- [pvl-core #37](https://github.com/pvliesdonk/fastmcp-pvl-core/issues/37) — `authorization` submodule (filed)
- [template #94](https://github.com/pvliesdonk/fastmcp-server-template/issues/94), [#95](https://github.com/pvliesdonk/fastmcp-server-template/issues/95), [#96](https://github.com/pvliesdonk/fastmcp-server-template/issues/96) — scaffold stubs, depend on pvl-core #37 (filed)

Phase 1 has no upstream dependency. Phase 2 is gated by pvl-core #35 + #37 landing in a release; #36 may be folded into #37.

## 11. References

- [MCP specification — control hierarchy (server overview)](https://modelcontextprotocol.io/specification/2025-11-25/server)
- [MCP specification — prompts (user-controlled)](https://modelcontextprotocol.io/specification/2025-11-25/server/prompts)
- [MCP specification — lifecycle (instructions field)](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [FastMCP — server instructions](https://gofastmcp.com/servers/server)
- [FastMCP — `PromptsAsTools` transform](https://gofastmcp.com/servers/transforms/prompts-as-tools)
- [StrictDoc dogfooded grammar](https://github.com/strictdoc-project/strictdoc/blob/main/docs/strictdoc_21_L2_StrictDoc_Requirements.sdoc)
- [StrictDoc user guide](https://github.com/strictdoc-project/strictdoc/blob/main/docs/sphinx/source/strictdoc_01_user_guide.md)
- [ISO/IEC/IEEE 29148:2018 — Requirements engineering](https://standards.ieee.org/ieee/29148/6937/)
- [markdown-mcp `git.py`](https://github.com/pvliesdonk/markdown-mcp/blob/main/src/markdown_vault_mcp/git.py) — pattern source for `GitStrategy`
