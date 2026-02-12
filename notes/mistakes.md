# Agent Mistakes Log

## 2026-02-12

- Mistake: I created the worktree at `vanity-eth-gpu/vanity-eth-gpu-contract` instead of a sibling path because I used a repo-relative path from inside the repo root.
- Avoid: When adding a worktree, run `git worktree add ../<name> -b codex/<branch>` and verify with `git worktree list` immediately.
- Cleanup: If the nested worktree is not desired, remove it with `git worktree remove vanity-eth-gpu-contract` from the main repo root.

