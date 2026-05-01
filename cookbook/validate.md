# /library validate — 단일 스킬 검증 (+ 자동 fix)

스킬의 frontmatter / 구조 / best practice 를 체크하고, 자동 가능한 수정은 그 자리에서 적용. `/library create` 의 Phase 4 단계가 내부에서 호출하는 흐름이지만, **이미 등록된 스킬을 점검**하는 용도로 직접 호출도 가능.

## When this runs

- `/library validate <path>` 명시 호출 — 단일 스킬 검증
- `/library create` Phase 4 의 자동 호출 — 스캐폴드 직후 품질 게이트
- `/library refine` 의 마지막 단계 — distill 후 재검증

## Arguments

```
/library validate <path>          # 단일 스킬 (기본 — fix 제안만)
/library validate <path> --fix    # 자동 가능한 항목 즉시 수정
```

`<path>` 는 `~/.claude/skills/<name>/` 또는 `~/.claude/skills/<name>/SKILL.md` 둘 다 OK.

## Steps

### 1. SKILL.md 읽기 + frontmatter parse

YAML frontmatter 추출 → name, description, version, tags, allowed-tools, context, agent 등.

### 2. 검증 체크리스트 적용

체크리스트 본체는 `~/.claude/skills/library/reference/skill-validation.md` 참조. 카테고리별 요약:

| 카테고리 | 항목 | Severity |
|---|---|---|
| **Frontmatter** | name (소문자+하이픈, 예약어 X), description (≤1024자, XML 없음, 3인칭), version 형식, tags 유효 | ERROR |
| **Frontmatter** | description 에 "Use when ..." 트리거 명시 | WARN |
| **Structure** | SKILL.md ≤ 500줄, reference 파일 ≤ 1 level 깊이, 참조 파일 존재 | ERROR / WARN |
| **Structure** | TOC (≥100줄 reference 파일에) | INFO |
| **Best Practice** | file-writing 류는 execution plan 단계 있음 | WARN |
| **Best Practice** | side-effect 스킬은 `disable-model-invocation` 명시 | INFO |
| **Best Practice** | MCP 도구는 `Server:tool_name` 정규형 | WARN |
| **Best Practice** | 스킬 이름이 동명사 형 (gerund) | INFO |
| **Best Practice** | description 이 대표 사용자 prompt 들로 트리거 테스트됨 | INFO |
| **Testing** | JTBD 시나리오 Test Pack 포함 | INFO |
| **Testing** | 성공 기준 명시 | INFO |

ERROR 1 개 이상 → FAIL. WARN 만 있으면 PASS-WITH-WARN. INFO 는 권고.

### 3. 자동 fix 가능한 항목 (--fix 시)

- frontmatter format (들여쓰기, key 순서, 빈 줄)
- description 의 XML 태그 제거
- name 의 대문자 → 소문자 변환
- 빈 줄 / trailing whitespace
- 참조 파일 path 의 잘못된 깊이 (warning 만)

수동 fix 가 필요한 항목 (description 내용 보강, 본문 재구조 등) → 사용자에게 보고 + 제안.

### 4. 결과 보고

```markdown
## Validation: <name>

### Summary
- **Status**: PASS | PASS-WITH-WARN | FAIL
- **Errors**: N
- **Warnings**: N
- **Auto-fixed**: N (if --fix)

### Issues

#### Errors
1. **<title>** at line N
   - Problem: ...
   - Fix: ...

#### Warnings
...

### Recommendations
- ...
```

## Examples

```
/library validate ~/.claude/skills/pptx-edit
→ Status: PASS-WITH-WARN
  Warnings: 2 (description 에 "NOT for" 누락, allowed-tools 미명시)

/library validate ~/.claude/skills/pptx-edit --fix
→ Auto-fixed 1 (frontmatter trailing whitespace)
  Manual fix needed: 2 warnings (위와 동일)
```

## Related

- 검증 본체: `library/reference/skill-validation.md`
- spec: `library/reference/skill-spec.md`
- create 의 Phase 4: `cookbook/create.md`
- 디렉토리 일괄: `cookbook/audit.md`
