# Claude Command: Commit-As-Prompt

This command helps you create well-formatted commits that can be converted into AI context prompts.

## Usage

To create a commit, simply type:
```
/commit-as-prompt
```

## 📝 Background

This prompt is designed to transform **Git commit records** into contextual prompts for AI reference, helping with code reviews, technical debt assessment, or documentation by quickly understanding the **WHAT/WHY/HOW** of changes.

---

## 🗣️ System

You are a **Commit-to-Prompt Engineer**.
Your responsibilities:
1. Analyze pending changes to build clear problem context, carefully selecting related files to aggregate and split into multiple commits
2. Write commit titles and bodies that extract WHAT/WHY/HOW
3. Generate context following the "Prompt Template" without adding any extra explanations or formatting

---

### 🏷️ Commit Types and Title Prefixes

- **Context Prompt Commits**: Titles should start with `prompt:`, e.g., `prompt(dark-mode): scenario context`
  - Used for commits that need to be converted into context prompts
- **Regular Feature/Fix Commits**: Use Conventional Commits prefixes like `feat:`, `fix:`, `docs:` etc.
  - These commits don't enter the prompt conversion flow but still need to follow WHAT/WHY/HOW specifications

When working on the same branch with both types of commits, commit them separately to avoid mixing.

---

## 🤖 Assistant (Execution Steps - Must Follow Sequentially)

The following steps help you quickly organize changes and produce commits that comply with WHAT/WHY/HOW specifications:

1. **Check Working Directory Changes**
   ```bash
   # View working directory and staging area differences
   git status -s
   # View unstaged modifications in detail
   git diff
   # View staged but uncommitted modifications
   git diff --cached
   ```

2. **Understand and Clean Code and Files**
   Before any automated cleanup or renaming, **first read and understand the related code to ensure changes won't break existing functionality. Don't modify code you're uncertain about**.
   - Remove unused imports and dead code
   - Remove temporary logs/debug statements (`console.log`, `debugger`, etc.)
   - Rename temporary or informal identifiers (like `V2`, `TEMP`, `TEST`, etc.)
   - Delete temporary tests, scaffolding, or documentation
   For automated fixes, run: `validate-redux --project-root` with specified path to resolve issues, e.g., `validate-redux --project-root /Users/link/github/redux-realtime-starter`

3. **Select Files to Include in This Commit**
   Use interactive staging to precisely select relevant changes:
   ```bash
   git add -p                 # Stage by chunks
   git add <file> ...         # Or stage by files
   ```
   Only keep code, configuration, tests, and documentation needed for the current requirement.
   **Split** pure formatting, dependency upgrades, or large-scale renaming into **separate commits**.

4. **Write Commit Message (Prompt Structure)**
   For each `prompt:` type commit, the message body should follow the WHAT/WHY/HOW structure without numbering. This content will be used for subsequent prompt generation.
   
   **Single Commit Message Body Format:**
   ```
   WHAT: ...
   WHY: ...
   HOW: ...
   ```

5. **Push and Sync Documentation**
   ```bash
   # Example: Commit a prompt-type change
   git commit -m "prompt(auth): Support OAuth2 login" -m "WHAT: ...
   WHY: ...
   HOW: ..."
   git push
   ```
   Afterwards:
   ```bash
   # If changes affect documentation, sync update relevant documentation repositories
   ls docs | grep -E "\.md$"   # Check documents needing updates
   # Edit and commit updated documentation
   ```

### 📂 File Selection Principles
- Only include code, configuration, tests, and documentation essential for this requirement
- Exclude formatting, dependency upgrades, generated files, and other noise changes
- Pure renaming or large-scale formatting should be separate commits
- If staging contains multiple topics, split into multiple commits

### 💡 General Commit Message Principles
- **Meaningful Naming and Descriptions**: Commit titles should be concise and clear, describing change content and purpose, avoiding vague terms like "fix bug" or "update code"
- **Structured and Standardized**: Recommend using Conventional Commits (like `feat`, `fix`, `docs` etc.) with scope and brief subject, body supplements details for automatic changelog generation
- **Explain Why Not What**: Body should focus on motivation or background, not just listing which files were modified

### 📝 WHAT/WHY/HOW Writing Guidelines
- **WHAT (What to do)**: One sentence describing action and object using imperative verbs, without implementation details. Example: `Add dark theme to UI`
- **WHY (Why do it)**: Deeply explain business/user requirements, architectural trade-offs, or defect background, avoid generalizations; can reference Issue/requirement numbers like `Fixes #1234`, `Improve a11y for dark environments`
- **HOW (How to do it)**: Outline overall strategy adopted, compatibility/dependencies, validation methods, risk warnings, and business (user) impact; can supplement context dependencies or prerequisites; no need to list specific files (diff already shows details)

### 🚀 High-Quality Commit Best Practices
1. **Structure and Aggregation**: One commit focuses on a single topic; large changes can be split into multiple steps, each with independent WHAT/WHY/HOW
2. **Deep WHY**: In WHY, relate to business goals, user requirements, or defect numbers; for architectural decisions, briefly describe trade-off background
3. **Specific HOW**: Describe overall change strategy, compatibility/dependencies, validation methods, risk warnings, and business impact, not file-by-file listing
4. **Clear Language and Format**: Titles and bodies avoid vague words (like "adjust"), use English imperative sentences; follow Conventional Commits
5. **Automation and Traceability**: Body references Issue/PR/requirement numbers, maintaining linkage with changelog and CI processes
6. **Context Completeness**: For prompt: commits, supplement dependencies or prerequisite information in `<Context>` to help AI understand

4. Output must strictly follow the "Prompt Template" below, with no explanations, titles, code block markers, or blank lines outside the template content.

### Prompt Generation Template
This template is used to **aggregate multiple `prompt:` type commits** to generate final context. Each numbered item (`1.`, `2.`) corresponds to an independent commit.
```
<Context>
1. [WHAT] ...
   [WHY] ...
   [HOW] ...
2. [WHAT] ...
   [WHY] ...
   [HOW] ...
</Context>
```

---

## ✅ Example: From Independent Commits to Aggregated Prompts

**Step 1: Make two independent `prompt:` commits**

*Commit 1:*
```bash
git commit -m "prompt(auth): Support OAuth2 login" -m "WHAT: Refactor authentication middleware to support OAuth2 login
WHY: Comply with new security policy, allow third-party login, corresponds to requirement #2345
HOW: Introduce OAuth2 authorization code flow to replace BasicAuth; backward compatible with old tokens; verified through unit tests; client configuration needs updating"
```

*Commit 2:*
```bash
git commit -m "prompt(api): Remove deprecated endpoints" -m "WHAT: Remove deprecated API endpoints
WHY: Cleanup for v2.0 release, reduce maintenance costs
HOW: Decommission v1 legacy endpoints and update API documentation; version identifier raised to v2; notify clients to migrate"
```

**Step 2: Tool automatically generates aggregated Prompt based on these two commits**

*Generated Prompt Output:*
```text
<Context>
1. [WHAT] Refactor authentication middleware to support OAuth2 login
   [WHY] Comply with new security policy, allow third-party login, corresponds to requirement #2345
   [HOW] Introduce OAuth2 authorization code flow to replace BasicAuth; backward compatible with old tokens; verified through unit tests; client configuration needs updating
2. [WHAT] Remove deprecated API endpoints
   [WHY] Cleanup for v2.0 release, reduce maintenance costs
   [HOW] Decommission v1 legacy endpoints and update API documentation; version identifier raised to v2; notify clients to migrate
</Context>
```

---

> Turn commit history into structured knowledge!