# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in any skill or agent, please report it responsibly.

**Email:** [anbuneel@gmail.com](mailto:anbuneel@gmail.com)

Please include:
- Which skill or agent is affected
- A description of the vulnerability
- Steps to reproduce (if applicable)

I'll acknowledge receipt within 48 hours and work on a fix.

## Scope

These are markdown instruction files executed by AI agents — they don't run as standalone software. Security concerns typically involve:

- Skills that could expose secrets or credentials in output
- Instructions that could cause unintended destructive actions (file deletion, force pushes)
- Unsafe shell commands that could be exploited via injection

## Design Principles

All skills follow these security practices:
- Secret redaction in all output and reports
- No hardcoded credentials or API keys
- Read-only analysis by default (skills that modify code say so explicitly)
- Temp files stored in `.review/` (gitignored) to prevent accidental commits
- Decision gates that require user confirmation before destructive actions
