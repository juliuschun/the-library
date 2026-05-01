---
name: library
description: |
  Mandatory entry point for the entire skill lifecycle — create, register, deploy, push, and manage private skills/agents/prompts. Use whenever the user wants to make a new skill, register an existing one, deploy skills to managed customer VMs, push skills back to GitHub, or browse the catalog. Triggers on `/library`, "스킬 만들어", "create skill", "new skill", "스킬 등록", "스킬 배포", "register skill", "publish skill", "스킬 카탈로그", "스킬 마켓".
  IMPORTANT: New skill creation MUST go through `/library create` — `skill-architect` is a sub-tool called internally and should not be invoked directly for net-new skills.
argument-hint: "[create|add|use|publish|push|remove|list|sync|search] [name|details]"
---

# The Library — Mandatory Entry Point for Skill Lifecycle

This skill is **the single entry point** for everything related to skills/agents/prompts on this server. Per the decision in `~/workspace/decisions/2026-05-01-skill-lifecycle-mandatory-entry-point.md`, every new skill creation, catalog registration, and customer-VM deployment must flow through `/library` commands. Direct invocation of `skill-architect` is reserved for validation/audit/distill on already-installed skills.

A meta-skill for private-first distribution of agentics (skills, agents, and prompts) across agents, devices, and teams.

## Variables

> Update these after forking and cloning the library repo.

- **LIBRARY_REPO_URL**: `<your forked repo url>`
- **LIBRARY_YAML_PATH**: `~/.claude/skills/library/library.yaml`
- **LIBRARY_SKILL_DIR**: `~/.claude/skills/library/`

## How It Works

The Library is a catalog of references to your agentics. The `library.yaml` file points to where skills, agents, and prompts live (local filesystem or GitHub repos). Nothing is fetched until you ask for it.

**The `library.yaml` is a catalog, not a manifest.** Entries define what's *available* — not what gets installed. You pull specific items on demand with `/library use <name>`.

## Commands

스킬 라이프사이클 (생성 → 운영 → 정제 → 배포) 모두 이 한 스킬 안에서 명령으로 노출됨.

### Lifecycle (저자 + 정제)

| Command                                  | Purpose                                                                |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| `/library create <name> [type] [tags]`   | **Create a new skill end-to-end** (5-phase: Genesis → Scaffold → Smoke test → Validate → Register) |
| `/library validate <path> [--fix]`       | Validate a single existing skill (frontmatter + structure + best practice) |
| `/library audit [path]`                  | Validate all SKILL.md in a directory (default `~/.claude/skills/`)     |
| `/library distill <path> [--apply]`      | Semantic analysis + compress bloated SKILL.md, move detail to reference |
| `/library refine <name>`                 | Iterative improvement after real use (4-phase: Observe → Diagnose → Apply → Verify) |

### Distribution (catalog + customer VMs)

| Command                                  | Purpose                                                                |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| `/library publish <profile\|customer>`   | **(operator host only)** Deploy registered skills to managed customer VMs |
| `/library install`                       | First-time setup on this device: fork, clone, configure                |
| `/library add <details>`                 | Register an existing skill (already on disk) into the catalog          |
| `/library use <name>`                    | Pull from external source (install or refresh)                         |
| `/library push <name>`                   | Push local changes back to source (GitHub backup)                      |
| `/library remove <name>`                 | Remove from catalog and optionally local                               |
| `/library list`                          | Show full catalog with install status                                  |
| `/library sync`                          | Re-pull all installed items from source                                |
| `/library search <keyword>`              | Find entries by keyword                                                |

### Host context (어디서 실행 중인지가 중요)

| 호스트 | library 의 역할 |
|---|---|
| **Operator host (본 서버, full 프로필)** | 모든 명령 사용 가능. customers 레지스트리·publish 도 여기서만 작동. 우리가 만든 스킬은 본 서버 → publish 로 customer VM 으로 전파. |
| **Managed customer VM** (e.g. okusystem) | lifecycle 명령 (`create / validate / audit / distill / refine`) + 카탈로그 관리 (`add / list / search / remove`) + 외부 pull (`use / push`) 사용 가능. **`publish` 비활성** (customers 정보 없음). 여기서 만든 스킬은 **그 VM 에만** 살고, 우리 publish 가 덮어쓰지 않음 (이름 충돌 없는 한). |
| **Standalone customer VM** | managed 와 동일하되, 우리가 publish 안 함. 자체 운영. |

