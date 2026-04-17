#!/usr/bin/env bash
# ─────────────────────────────────────────────
# Library Profile Deployer
# 고객 VM에 프로필 기반으로 스킬을 배포한다.
#
# Usage:
#   bash deploy-profile.sh <profile> <ssh-target>
#   bash deploy-profile.sh customer-basic toweradmin@20.41.101.188
#   bash deploy-profile.sh --customer okusystem     # customers 레지스트리에서 조회
#   bash deploy-profile.sh --list                    # 프로필별 스킬 목록
#   bash deploy-profile.sh --dry-run customer-basic  # 배포 없이 목록만
# ─────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_FILE="$SCRIPT_DIR/library.yaml"
SKILLS_DIR="$HOME/.claude/skills"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1" >&2; }

# ─── Parse library.yaml with python ───
parse_yaml() {
  local yaml_file="$1"; shift
  python3 - "$yaml_file" "$@" << 'PYEOF'
import sys, yaml, json

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

cmd = sys.argv[2] if len(sys.argv) > 2 else "dump"

if cmd == "profile-tags":
    profile_name = sys.argv[3]
    profiles = data.get("profiles", {})
    if profile_name not in profiles:
        print(f"ERROR: profile '{profile_name}' not found", file=sys.stderr)
        sys.exit(1)
    tags = profiles[profile_name].get("tags", [])
    print(json.dumps(tags))

elif cmd == "skills-by-tags":
    tags = json.loads(sys.argv[3])
    tag_set = set(tags)
    skills = data.get("library", {}).get("skills", [])
    matched = [s["name"] for s in skills if tag_set.intersection(set(s.get("tags", [])))]
    print(json.dumps(matched))

elif cmd == "customer":
    customer_name = sys.argv[3]
    customers = data.get("customers", {})
    if customer_name not in customers:
        print(f"ERROR: customer '{customer_name}' not found", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(customers[customer_name]))

elif cmd == "list-profiles":
    profiles = data.get("profiles", {})
    skills = data.get("library", {}).get("skills", [])
    for pname, pdata in profiles.items():
        tags = set(pdata.get("tags", []))
        matched = [s["name"] for s in skills if tags.intersection(set(s.get("tags", [])))]
        desc = pdata.get("description", "")
        print(f"{pname}|{desc}|{len(matched)}|{','.join(matched)}")

elif cmd == "list-all":
    skills = data.get("library", {}).get("skills", [])
    for s in skills:
        tags = ",".join(s.get("tags", []))
        print(f"{s['name']}|{tags}|{s.get('description','')}")

elif cmd == "manifest":
    # Generate managed skills manifest (name → version) for a profile
    tags = json.loads(sys.argv[3])
    tag_set = set(tags)
    skills = data.get("library", {}).get("skills", [])
    manifest = {
        s["name"]: s.get("version", "0.0.0")
        for s in skills
        if tag_set.intersection(set(s.get("tags", [])))
    }
    print(json.dumps(manifest, indent=2))

PYEOF
}

# ─── Check dependencies ───
if ! python3 -c "import yaml" 2>/dev/null; then
  err "PyYAML required: pip3 install pyyaml"
  exit 1
fi

