# /library audit — 디렉토리 전체 일괄 검증

`~/.claude/skills/` 또는 임의 디렉토리의 모든 SKILL.md 를 일괄 validate. 정기 점검·운영 용도.

## When this runs

- `/library audit` 명시 호출 (전체 점검)
- `/library audit <path>` (특정 디렉토리)
- selfheal skill 의 일부로 (문서·스킬 정합성 점검)
- schedule 으로 주기 점검 (단기 follow-up)

## Arguments

```
/library audit                # ~/.claude/skills/ 전체
/library audit <path>         # 지정 디렉토리
/library audit --catalog      # library.yaml 등재된 스킬만
```

## Steps

### 1. 대상 enumeration

```bash
# 전체
find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md

# 카탈로그 등재된 스킬만
yq '.library.skills[].name' ~/.claude/skills/library/library.yaml
```

### 2. 각 스킬에 validate 적용

`cookbook/validate.md` 의 단계를 각 스킬에 반복. 결과를 누적.

### 3. 카탈로그 정합성 cross-check

추가로 검사:
- **디스크 ↔ library.yaml mismatch**:
  - 디스크에 있지만 yaml 미등록 → `unregistered`
  - yaml 에는 있지만 디스크 누락 → `missing`
- **태그 일관성**:
  - SKILL.md frontmatter 의 tags 와 library.yaml 의 tags 가 일치하는가?

### 4. 결과 보고

```markdown
## Audit: <directory>

### Overview
- **Skills Found**: N (디스크) / M (yaml)
- **Passed**: X
- **Warnings**: Y
- **Failed**: Z
- **Unregistered**: U (디스크에는 있지만 yaml 미등록)
- **Missing**: V (yaml 에는 있지만 디스크 누락)

### Per-Skill Results

| Skill | Status | Errors | Warnings | Catalog |
|-------|--------|--------|----------|---------|
| pptx-edit | PASS | 0 | 1 | OK |
| pptx-template | PASS | 0 | 0 | OK |
| <legacy> | FAIL | 2 | 3 | unregistered |

### Critical Issues
- ...

### Recommendations
- 등록 누락: `/library add <skill>` 으로 등재
- 누락 항목: 본 서버 디스크에 다시 가져오기 (백업에서)
- FAIL 항목: `/library validate <path> --fix` 시도
```

## Use cases

- **분기마다 한 번**: 운영자가 정기 점검
- **Drift 의심 시**: deploy-profile.sh --diff 로 customer VM 검증 후 본 서버 audit
- **신규 운영자 인수**: 전체 카탈로그 상태를 한눈에 파악

## Related

- 단일 스킬: `cookbook/validate.md`
- 카탈로그 등재: `cookbook/add.md`
- 검증 본체: `library/reference/skill-validation.md`
