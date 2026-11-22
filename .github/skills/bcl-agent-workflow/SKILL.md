---
name: bcl-agent-workflow
description: "Use when: an AI agent starts any task on becloudless (bcl) or on an infrastructure repo that consumes it (NixOS, Kubernetes/Helm, Terraform). Operating rules set by the maintainer: never commit, never apply, no live host or cluster mutation without approval, changes as code, verify before asserting, how to handle sudo password prompts, shell and tool pitfalls, answer style. Load this first, before the topic skills."
---

# Agent operating rules

These rules come from the maintainer and apply to every bcl based repository. Topic skills:
[bcl-nixos](../bcl-nixos/SKILL.md), [bcl-kube-charts](../bcl-kube-charts/SKILL.md),
[bcl-kube-operations](../bcl-kube-operations/SKILL.md), [bcl-host-debugging](../bcl-host-debugging/SKILL.md),
[bcl-base-chart-internals](../bcl-base-chart-internals/SKILL.md), [bcl-app-charts](../bcl-app-charts/SKILL.md),
[bcl-virtualization](../bcl-virtualization/SKILL.md), [bcl-tv-role](../bcl-tv-role/SKILL.md).
Code style (naming, comments, refactoring) is in `AGENTS.md` and `CONTRIBUTING.md`: read them too.

## Hard rules

1. Never run `git commit`, `--amend`, `rebase`, or move branches. Leave changes in the working tree: the maintainer commits and pushes. Only commit when explicitly asked.
2. Never run `tofu/terraform apply`, `kubectl apply|patch|delete`, `helm install|upgrade`, or deploy with `bcl nix up` unless asked. Read-only is always fine: `plan`, `nix eval`, `helm template`, `kubectl get|describe|logs`, `ssh host <read-only command>`.
3. Infrastructure is changed as code (`AGENTS.md`: nothing directly in the infrastructure except for testing). A live tweak is only a test: always port it to the repo, and say it is not persistent.
4. Ask before anything destructive or hard to reverse: deleting PVC/PV/volumes/backups, removing etcd members, `rm -rf`, force push, resetting a device, changing a live production network config. A temporary, reversible, read-mostly test (e.g. writing a CPU register until reboot) is fine once the user said to do it; describe what it does and how to undo it first.
5. Public repositories must not contain private data: no names of private infra repos, personal domains, host names, IPs, people. Use `example.com`, `<host>`, `<cluster>`. Re-read what you wrote before finishing.
6. Do not create markdown documentation files unless asked. Do not add features, refactors or comments beyond the request.

## Keep the skills current

Skills are the shared memory between agents and machines: a stale skill is worse than none.

- When a task shows that a skill is wrong, outdated or incomplete (a command that failed, a renamed path or option, a new pitfall confirmed by a test, a rule the maintainer just stated), fix the skill in the same change, in the repo that owns the knowledge.
- Add only verified facts: the symptom, the cause, the fix, how it was confirmed. Replace a wrong entry instead of appending a contradiction. Keep SKILL.md under 500 lines and move detail to `references/`.
- Generic knowledge goes in the public bcl skills with no private names, IPs or domains; infra specific knowledge goes in the skills of the private repo. Do not put one-shot migration plans or in-progress state in skills.
- Skill edits are left uncommitted like any other change, and mentioned in the hand-back.

## Investigate, then conclude

- Measure before theorising, read-only first. Prefer data (counters, timestamps, logs) over guesses, and rule hypotheses out with a test.
- Verify state before asserting it. "Is X deployed?": compare `readlink /run/current-system`, boot time and crash timestamps. Do not answer from the repo alone.
- One confirmed test does not prove a parameter accepts every value (a keyword can be valid while the value is not).
- Error handlers that only log "script error" hide the real message: run the inner command by hand to see it.
- A looping test runner that only fails at the end must not be judged with `| tail`: capture the output, `grep -c '^PASS'`/`'^FAIL'`, or check the exit code.
- After a notice that files were edited by the user or a formatter, re-read the files and run `git status`, `git log --oneline -5`, `git reflog -5`: the maintainer may have committed your work to another branch or discarded it. Never assume earlier edits are still in the tree. After a rename/move, also check for stray old directories or files that reappeared (`git status --short`).
- Generated files (e.g. `_renderResources.tpl`, `ci/ci-result.yaml`, `*.gen.go`) are regenerated, not hand edited, unless the topic skill says otherwise.
- Local tool or library versions can differ from what a consumer pins (nixpkgs `lib`, helm): test through the real consumer path.

## Interactive sudo and prompts

When a remote command needs a sudo password (`ssh -t host 'sudo ...'`):
1. Run it in an async terminal.
2. Tell the user what it does, whether it is read-only, and ask them to type the password in that terminal.
3. Poll the terminal output. Never ask for the password in chat and never type it yourself.

Batch what needs sudo into one command so the user types the password once.

## Shell and tool pitfalls (zsh)

- Never use `path` (lower case) as a variable or loop name in zsh: it is tied to `$PATH` and silently breaks every command. Use `p`, `item`, `entry`. Recovery on NixOS: `source /etc/set-environment`.
- `curl` can be a shell function (grc wrapper) that hangs in scripts: use `command curl`. Add `--compressed` when the response is gzip.
- Avoid `rm -rf *` (zsh prompts): `rm -rf dir && mkdir dir`.
- `echo "====="` unquoted-ish can fail ("= not found"): use `echo "--- title"`.
- `k` or other aliases do not exist in scripts: use functions in a bash file.
- `set -e` plus `pipefail`: `grep | wc -l` aborts when grep finds nothing, and `cmd | grep -q` fails with SIGPIPE (141). Capture into a variable first.
- A kubectl shim `ssh host sudo kubectl "$@"` loses quoting: build the remote command with `printf '%q '`.
- Tools may be missing (python3, opentofu, jq): use `nix run nixpkgs#<pkg> -- ...` or `nix shell nixpkgs#<pkg> -c ...`.
- Big raw files through a web fetch tool return 100k+ tokens: prefer `command curl -s <raw-url> | grep -n -B2 -A8 <key>`.
- Sync terminal commands that exceed the timeout move to the background and lose shell variables: do build + test in one call with a generous timeout.

## Editing pitfalls

- Never issue several single-string replacements on the same file in parallel: they race and silently mangle the file. Use one multi-replace call, or edit sequentially, then check `git diff`.
- A Go language server can insert a `package <dirname>` line at the top of a brand new `.go` file. After creating Go files, re-read each one (or grep the package clause) before building: the error only shows as a duplicate package or "not a main package".
- After editing, run the project's own check (see topic skill) and the editor error check on changed files.

## Answer style

Short and factual, no emojis, link files with workspace-relative links. End with what remains for the user (commit, push, deploy, apply, reboot) and the exact command when useful. Say clearly what is verified and what is only evaluated.

## Keep knowledge in the repo

When a gotcha cost real time, add it to the relevant topic skill (or its `references/`), generic and without private names. Keep notes short and say how it was verified.
