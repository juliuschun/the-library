# Skill Templates

Ready-to-use templates for different skill types. Copy and customize.

## Available Templates

| Template | Use When | File |
|----------|----------|------|
| **Reference** | Background knowledge, conventions, guidelines | [templates/reference.md](templates/reference.md) |
| **Task** | Step-by-step instructions for specific actions | [templates/task.md](templates/task.md) |
| **File-Writing** | Tasks that create or modify files | [templates/file-writing.md](templates/file-writing.md) |
| **Multi-Agent** | Orchestrating multiple agents or CLIs | [templates/multi-agent.md](templates/multi-agent.md) |
| **Minimal** | Absolute minimum for a working skill | [templates/minimal.md](templates/minimal.md) |

---

## Template Selection Guide

| If your skill... | Use Template |
|------------------|--------------|
| Provides conventions/knowledge | Reference |
| Executes a specific task | Task |
| Creates or modifies files | File-Writing |
| Coordinates multiple agents/CLIs | Multi-Agent |
| Is extremely simple | Minimal |

**Hybrid Approaches:**
- Reference + Task: Add `disable-model-invocation: true` to reference skills that should only run when explicitly invoked
- Task + File-Writing: All file-writing skills are tasks, but not all tasks write files
- Multi-Agent + File-Writing: Most multi-agent skills write consolidated output files

---

## Testing Guidance

- All skill types benefit from at least a Primary JTBD
- File-writing and Multi-agent skills should include Edge cases
- Add Regression tests when fixing bugs in existing skills

**CDM/RPD Guidance:**
- Add **RPD Card** when skill involves a critical decision with multiple patterns
- Add **Classification Gym** (3-6 scenarios) for skills where pattern discrimination matters
- Add **Decision Requirement Table** to map expert vs novice cue recognition
- RPD Cards are **mandatory** for skills where wrong decisions have significant consequences
