# Contributing

Thanks for helping. Bug reports, doc fixes and pull requests are all welcome.

## Reporting a bug

Use the **Bug report** issue form. It asks for the plugin version, Claude Code version and OS,
which is most of what's needed to reproduce. Security problems go through
[SECURITY.md](SECURITY.md) instead, privately.

## Making a change

1. Fork, branch from `main`, and load your copy with `claude --plugin-dir ./qa-warden`
   (`/reload-plugins` after each edit).
2. Run the checks from the README's [Running the checks](README.md#running-the-checks) section before
   you push. CI runs the same checks plus shellcheck on Ubuntu and macOS, and a PR needs them green.
   Scripts must still parse under macOS's `/bin/bash` 3.2.
3. If the change is user-visible, add an entry to `qa-warden/CHANGELOG.md`. The maintainer bumps the
   version when releasing.
4. Open a pull request against `main`. PRs are merged by rebase, so keep commits meaningful.

Changes to `qa-warden/agents/reviewer.md` also need the behavioural evals
([`qa-warden/evals/README.md`](qa-warden/evals/README.md)). They make real model calls, so the
maintainer runs them; say in the PR that the reviewer changed.

## Ground rules for the plugin

- Nothing may let the AI weaken an assertion. That is the project's one promise; a change that
  loosens a hook or a reviewer check needs a strong reason in the PR.
- No model calls in CI and no API keys anywhere in the repo.
- Templates under `qa-warden/templates/` are copied into users' projects; a change there only reaches
  them through `/qa-warden:init --resync`, so call it out in the CHANGELOG entry.
