# Agent Mistakes Log

## 2026-02-12

- Mistake: I created the worktree at `vanity-eth-gpu/vanity-eth-gpu-contract` instead of a sibling path because I used a repo-relative path from inside the repo root.
- Avoid: When adding a worktree, run `git worktree add ../<name> -b codex/<branch>` and verify with `git worktree list` immediately.
- Cleanup: If the nested worktree is not desired, remove it with `git worktree remove vanity-eth-gpu-contract` from the main repo root.

- Mistake: I used backticks directly inside a double-quoted `gh pr create --body "..."` shell string, which triggered command substitution (`command not found`) and produced a malformed PR body.
- Avoid: Use a single-quoted heredoc (`cat <<'EOF'`) or escape backticks when passing markdown through shell flags.
- Cleanup: Immediately correct the PR description with `gh pr edit --body-file <file>`.

- Mistake: I interpreted “remove EIP-55” as removing the feature instead of removing the wording in the selector, and merged that broader behavior change.
- Avoid: Confirm scope by mapping the request to explicit targets (label text vs runtime logic) before editing behavior paths.
- Cleanup: Restore the previous behavior and apply only the requested copy change in a follow-up PR.