자세한 정책: `cookbook/publish.md` 의 "Host context" 섹션, `cookbook/create.md` 의 "Customer host naming" 섹션.

## Cookbook

Each command has a detailed step-by-step guide. **Read the relevant cookbook file before executing a command.**

| Command  | Cookbook                                       | Use When                                                                                        |
| -------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| create   | [cookbook/create.md](cookbook/create.md)       | User wants a NEW skill (5-phase JTBD-driven workflow). Default for "스킬 만들어".                |
| validate | [cookbook/validate.md](cookbook/validate.md)   | Single-skill validation (called by create Phase 4, or directly on existing skills)              |
| audit    | [cookbook/audit.md](cookbook/audit.md)         | Directory-wide validation + catalog mismatch check                                              |
| distill  | [cookbook/distill.md](cookbook/distill.md)     | Skill bloat / trigger drift — analyze and compress                                              |
| refine   | [cookbook/refine.md](cookbook/refine.md)       | After 1-2 weeks of real use — iterative improvement                                             |
| publish  | [cookbook/publish.md](cookbook/publish.md)     | User wants registered skills pushed out to managed customer VMs                                  |
| install  | [cookbook/install.md](cookbook/install.md)     | First-time setup on a new device                                                                 |
| add      | [cookbook/add.md](cookbook/add.md)             | User wants to register a skill that already exists on disk (no scaffold needed)                  |
| use      | [cookbook/use.md](cookbook/use.md)             | User wants to pull or refresh a skill from the catalog                                           |
| push     | [cookbook/push.md](cookbook/push.md)           | User improved a skill locally and wants to update the upstream GitHub source                     |
| remove   | [cookbook/remove.md](cookbook/remove.md)       | User wants to remove an entry from the catalog                                                   |
| list     | [cookbook/list.md](cookbook/list.md)           | User wants to see what's available and what's installed                                          |
| sync     | [cookbook/sync.md](cookbook/sync.md)           | User wants to refresh all installed items at once                                                |
| search   | [cookbook/search.md](cookbook/search.md)       | User is looking for a skill but doesn't know the exact name                                      |

**When a user invokes a `/library` command, read the matching cookbook file first, then execute the steps.**

## Reference (skill spec + validation)

스킬 자체의 형식·검증·테스트 reference. `cookbook/create.md` 와 `cookbook/validate.md` 가 이 파일들을 참조함.

| File | Content |
|---|---|
| `reference/skill-spec.md` | Frontmatter spec, structure conventions, allowed-tools, MCP integration |
| `reference/skill-templates.md` | Type별 (reference / task / file-writing / multi-agent) 본문 템플릿 |
| `reference/skill-validation.md` | Validation 체크리스트 (ERROR / WARN / INFO 분류) |
| `reference/skill-testing.md` | TDD-style trigger probes + JTBD test pack 패턴 |
| `reference/skill-classification.md` | 스킬 type 분류 가이드 (어떤 type 으로 만들지) |

## Lifecycle Flow (mandatory entry point)

```
"스킬 만들어"      →  /library create   (5-phase: JTBD → scaffold → smoke test → validate → register)
                                       └─ ask: "managed VMs 에 배포?" → /library publish managed
"이미 만든 스킬 등록"  →  /library add
"이상해, 고치자"    →  /library refine    (4-phase: observe → diagnose → apply → verify)
"본문 너무 두꺼움"  →  /library distill   (analyze, compress to reference)
"전체 점검"        →  /library audit
"검증 한 번"       →  /library validate
"고객 VM 배포"     →  /library publish <profile|customer>
"GitHub 백업"     →  /library push <name>
```

이 라이프사이클 전체가 **`/library` 한 스킬 안에서 끝남**. 별도 sub-skill 없음. 결정·이유: `~/workspace/decisions/2026-05-01-skill-lifecycle-mandatory-entry-point.md`.

## Source Format

The `source` field in `library.yaml` supports these formats (auto-detected):

- `/absolute/path/to/SKILL.md` — local filesystem
- `https://github.com/org/repo/blob/main/path/to/SKILL.md` — GitHub browser URL
- `https://raw.githubusercontent.com/org/repo/main/path/to/SKILL.md` — GitHub raw URL

Both GitHub URL formats are supported. Parse org, repo, branch, and file path from the URL structure. For private repos, use SSH or `GITHUB_TOKEN` for auth automatically.

**Important:** The source points to a specific file (SKILL.md, AGENT.md, or prompt file). We always pull the entire parent directory, not just the file.

