# /library publish — legacy wrapper for managed customer VM skill sync

`/library publish` is legacy muscle memory. The canonical operator flow is now:

```bash
/skill-registry-orchestration diff <customer>
/skill-registry-orchestration sync <customer>
```

This cookbook remains only because `deploy-profile.sh` still physically lives under the library skill directory. It forwards the operator to the same ssh + rsync transport for `~/.claude/skills/<name>/` + scoped `library.yaml`.

## Host context — operator host only

이 명령은 **operator host (본 서버, full 프로필)** 에서만 작동한다.

- **본 서버 (`enterpriseai` / `tower-prod`)**: customers 레지스트리 (SSH 정보 + 프로필) 가 `library.yaml` 에 있음 → publish 가능.
- **Customer VM (managed/standalone)**: `library.yaml` 에서 `customers:` 블록이 빠진 scoped 버전만 받음 (`deploy-profile.sh` 의 91-122 줄 참조). 이 명령 실행하면 "customer 'xxx' not found" 에러로 실패.
  - 즉, customer VM 의 사용자가 자기 VM 에서 만든 스킬을 다른 VM 에 publish 하는 시나리오는 의도적으로 막혀있음. publish 는 우리(운영자)의 source-of-truth 모델 일관성 유지 도구.
  - 만약 customer VM 사용자가 만든 스킬을 본 서버로 가져와서 다른 customer 에게 배포하고 싶다면 → 운영자에게 요청 → 본 서버로 끌어오기 (별도 follow-up: `cookbook/import.md` 미작성) → 본 서버에서 publish.

## Customer-custom 스킬 보존 (managed 정책)

`/library publish` 가 customer VM 에 배포할 때, **그 VM 에서 customer 가 만든 자체 스킬은 자동 보존됨**:

| 상황 | 결과 |
|---|---|
| 우리 manifest 의 스킬 (예: `pptx-edit`) → 같은 이름 폴더 sync | `rsync --delete` 로 폴더 안 파일 sync. 우리 source 가 진실원. |
| customer 가 만든 자체 스킬 (예: `local-acme-report`) — 우리 manifest 에 없음 | **건드리지 않음** (rsync 가 그 폴더 자체를 무시). 보존됨. |
| **이름 충돌** — customer 가 `pptx-edit` 를 자체 만들었는데 우리도 `pptx-edit` 가 manifest 에 있음 | ⚠️ **우리 것이 덮어씀**. customer 작품 사라짐. → publish 전에 `--diff` 로 충돌 확인 필요. |

이름 충돌 방어를 위해 `cookbook/create.md` 의 Phase 1 에서 customer host 면 `local-` 또는 `<customer>-` prefix 를 권장. (그래도 우리 manifest 와 같은 이름 만드는 건 자율.)

## When this runs

Prefer **not** to run this cookbook directly. For new flows:

- 사용자 요청이 "고객 VM 에 스킬 배포", "okusystem 에 새 스킬 보내기", "publish skill" 이면 → `/skill-registry-orchestration diff/sync` 로 넘긴다.
- 사용자가 명시적으로 legacy `/library publish <profile|customer>` 를 호출했을 때만 이 cookbook을 실행한다.
- `/skill-architect create` 후 고객 VM 전파가 필요하면 → `/skill-registry-orchestration diff <customer>` → 사용자 확인 → `sync <customer>`.

## Arguments

```
/library publish <profile>     # 프로필 단위 — 그 프로필 가진 모든 customer VM 일괄
/library publish <customer>    # 단일 customer VM
/library publish all           # 모든 managed customer (registry 전체)
```

- **`<profile>`**: `standalone | managed | full`
- **`<customer>`**: `library.yaml` 의 `customers:` 키 (e.g. `okusystem`, `demo-tower`)

## Boundary with `/skill-registry-orchestration` and `/fleet deploy`

| 명령 | 범위 | 언제 |
|---|---|---|
| `/skill-registry-orchestration diff/sync` | 스킬 + scoped library.yaml + manifest **만** | 새 스킬 추가 / 기존 스킬 업데이트 후 canonical path |
| `/library publish` | 위 sync의 legacy wrapper | 오래된 호출 호환이 필요할 때만 |
| `/fleet deploy <customer>` | Tower 코드 (git pull + build + pm2 restart) **+** 스킬 + workspace guide | Tower 자체 업데이트 또는 종합 배포 |

`deploy-profile.sh` 는 아직 library 폴더에 있지만 workflow owner는 `/skill-registry-orchestration` 이다.

## Steps

### 1. 인자 해석 + 대상 결정

```bash
case "$ARG" in
  standalone|managed|full)
    # profile 단위 — registry 에서 해당 profile 가진 customers 전체 enumerate
    TARGETS=$(yq '.customers | to_entries | .[] | select(.value.profile == "<profile>") | .key' library.yaml)
    ;;
  all)
    # 모든 customer (단, ssh: null 인 tower-prod 은 제외)
    TARGETS=$(yq '.customers | to_entries | .[] | select(.value.ssh != null) | .key' library.yaml)
    ;;
  *)
    # 단일 customer
    TARGETS="$ARG"
    ;;
esac
```

대상이 비어있으면 사용자에게 보고 후 정지: "managed 프로필을 가진 등록 customer 가 없어요."

### 2. Dry-run 확인 (선택)

대상이 2 개 이상이면 사용자에게 미리 보여주기:

```bash
for c in $TARGETS; do
  bash ~/.claude/skills/library/deploy-profile.sh --dry-run $(yq ".customers.$c.profile" library.yaml)
done
```

→ "이 N 개 customer 에 M 개 스킬 배포 예정. 진행할까요?" 사용자 확인.

### 3. 배포 실행

각 customer 별로:

```bash
bash ~/.claude/skills/library/deploy-profile.sh --customer <customer>
```

이 스크립트가 내부적으로:
1. SSH 연결 확인
2. `~/.claude/skills/` 에 프로필 매칭되는 스킬들 rsync
3. `.managed-manifest.json` 업데이트
4. scoped `library.yaml` 전송
5. `tower-prod` PM2 restart (skill DB reconcile)
6. customer guide 동기화
7. (managed + browser-live 포함 시) Neko 헬스 체크

### 4. 검증

배포 직후 각 customer 에 대해:

```bash
bash ~/.claude/skills/library/deploy-profile.sh --diff <customer>
```

→ "missing / outdated / up-to-date / customer-custom" 카테고리로 결과 보고. missing 이 있으면 경고.

### 4.5 Secrets drift 검사 (★ 자주 누락)

배포된 스킬이 외부 API 키 의존성 있을 수 있음 (예: `OPENAI_API_KEY`). `library.yaml customers.<name>.secrets:` 의 declarative 선언과 customer VM 의 실제 `~/claude-desk/.env` 가 일치하는지 검사:

```bash
# 선언된 키 이름들
declared=$(yq -r ".customers.$CUSTOMER.secrets[]" ~/.claude/skills/library/library.yaml)

# customer VM 의 실제 키 (이름만, 값 redact)
actual=$(ssh "$SSH_TARGET" "grep -oE '^[A-Z_]+=' ~/claude-desk/.env 2>/dev/null | sed 's/=$//'")

# missing = 선언했는데 .env 에 없음
missing=$(comm -23 <(echo "$declared" | sort) <(echo "$actual" | sort))

if [[ -n "$missing" ]]; then
  warn "Missing secrets on $CUSTOMER:"
  echo "$missing" | sed 's/^/  - /'
  echo "→ Run: /fleet secrets $CUSTOMER 또는 set-secret.sh 스크립트로 배포"
fi
```

**선언 vs 실제 mismatch 패턴**:
- ⚠️ 선언만 있고 실제 .env 에 없음 → 다음 첫 호출에서 fail. **배포 전에 fix 필수**.
- ℹ️ .env 에는 있는데 선언 없음 → declarative source 갱신 권장 (운영자가 수동 추가했거나 옛 잔존)
- ✅ 둘 다 일치 → 정상

이 검사는 단기 follow-up 으로 `deploy-profile.sh --diff <customer>` 에 통합 예정. 현재는 위 snippet 으로 수동 검사.

근거: `~/workspace/decisions/2026-05-01-skill-lifecycle-mandatory-entry-point.md` (갱신 #5 — Phase 4.5)
+ `~/workspace/decisions/2026-05-01-ppt-gen-openai-integration.md` (`set-secret.sh` 신설 절차)

### 5. 보고

사용자에게 요약:

> "배포 완료:
> - okusystem: 34 skills (+ pptx-edit, pptx-template 신규)
> - demo-tower: 34 skills (+ pptx-edit, pptx-template 신규)
>
> 모든 VM 에서 Tower restart 완료, skill DB 재조정 OK."

## Examples

```
사용자: "/library publish managed"
AI:    1. profile=managed 인 customers: okusystem, demo-tower 두 개
       2. dry-run 결과: 34 skills × 2 customers = 68 file ops
       3. 사용자 확인 → 진행
       4. deploy-profile.sh --customer okusystem (3-5 분)
       5. deploy-profile.sh --customer demo-tower
       6. --diff 양쪽 검증
       7. 요약 보고
```

```
사용자: "/library publish okusystem"
AI:    단일 customer → 한 번 실행 → diff → 보고
```

```
사용자: "/skill-architect create 끝나고 곧장 publish"
AI:    create cookbook 의 step 6 에서 사용자가 "managed 배포" 선택
       → 이 cookbook step 1 부터 자동 실행
```

## Failure modes

- **SSH 연결 실패**: 해당 customer 만 skip + 다른 customer 진행. 마지막에 실패 customer 목록 보고.
- **rsync 부분 실패**: 어느 스킬에서 실패했는지 보고. 실패 1 개라도 있으면 `/library publish <customer>` 재실행 권장.
- **PM2 restart 실패**: 배포 자체는 끝났으나 reconcile 안 됨 → 사용자에게 SSH 진단 안내 ("ssh <target> 'pm2 logs tower-prod --lines 100'").
- **Neko 헬스 체크 실패** (managed + browser-live): 비치명. 운영자에게 `tower/scripts/azure/setup-neko.sh` 실행 권유 메시지.

## Related

- 실행 엔진: `~/.claude/skills/library/deploy-profile.sh`
- VM 레지스트리: `library.yaml` `customers:` 섹션
- fleet 결정: `~/workspace/decisions/2026-05-01-fleet-mandatory-entry-point.md` (publish 와 fleet deploy 의 책임 경계)
- 본 결정: `~/workspace/decisions/2026-05-01-skill-lifecycle-mandatory-entry-point.md`