# ─── Commands ───
case "${1:-}" in
  --list)
    echo -e "${CYAN}═══ Library Profiles ═══${NC}"
    echo ""
    parse_yaml "$YAML_FILE" list-profiles | while IFS='|' read -r name desc count skills; do
      echo -e "${GREEN}[$name]${NC} $desc"
      echo -e "  스킬 ${count}개: $skills"
      echo ""
    done
    exit 0
    ;;

  --list-all)
    echo -e "${CYAN}═══ All Skills ═══${NC}"
    echo ""
    printf "%-30s %-15s %s\n" "SKILL" "TAGS" "DESCRIPTION"
    printf "%-30s %-15s %s\n" "─────" "────" "───────────"
    parse_yaml "$YAML_FILE" list-all | while IFS='|' read -r name tags desc; do
      printf "%-30s %-15s %s\n" "$name" "$tags" "$desc"
    done
    exit 0
    ;;

  --customer)
    CUSTOMER="${2:?customer name required}"
    CUSTOMER_JSON=$(parse_yaml "$YAML_FILE" customer "$CUSTOMER")
    PROFILE=$(echo "$CUSTOMER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['profile'])")
    SSH_TARGET=$(echo "$CUSTOMER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['ssh'])")
    TEAM_NAME=$(echo "$CUSTOMER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('team_name',''))")
    info "Customer: $CUSTOMER → profile=$PROFILE, ssh=$SSH_TARGET, team=$TEAM_NAME"
    ;;

  --dry-run)
    PROFILE="${2:?profile name required}"
    TAGS=$(parse_yaml "$YAML_FILE" profile-tags "$PROFILE")
    SKILLS_JSON=$(parse_yaml "$YAML_FILE" skills-by-tags "$TAGS")
    echo -e "${CYAN}═══ Dry Run: profile=$PROFILE ═══${NC}"
    echo -e "Tags: $TAGS"
    echo ""
    echo "$SKILLS_JSON" | python3 -c "import sys,json; [print(f'  → {s}') for s in json.load(sys.stdin)]"
    SKILL_COUNT=$(echo "$SKILLS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    echo ""
    echo -e "${GREEN}Total: $SKILL_COUNT skills would be deployed${NC}"
    exit 0
    ;;

  --diff)
    # Compare local managed skills vs remote (customer VM)
    CUSTOMER="${2:?customer name required}"
    CUSTOMER_JSON=$(parse_yaml "$YAML_FILE" customer "$CUSTOMER")
    PROFILE=$(echo "$CUSTOMER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['profile'])")
    SSH_TARGET=$(echo "$CUSTOMER_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['ssh'])")

    echo -e "${CYAN}═══ Skill Diff: $CUSTOMER (profile=$PROFILE) ═══${NC}"
    echo ""

    # Get managed manifest for this profile
    TAGS=$(parse_yaml "$YAML_FILE" profile-tags "$PROFILE")
    LOCAL_MANIFEST=$(parse_yaml "$YAML_FILE" manifest "$TAGS")

    # Get remote state
    REMOTE_SKILLS=$(ssh -o ConnectTimeout=5 "$SSH_TARGET" 'ls -1 ~/.claude/skills/ 2>/dev/null' || echo "")
    REMOTE_MANIFEST=$(ssh -o ConnectTimeout=5 "$SSH_TARGET" 'cat ~/.claude/skills/.managed-manifest.json 2>/dev/null' || echo "{}")

    python3 - "$LOCAL_MANIFEST" "$REMOTE_MANIFEST" "$REMOTE_SKILLS" << 'DIFFPY'
import sys, json

local = json.loads(sys.argv[1])
try:
    remote_managed = json.loads(sys.argv[2])
except:
    remote_managed = {}
remote_dirs = set(sys.argv[3].strip().split('\n')) if sys.argv[3].strip() else set()
remote_dirs.discard('.managed-manifest.json')

local_names = set(local.keys())
managed_names = set(remote_managed.keys())

# Categories
missing = local_names - remote_dirs          # Should be deployed but isn't there
outdated = {n for n in local_names & managed_names if local[n] != remote_managed.get(n)}
custom = remote_dirs - local_names           # Customer-created skills
up_to_date = local_names & remote_dirs - outdated

print("📦 Managed Skills:")
if missing:
    for s in sorted(missing):
        print(f"  ❌ {s} — missing (local {local[s]})")
if outdated:
    for s in sorted(outdated):
        print(f"  🔄 {s} — outdated (remote {remote_managed[s]} → local {local[s]})")
if up_to_date:
    for s in sorted(up_to_date):
        print(f"  ✅ {s} ({local[s]})")
if not missing and not outdated:
    print("  All managed skills up to date ✅")

print()
print("🔧 Customer Custom Skills:")
if custom:
    for s in sorted(custom):
        print(f"  🆕 {s}")
else:
    print("  (none)")

print()
print(f"Summary: {len(up_to_date)} current, {len(outdated)} outdated, {len(missing)} missing, {len(custom)} custom")
DIFFPY
    exit 0
    ;;

  -h|--help)
    echo "Usage:"
    echo "  deploy-profile.sh <profile> <ssh-target>     Deploy skills by profile"
    echo "  deploy-profile.sh --customer <name>           Deploy using customer registry"
    echo "  deploy-profile.sh --list                      Show all profiles"
    echo "  deploy-profile.sh --list-all                  Show all skills with tags"
    echo "  deploy-profile.sh --dry-run <profile>         Preview without deploying"
    echo "  deploy-profile.sh --diff <customer>           Compare local vs remote skills"
    exit 0
    ;;

  *)
    if [[ -z "${2:-}" && -z "${SSH_TARGET:-}" ]]; then
      PROFILE="${1:?profile or --customer required}"
      SSH_TARGET="${2:?ssh target required (user@host)}"
    elif [[ -z "${SSH_TARGET:-}" ]]; then
      PROFILE="$1"
      SSH_TARGET="$2"
    fi
    ;;
esac