## Source Parsing Rules

**Local paths** start with `/` or `~`:
- Use the path directly. Copy the parent directory of the referenced file.

**GitHub browser URLs** match `https://github.com/<org>/<repo>/blob/<branch>/<path>`:
- Parse: `org`, `repo`, `branch`, `file_path`
- Clone URL: `https://github.com/<org>/<repo>.git`
- File location within repo: `<path>`

**GitHub raw URLs** match `https://raw.githubusercontent.com/<org>/<repo>/<branch>/<path>`:
- Parse: `org`, `repo`, `branch`, `file_path`
- Clone URL: `https://github.com/<org>/<repo>.git`
- File location within repo: `<path>`

## GitHub Workflow

When working with GitHub sources, prefer `gh api` for accessing single files (e.g., reading a SKILL.md to check metadata). For pulling entire skill directories, clone into a temp dir per the steps below.

**Fetching (use):**
1. Clone the repo with `git clone --depth 1 <clone_url>` into a temporary directory
2. Navigate to the parent directory of the referenced file
3. Copy that entire directory to the target local directory
4. The temporary directory is cleaned up automatically

**Pushing (push):**
1. Clone the repo with `git clone --depth 1 <clone_url>` into a temporary directory
2. Overwrite the skill directory in the clone with the local version
3. Stage only the relevant changes: `git add <skill_directory_path>`
4. Commit with message: `library: updated <skill name> <what changed>`
5. Push to remote
6. The temporary directory is cleaned up automatically

## Typed Dependencies

The `requires` field uses typed references to avoid ambiguity:
- `skill:name` — references a skill in the library catalog
- `agent:name` — references an agent in the library catalog
- `prompt:name` — references a prompt in the library catalog

When resolving dependencies: look up each reference in `library.yaml`, fetch all dependencies first (recursively), then fetch the requested item.

## Target Directories

By default, items are installed to the **default** directory from `library.yaml`:

```yaml
default_dirs:
    skills:
        - default: .claude/skills/
        - global: ~/.claude/skills/
    agents:
        - default: .claude/agents/
        - global: ~/.claude/agents/
    prompts:
        - default: .claude/commands/
        - global: ~/.claude/commands/
```

- If the user says "global" or "globally", use the `global` directory.
- If the user specifies a custom path, use that path.
- Otherwise, use the `default` directory.

## Library Repo Sync

The library skill itself lives in `<LIBRARY_SKILL_DIR>` as a cloned git repo. When running `add` (which modifies `library.yaml`), always:
1. `git pull` in the library directory first to get latest
2. Make the changes
3. `git add library.yaml && git commit && git push`

This keeps the catalog in sync across devices.

## Example Filled Library File

```yaml
default_dirs:
  skills:
    - default: .claude/skills/
    - global: ~/.claude/skills/
  agents:
    - default: .claude/agents/
    - global: ~/.claude/agents/
  prompts:
    - default: .claude/prompts/
    - global: ~/.claude/prompts/

library:
  skills:
    - name: firecrawl
      description: Scrape, crawl, and search websites using Firecrawl CLI
      source: /Users/me/projects/tools/skills/firecrawl/SKILL.md

    - name: meta-skill
      description: Creates new Agent Skills following best practices
      source: /Users/me/projects/tools/skills/meta-skill/SKILL.md

    - name: diagram-kroki
      description: Generate diagrams via Kroki HTTP API supporting 28+ languages
      source: https://github.com/myorg/private-skills/blob/main/skills/diagram-kroki/SKILL.md
      requires: [skill:firecrawl]

    - name: green-screen-captions
      description: Generate and burn AI-powered captions onto green screen videos
      source: https://raw.githubusercontent.com/myorg/video-tools/main/skills/green-screen-captions/SKILL.md
      requires: [agent:video-processor, prompt:caption-style]

  agents:
    - name: video-processor
      description: Processes video files with ffmpeg and whisper transcription
      source: /Users/me/projects/tools/agents/video-processor/AGENT.md

    - name: code-reviewer
      description: Reviews code for quality, security, and performance
      source: https://github.com/myorg/agent-configs/blob/main/agents/code-reviewer/AGENT.md

  prompts:
    - name: caption-style
      description: Style guide for generating video captions
      source: /Users/me/projects/content/prompts/caption-style.md

    - name: commit-message
      description: Standardized commit message format for all projects
      source: https://github.com/myorg/team-prompts/blob/main/prompts/commit-message.md
```
