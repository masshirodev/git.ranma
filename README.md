# git.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: the focused pane's branch in the bar, and a git folder of keys.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/git.lua`:

```lua
return { "masshirodev/git.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/git.ranma ~/.config/ranma/pack/plugins/start/git.ranma
```

Then put the module in the bar, which no plugin does for you:

```lua
ranma.bar { right = { "git", "datetime" } }
```

Needs: ranma 0.2.2 or newer (the first whose jobs open popups and whose modules a job can refresh), and `git`. Optional: `lazygit` (the `l` key exists only when it is installed), `gh` (for `o`), `less` (the default status command).

## What it does

```text
The `git` bar module shows the repository the focused pane is in: its
branch (the short SHA when HEAD is detached), how many files differ, and
how far it is ahead of and behind its upstream, `main *3 ↑1 ↓2`; accent
while anything differs, urgent with a merge conflict. Nothing outside a
repository. Put it in the bar yourself:
  ranma.bar { right = { "git", "datetime" } }
It is read from one `git status --porcelain=v2 --branch` (without optional
locks, so it never holds the index lock your own git wants), run when the
pane changes directory, when a command finishes in it or in another pane
of the same repository (with shell integration), when focus moves,
and on a slow fallback timer; never two at once for one repository, and
none while the bar does not show the module. A pane whose shell is on
another host (ssh, by OSC 7) shows nothing rather than a local repository
at the same path. The bar shows a look as soon as it ends. Clicking it
opens the status.

leader G is the git folder, on the focused pane's repository:
  s  status in a popup               l  lazygit in one (when installed)
  c  copy HEAD's SHA                 b  copy the branch name
  o  open the remote in the browser (gh browse, or the remote's URL made
     into a web address when gh is missing or fails; copied instead when
     ranma runs over SSH)
  r  refresh the bar now
Options (settings panel, "git" group): git.format, git.interval,
git.untracked, git.status_command, git.lazygit, git.float, git.browse,
git.remote.
```

| Key | Does |
| --- | --- |
| `leader G` | the git folder (`G` is `shift+g`; `g` is ranma's `toggle_group`) |
| `leader G s` | `git.status_command` in a popup, in the focused pane's directory |
| `leader G l` | lazygit in a popup; only bound when lazygit is installed |
| `leader G c` | copy HEAD's full SHA |
| `leader G b` | copy the branch name |
| `leader G o` | open the remote in the browser |
| `leader G r` | look at the repository again now |

A click on the bar module opens the status, as `leader G s` does.

## Options

In ranma's settings panel under `git`, or with hako's `opts` (`{ "masshirodev/git.ranma", opts = { ... } }`), or `ranma.set { git = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `git.format` | `"{branch}{dirty}{ab}"` | The module's text. `{branch}`; `{dirty}` is ` *N` with N files changed; `{ab}` is ` ↑A ↓B` against the upstream; the bare numbers `{staged}` `{changed}` `{untracked}` `{conflicts}` `{ahead}` `{behind}`. |
| `git.interval` | `30` | Seconds between two looks when nothing else asked for one; `0` never. |
| `git.untracked` | `true` | Count untracked files as changed. Off is faster in a huge working tree. |
| `git.status_command` | `"git -c color.status=always status \| less -R -+F -c"` | What `leader G s` runs in the popup, in the pane's directory. Its output goes to the popup's terminal. |
| `git.lazygit` | `true` | `leader G l` opens lazygit in a popup (when lazygit is installed). |
| `git.float` | `80` | The popup's width and height, in percent of the workspace. |
| `git.browse` | `"auto"` | `gh`: `gh browse`. `url`: the remote's URL made into a web address. `auto`: gh when it is installed, the URL when gh fails. |
| `git.remote` | `"origin"` | The remote `leader G o` opens (gh browse picks its own). |

## Notes

- A command finishing refreshes the bar only when ranma can tell a command finished, which takes shell integration (OSC 133 marks). Without it the bar still follows directory changes, focus, and the fallback timer.
- The bar follows the directory ranma knows for the pane. Over ssh, a shell that reports its host with OSC 7 hides the module rather than showing a local repository at the same path.

## License

MIT or Apache-2.0, as ranma.