# ─── Resolve profile → skill list ───
TAGS=$(parse_yaml "$YAML_FILE" profile-tags "$PROFILE")
SKILLS_JSON=$(parse_yaml "$YAML_FILE" skills-by-tags "$TAGS")
SKILL_NAMES=$(echo "$SKILLS_JSON" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)))")
SKILL_COUNT=$(echo "$SKILLS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

info "Profile: $PROFILE ($SKILL_COUNT skills)"
info "Target: $SSH_TARGET"
echo ""

# ─── Check SSH connectivity ───
if ! ssh -o ConnectTimeout=5 "$SSH_TARGET" 'echo ok' >/dev/null 2>&1; then
  err "Cannot SSH to $SSH_TARGET"
  exit 1
fi

# ─── Prepare remote skills dir ───
ssh "$SSH_TARGET" 'mkdir -p ~/.claude/skills'

# ─── Deploy each skill ───
DEPLOYED=0
FAILED=0

for skill in $SKILL_NAMES; do
  SRC="$SKILLS_DIR/$skill"
  if [[ ! -d "$SRC" ]]; then
    warn "Skill not found locally: $skill (skipping)"
    ((FAILED++)) || true
    continue
  fi

  echo -ne "  Deploying ${CYAN}$skill${NC}..."
  rsync -az --delete "$SRC/" "$SSH_TARGET:~/.claude/skills/$skill/" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo -e " ${GREEN}✓${NC}"
    ((DEPLOYED++)) || true
  else
    echo -e " ${RED}✗${NC}"
    ((FAILED++)) || true
  fi
done

echo ""
info "Deployed: $DEPLOYED / $SKILL_COUNT skills"
[[ $FAILED -gt 0 ]] && warn "Failed: $FAILED (run with local skills installed first)"

# ─── Deploy managed manifest ───
# This file marks which skills are managed by us (vs customer-created)
MANIFEST_JSON=$(parse_yaml "$YAML_FILE" manifest "$TAGS")
echo -ne "  Deploying managed manifest..."
echo "$MANIFEST_JSON" | ssh "$SSH_TARGET" 'cat > ~/.claude/skills/.managed-manifest.json'
if [[ $? -eq 0 ]]; then
  echo -e " ${GREEN}✓${NC}"
else
  echo -e " ${RED}✗${NC}"
  warn "Manifest deployment failed"
fi

# ─── Verify on remote ───
REMOTE_COUNT=$(ssh "$SSH_TARGET" 'ls ~/.claude/skills/ 2>/dev/null | wc -l')
CUSTOM_COUNT=$(ssh "$SSH_TARGET" 'python3 -c "
import json, os
manifest = {}
mf = os.path.expanduser(\"~/.claude/skills/.managed-manifest.json\")
if os.path.exists(mf):
    with open(mf) as f: manifest = json.load(f)
dirs = set(d for d in os.listdir(os.path.expanduser(\"~/.claude/skills/\")) if os.path.isdir(os.path.expanduser(f\"~/.claude/skills/{d}\")))
custom = dirs - set(manifest.keys())
print(len(custom))
" 2>/dev/null' || echo "?")
info "Remote skills: $REMOTE_COUNT total ($CUSTOM_COUNT customer-created)"

# ─── Deploy customer guide to workspace ───
GUIDE_SRC="$HOME/tower/templates/customer-guide"
if [[ -d "$GUIDE_SRC" ]]; then
  echo ""
  echo -e "${CYAN}═══ Deploying Customer Guide ═══${NC}"

  # Ensure remote guide dir exists
  ssh "$SSH_TARGET" 'mkdir -p ~/workspace/guide'

  echo -ne "  Deploying guide files..."
  rsync -az "$GUIDE_SRC/" "$SSH_TARGET:~/workspace/guide/" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo -e " ${GREEN}✓${NC}"
  else
    echo -e " ${RED}✗${NC}"
    warn "Guide deployment failed (non-fatal)"
  fi

  # ─── Fix {{TEAM_NAME}} placeholder if team_name is set ───
  if [[ -n "${TEAM_NAME:-}" ]]; then
    HAS_PLACEHOLDER=$(ssh "$SSH_TARGET" 'grep -c "{{TEAM_NAME}}" ~/workspace/CLAUDE.md 2>/dev/null || echo 0')
    if [[ "$HAS_PLACEHOLDER" != "0" ]]; then
      echo -ne "  Replacing {{TEAM_NAME}} → ${TEAM_NAME}..."
      ssh "$SSH_TARGET" "sed -i 's/{{TEAM_NAME}}/${TEAM_NAME}/g' ~/workspace/CLAUDE.md" 2>/dev/null
      echo -e " ${GREEN}✓${NC}"
    fi
  fi

  # ─── Ensure codify.md exists ───
  HAS_CODIFY=$(ssh "$SSH_TARGET" 'test -f ~/workspace/codify.md && echo 1 || echo 0')
  if [[ "$HAS_CODIFY" == "0" ]]; then
    echo -ne "  Creating codify.md..."
    ssh "$SSH_TARGET" 'cat > ~/workspace/codify.md << "CODEOF"
# Learnings Log

팀이 일하면서 배운 것들을 기록합니다.
실수, 발견, 팁 — 한 줄이라도 적어두면 다음에 같은 실수를 안 합니다.

## 사용법

AI에게 "이거 codify에 기록해줘"라고 말하면 여기에 추가합니다.

---

CODEOF' 2>/dev/null
    echo -e " ${GREEN}✓${NC}"
  fi

  # ─── Update workspace CLAUDE.md with guide reference ───
  CLAUDE_TEMPLATE="$HOME/tower/templates/workspace/CLAUDE.md"
  if [[ -f "$CLAUDE_TEMPLATE" ]]; then
    HAS_GUIDE=$(ssh "$SSH_TARGET" 'grep -c "tower-knowledge.md" ~/workspace/CLAUDE.md 2>/dev/null || echo 0')
    if [[ "$HAS_GUIDE" == "0" ]]; then
      echo -ne "  Updating workspace CLAUDE.md with guide reference..."
      ssh "$SSH_TARGET" 'python3 -c "
import os
ws = os.path.expanduser(\"~/workspace/CLAUDE.md\")
with open(ws) as f:
    content = f.read()
guide_block = chr(10) + chr(10).join([
    \"## Tower 제품 가이드\",
    \"\",
    \"사용자가 Tower 사용법, 기능, 스킬, 시각화, 권한 등을 물으면 guide/tower-knowledge.md를 참조하여 답변하세요.\",
    \"- 기능 질문 → guide/tower-knowledge.md\",
    \"- 시작 방법 → guide/getting-started.md\",
    \"- 활용 팁 → guide/tips.md\",
    \"\",
    \"사용자가 뭘 할 수 있어?, 도움말, 기능 목록, 스킬 목록 등을 물으면:\",
    \"- 설치된 스킬과 각 1줄 설명을 보여주세요\",
    \"- 시각화 기능 예시를 포함하세요\",
    \"- 이런 것도 할 수 있어요 식으로 구체적 예시를 들어주세요\",
    \"\",
]) + chr(10)
if \"tower-knowledge.md\" not in content:
    lines = content.split(chr(10))
    idx = next((i for i, l in enumerate(lines) if i > 0 and l.startswith(\"## \")), len(lines))
    lines.insert(idx, guide_block)
    with open(ws, \"w\") as f:
        f.write(chr(10).join(lines))
"' 2>/dev/null
      if [[ $? -eq 0 ]]; then
        echo -e " ${GREEN}✓${NC}"
      else
        echo -e " ${YELLOW}⚠ manual update needed${NC}"
      fi
    else
      echo -e "  Workspace CLAUDE.md already has guide reference ${GREEN}✓${NC}"
    fi
  fi
else
  warn "Customer guide not found at $GUIDE_SRC (skipping guide deployment)"
fi

# ─── Restart remote Tower to trigger reconcileManagedSkills ───
# Tower's startup path (backend/index.ts) reads .managed-manifest.json and
# reconciles the skill_registry table against it. Without a restart the DB
# keeps whatever legacy rows it had, and syncCompanySkillsToFs will re-emit
# them as files on the next restart regardless.
echo ""
echo -e "${CYAN}═══ Reconciling skill DB on remote ═══${NC}"
echo -ne "  Restarting tower-prod..."
if ssh "$SSH_TARGET" 'pm2 restart tower-prod --update-env >/dev/null 2>&1'; then
  echo -e " ${GREEN}✓${NC}"
  # Wait a moment for startup reconciler to run, then verify
  sleep 3
  RECONCILE_LOG=$(ssh "$SSH_TARGET" 'pm2 logs tower-prod --lines 40 --nostream --raw 2>/dev/null | grep "reconcileManagedSkills\|Managed mode" | tail -3')
  if [[ -n "$RECONCILE_LOG" ]]; then
    echo -e "  ${GREEN}Reconcile log:${NC}"
    echo "$RECONCILE_LOG" | sed 's/^/    /'
  else
    warn "Could not verify reconcile in logs (Tower may be running an older build without reconciler — update tower repo + rebuild on remote)"
  fi
else
  warn "Failed to restart tower-prod — skill DB may still contain legacy rows until next restart"
fi

echo ""
echo -e "${GREEN}Done!${NC} Customer can now use deployed skills on their Tower instance."
