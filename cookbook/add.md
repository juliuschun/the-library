# Add a New Entry to the Library

## Context
Register a new skill, agent, or prompt in the library catalog.

## Input
The user provides: name, description, source, and optionally type and dependencies.

## Steps

### 1. Sync the Library Repo
Pull the latest changes before modifying:
```bash
cd <LIBRARY_SKILL_DIR>
git pull
```

**⚠️ Working tree 검증 (2026-05-09 추가, 사고 사례 후)**: `git pull` 만으론 부족.
Multi-session 환경에서 *origin 은 최신* (`Already up to date.`) 이지만 working
tree 에 다른 세션의 unstaged 변경이 이미 떠있을 수 있음. 그 상태에서 `git
add library.yaml` 하면 의도와 무관한 변경이 함께 묶여 commit 됨.

```bash
# working tree 상태 확인
git status --short
# library.yaml 의 unstaged diff 정확히 보기
git diff library.yaml
```

다른 세션의 변경이 보이면:
- (a) 의도된 변경이면 → 사용자에게 보고하고 분리 commit 또는 자기 add 와 묶어 처리할지 결정 받음
- (b) 의미 불명이면 → 진행 중단, 사용자에게 우선순위 결정 요청
- 절대 silent 로 묶어 push 금지 — 한 번 push 하면 force-push 비용이 큼

### 2. Determine the Type
Figure out the type from the user's prompt or the source path:
- If the source path contains `SKILL.md` or user says "skill" → type is `skill`
- If the source path contains `AGENT.md` or user says "agent" → type is `agent`
- If user says "prompt" → type is `prompt`
- If ambiguous, ask the user

### 3. Validate the Source
- **Local path**: Verify the file exists at the given path
- **GitHub URL**: Verify the URL is well-formed (matches browser or raw URL patterns)
- Confirm the source points to a specific file, not a directory

### 4. Parse Dependencies
Detect dependencies by looking through the skill/agent/prompt files, format them as typed references:
- `skill:name`, `agent:name`, `prompt:name`
- Verify each dependency already exists in `library.yaml` if or warn the user
  - If they don't exist add them to `library.yaml` first. If those files have dependencies, add them recursively.
  - You can detect these sometimes by looking at the frontmatter, and then in the file content look for `/<prompt|agent|skill>:name` references. If you're not sure, ask the user the user if they have any dependencies.

### 5. Add the Entry to library.yaml
Read `library.yaml`, add the new entry under the correct section:

```yaml
# Under library.skills, library.agents, or library.prompts
- name: <name>
  description: <description>
  source: <source>
  requires: [<typed:refs>]  # omit if no dependencies
```

**YAML formatting rules:**
- 2-space indentation
- List items use `- ` prefix
- Properties are indented under the list item
- Keep entries alphabetically sorted by name within each section
- For skills reference the `.../<skill-name>/SKILL.md` file,
- For agents reference the `.../<agent name>.md` file,
- For prompts reference the `.../<prompt name>.md` file (installed to `.claude/commands/`),
- Remember we'll be adding a absolute path or a github url (https or ssh)

### 6. Commit and Push

**⚠️ Stage 후 final 검증 (2026-05-09 추가)**: `git add` 한 후 `git diff --cached`
로 정확히 의도한 변경만 staged 됐는지 한 번 더 확인. step 1 의 working tree
검증을 건너뛰었거나 그 사이 다른 세션이 변경을 추가했을 수 있음.

```bash
cd <LIBRARY_SKILL_DIR>
git add library.yaml
git diff --cached library.yaml   # ← staged diff 가 의도한 entry 추가만 인지 확인
```

`git diff --cached` 가 *예상보다 큰 변경* 이면 (예: insertions/deletions 수가
30 줄을 넘는데 entry 한 개 추가가 그 정도가 아닐 때) → step 1 의 working
tree 검증 흐름으로 돌아가서 분리 처리.

```bash
git commit -m "library: added <type> <name>"
git push
```

### 7. Confirm
Tell the user the entry has been added and is now available for others to use via `/library use <name>`.
