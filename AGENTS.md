# AGENTS.md

git.ranma is a ranma plugin in Lua: `plugin/git.lua` is all of it, and its
header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Keep it to API that exists in the latest ranma release: CI loads it there.
- Never poll fast: a look at a repository is one `ranma.spawn` of git, at
  most one in flight per repository, and none while the bar hides the module.
  The module ticks every 30 s only so the plugin knows the bar shows it; a
  look's `on_exit` shows its result with `ranma.refresh_module("git")`.
- The popups are `ranma popup` run as a job (ranma 0.2.2 gives jobs the
  server's `RANMA_SOCKET`), with the command's stdout sent to `/dev/tty`,
  since `ranma popup` captures stdout and less and lazygit draw there.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server. Test behaviour against a private
  server (its own `RANMA_CONFIG_DIR` and `XDG_RUNTIME_DIR`, with `RANMA_SOCKET`
  `RANMA` `RANMA_PANE` `TMUX` unset), never the one you are typing in.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
