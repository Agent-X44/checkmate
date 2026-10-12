# Committing and pushing across branches

A day-to-day command guide for this repository. For what each branch is for and how releases are published, see [GitHub branches and Android releases](github-branch-workflow.md).

| Branch | How it is updated |
| --- | --- |
| `dev` | Commit here directly. All everyday work starts on this branch. |
| `stable` | Never commit on it directly. Fast-forward it to a tested `dev` commit. |
| `feature/<change-name>` | Optional. Branch off `dev`, then merge back into `dev`. |
| `Android-dev`, `IOS-dev` | Platform branches. Only commit there for platform-only work. |

## Before you start

```bash
git status
git switch dev
git pull --ff-only origin dev
```

`git status` should report a clean working tree. If it lists changes you don't want to keep, stash them (`git stash`) before switching branches.

## Everyday change: `dev`, then `stable`

1. Make the change on `dev` and check what you are about to commit:

   ```bash
   git status
   git diff
   ```

2. Stage specific files rather than everything, so secrets and build output stay out:

   ```bash
   git add lib/path/to/file.dart docs/some-doc.md
   ```

3. Commit with a short, typed message (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`):

   ```bash
   git commit -m "fix: keep failed sheet saves queued for retry"
   ```

4. Push `dev`:

   ```bash
   git push origin dev
   ```

5. Fast-forward `stable` to the same commit without leaving `dev`:

   ```bash
   git push origin dev:stable
   ```

   This only succeeds when `stable` is an ancestor of `dev`. If Git rejects it as non-fast-forward, someone changed `stable` separately. Stop and inspect it with `git log --oneline dev..origin/stable`. Do not force-push.

6. Optionally bring your local `stable` up to date as well:

   ```bash
   git fetch origin
   git branch -f stable origin/stable
   ```

## Larger change: a feature branch

```bash
git switch dev
git pull --ff-only origin dev
git switch -c feature/template-import
```

Commit on the feature branch as often as you like, and push it to back it up:

```bash
git push -u origin feature/template-import
```

When the change is ready, merge it into `dev`, push, then promote to `stable` as in step 5:

```bash
git switch dev
git pull --ff-only origin dev
git merge --no-ff feature/template-import
git push origin dev
git push origin dev:stable
```

Delete the branch afterwards:

```bash
git branch -d feature/template-import
git push origin --delete feature/template-import
```

## Platform branches (`Android-dev`, `IOS-dev`)

Shared fixes belong on `dev`. Use a platform branch only for work that applies to that platform alone:

```bash
git switch Android-dev
git pull --ff-only origin Android-dev
git commit -m "fix: android camera permission prompt"
git push origin Android-dev
```

To carry one specific platform commit over to `dev`, use cherry-pick:

```bash
git switch dev
git cherry-pick <commit-hash>
git push origin dev
```

## Keeping the contributor list to yourself

GitHub lists everyone named in a `Co-authored-by:` line in a commit message as a contributor. AI tools such as Claude Code and Copilot can add these lines automatically. Before pushing, check the latest commit message:

```bash
git log -1 --format=%B
```

If it has a `Co-authored-by:` line you don't want, remove it before pushing:

```bash
git commit --amend
```

Only amend commits that you haven't pushed yet.

Also confirm that your commits use your GitHub identity:

```bash
git config user.email
```

The email should be `147250418+Agent-X44@users.noreply.github.com`.

## Quick fixes

| Situation | Command |
| --- | --- |
| Committed to the wrong branch (not pushed) | `git switch correct-branch`, `git cherry-pick <hash>`, then on the wrong branch `git reset --hard HEAD~1` |
| Need to undo a pushed commit | `git revert <hash>`, then push. Never rewrite pushed history on `stable`. |
| `git pull --ff-only` refuses | Your local branch diverged. Run `git log --oneline --graph HEAD origin/<branch>` to see both sides, then rebase or merge deliberately. |
| Forgot a file in the last commit (not pushed) | `git add <file>`, then `git commit --amend --no-edit` |
| See what `stable` is missing from `dev` | `git log --oneline origin/stable..origin/dev` |
