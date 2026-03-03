# 🤖 Agentic Engineering: Skills Guide (Gemini)

**Author:** Gemini CLI  
**Last Updated:** Monday, March 2, 2026

Welcome to your advanced agent workspace. This repository is equipped with a suite of specialized skills that orchestrate multiple AI models and security tools to help you build, review, and ship high-quality software.

---

## 📂 Quick Navigation

| Category | Skills |
| :--- | :--- |
| **💡 Ideation** | `peer-ideate`, `peer-review-plan` |
| **🚀 Delivery** | `peer-review-code`, `merge` |
| **🛡️ Security** | `security-scan`, `security-audit`, `security-posture` |

---

## 💡 Collaboration & Ideation

### `peer-ideate` — The Council of Models
Gather independent perspectives from **Claude**, **Codex**, and **Gemini** on any topic.
*   **Best for:** Brainstorming architecture, naming, UI design, or complex tradeoffs.
*   **Workflow:**
    ```mermaid
    graph TD
      A[User Brief] --> B(Parallel Brainstorming)
      B --> C[Claude]
      B --> D[Codex]
      B --> E[Gemini]
      C & D & E --> F{Claude Synthesis}
      F --> G[Counter-Review Round]
      G --> H[Final Consensus Report]
    ```

### `peer-review-plan` — Blueprint Validation
Get a second opinion on your implementation strategy before you write a single line of code.
*   **Best for:** Validating complex refactors or new feature designs.
*   **Logic:** Uses a **Counter-Review** system where Claude and Codex debate the plan until a consensus is reached.

---

## 🚀 Code Quality & Delivery

### `peer-review-code` — Automated PR Pipeline
The most rigorous code review tool in your belt. It orchestrates a multi-round review with automated fixes.
*   **Best for:** Ensuring high standards on feature branches before merging.
*   **Key Feature:** **Fingerprinting.** It tracks "MUST FIX" items across rounds to ensure bugs don't resurface.

### `merge` — Safe Landing
A one-command workflow to squash-merge your PR and keep your project history clean.
*   **Best for:** Finalizing a task.
*   **Automation:** Automatically updates your `README.md`, `CHANGELOG.md`, and `CLAUDE.md` based on the PR content.

---

## 🛡️ Security & Compliance

### `security-scan` — Fast Tool-Based Audit
Runs industry-standard scanners (Semgrep, Gitleaks, npm audit) to catch low-hanging fruit.
*   **Scan Types:** SAST (Static Analysis), Secret Detection, and Dependency Vulnerabilities.

### `security-audit` — Deep AI Analysis
A comprehensive, full-codebase security review powered by four different AI perspectives.
*   **OWASP Focus:** Maps findings directly to the OWASP Top 10.
*   **Safety:** **Redacts all secrets.** No sensitive data ever enters the final report.

### `security-posture` — Infrastructure Scorecard
A fast hygiene check that gives your project a letter grade (A-F).
*   **Checks:** Gitignore health, Branch protection, CI security steps, and Docker best practices.

---

## 🎨 Visual Assets (Generated via Nano Banana 2)

Leverage Google's **Nano Banana 2** (Gemini 3.1 Flash Image) to generate high-quality visual assets, icons, and hero images directly within your project workflow.

**Primary Intent:** Use AI image generation to create visually appealing documentation, UI placeholders, and professional marketing assets that make your repository stand out.

### 🖼️ Hero Header
> **Prompt:** *A futuristic, high-detail wide-angle digital illustration of a robotic "Council of Three" AI agents sitting around a holographic table, neon blue and violet accents, glassmorphism style, 8k resolution, cinematic lighting.*

### 🛠️ Skill Category Icons
| Category | Nano Banana 2 Prompt |
| :--- | :--- |
| **Ideation** | *A minimalist 3D isometric icon of a glowing lightbulb made of interconnected circuit lines, frosted glass texture, soft studio lighting.* |
| **Delivery** | *A 3D isometric icon of a sleek silver rocket ship lifting off from a digital terminal, vibrant orange engine glow, clean white background.* |
| **Security** | *A high-tech 3D shield icon with a holographic fingerprint scan over it, metallic chrome and neon green accents, cyber-security aesthetic.* |

---

> [!TIP]
> Run any skill by typing its name (e.g., `/peer-ideate`) in the Gemini CLI.
