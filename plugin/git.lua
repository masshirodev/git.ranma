-- git: the focused pane's branch in the bar, and a git folder of keys.
--
-- The `git` bar module shows the repository the focused pane is in: its
-- branch (the short SHA when HEAD is detached), how many files differ, and
-- how far it is ahead of and behind its upstream, `main *3 ↑1 ↓2`; accent
-- while anything differs, urgent with a merge conflict. Nothing outside a
-- repository. Put it in the bar yourself:
--   ranma.bar { right = { "git", "datetime" } }
-- It is read from one `git status --porcelain=v2 --branch` (without optional
-- locks, so it never holds the index lock your own git wants), run when the
-- pane changes directory, when a command finishes in it or in another pane
-- of the same repository (with shell integration), when focus moves,
-- and on a slow fallback timer; never two at once for one repository, and
-- none while the bar does not show the module. A pane whose shell is on
-- another host (ssh, by OSC 7) shows nothing rather than a local repository
-- at the same path. Clicking it opens the status.
--
-- leader G is the git folder, on the focused pane's repository:
--   s  status in a floating pane       l  lazygit in one (when installed)
--   c  copy HEAD's SHA                 b  copy the branch name
--   o  open the remote in the browser (gh browse, or the remote's URL made
--      into a web address when gh is missing or fails; copied instead when
--      ranma runs over SSH)
--   r  refresh the bar now
-- Options (settings panel, "git" group): git.format, git.interval,
-- git.untracked, git.status_command, git.lazygit, git.float, git.browse,
-- git.remote.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("The bar",
-- "Timers and processes", "Hooks").

ranma.option("git.format", {
  type = "string", default = "{branch}{dirty}{ab}",
  name = "Bar format",
  desc = "The module's text. {branch}; {dirty} ' *N' with N files changed; {ab} ' ↑A ↓B' "
    .. "against the upstream; and the bare numbers {staged} {changed} {untracked} {conflicts} {ahead} {behind}.",
})
ranma.option("git.interval", {
  type = "int", min = 0, max = 600, step = 5, default = 30, slider = false,
  name = "Fallback refresh",
  desc = "Seconds between two looks when nothing else asked for one; 0 never.",
})
ranma.option("git.untracked", {
  type = "bool", default = true,
  name = "Count untracked",
  desc = "Count untracked files as changed. Off is faster in a huge working tree.",
})
ranma.option("git.status_command", {
  type = "string", default = "git -c color.status=always status | less -R -+F -c",
  name = "Status command", desc = "What leader G s runs in the floating pane, in the pane's directory.",
})
ranma.option("git.lazygit", {
  type = "bool", default = true,
  name = "lazygit key", desc = "leader G l opens lazygit in a floating pane (when lazygit is installed).",
})
ranma.option("git.float", {
  type = "int", min = 20, max = 100, step = 5, default = 80,
  name = "Popup size", desc = "The floating pane's width and height, in percent of the workspace.",
})
ranma.option("git.browse", {
  type = "enum", choices = { "auto", "gh", "url" }, default = "auto",
  name = "Open the remote with",
  desc = "gh: gh browse. url: the remote's URL made into a web address. auto: gh when it is installed.",
})
ranma.option("git.remote", {
  type = "string", default = "origin",
  name = "Remote", desc = "The remote leader G o opens.",
})

-- Whether a program is on PATH, by looking: no process at load.
local function installed(name)
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    local f = io.open(dir .. "/" .. name, "r")
    if f then f:close(); return true end
  end
  return false
end

local HAS_LAZYGIT = installed("lazygit")
local HAS_GH = installed("gh")

local function hostname()
  local f = io.open("/proc/sys/kernel/hostname", "r")
  if not f then return os.getenv("HOSTNAME") end
  local h = f:read("l")
  f:close()
  return h
end
-- Short names: a shell may name the machine with its domain.
local function short(h) return h and h:match("^[^.]*"):lower() end
local HOST = short(hostname())

-- pane id -> true while its shell reports (OSC 7) being on another host.
local elsewhere = {}

-- The module ticks only while the bar shows it; a look nobody would see is
-- not taken.
local SHOWN_FOR = 3
local shown_at = nil

-- cwd -> the repository's top level (false outside one), from earlier looks.
local top = {}
-- repository (or cwd, before its top is known) -> its last status, or false
-- outside a repository.
local status = {}
-- key -> true while a look runs; "again" when one was asked for meanwhile.
local running = {}
-- How many directories `top` remembers before it starts over.
local REMEMBER = 256
local remembered = 0

local function shown()
  return shown_at and os.time() - shown_at <= SHOWN_FOR
end

local function key_of(cwd)
  return top[cwd] or cwd
end

-- `git status --porcelain=v2 --branch`, after the top level on its own line.
local function parse(out)
  local lines = {}
  for l in out:gmatch("[^\n]+") do lines[#lines + 1] = l end
  local s = { top = lines[1], staged = 0, changed = 0, untracked = 0, conflicts = 0 }
  for i = 2, #lines do
    local l = lines[i]
    local k, v = l:match("^# branch%.(%S+) (.*)$")
    if k == "oid" then s.oid = v
    elseif k == "head" then s.head = v
    elseif k == "upstream" then s.upstream = v
    elseif k == "ab" then
      local a, b = v:match("^%+(%d+) %-(%d+)$")
      s.ahead, s.behind = tonumber(a), tonumber(b)
    else
      local kind, xy = l:match("^(%S) (%S*)")
      if kind == "?" then s.untracked = s.untracked + 1
      elseif kind == "u" then s.conflicts = s.conflicts + 1
      elseif kind == "1" or kind == "2" then
        if xy:sub(1, 1) ~= "." then s.staged = s.staged + 1 end
        if xy:sub(2, 2) ~= "." then s.changed = s.changed + 1 end
      end
    end
  end
  if s.head == "(detached)" then
    s.branch, s.detached = (s.oid or ""):sub(1, 7), true
  else
    s.branch = s.head or "?"
  end
  return s
end

-- Look at cwd's repository. `again`: one already running is followed by
-- another once it ends (something changed meanwhile); without it, the
-- running one is answer enough.
local function look(cwd, again)
  if not cwd then return end
  local key = key_of(cwd)
  if running[key] then
    if again then running[key] = "again" end
    return
  end
  if top[cwd] == nil then
    remembered = remembered + 1
    if remembered > REMEMBER then top, status, remembered = {}, {}, 1 end
  end
  running[key] = true
  local untracked = ranma.get("git.untracked") and "" or " -uno"
  ranma.spawn({ "sh", "-c",
    "git rev-parse --show-toplevel && exec git --no-optional-locks status --porcelain=v2 --branch" .. untracked }, {
    cwd = cwd, timeout = 10,
    on_exit = function(r)
      local again = running[key] == "again"
      running[key] = nil
      if r.error or r.signal then
        -- A timeout, a directory that is gone, a git that cannot run: keep
        -- what was there, or nothing, so it is not asked again every tick.
        if status[key] == nil then status[key] = false end
      elseif r.code ~= 0 then
        top[cwd], status[cwd] = false, false
      else
        local s = parse(r.stdout or "")
        top[cwd] = s.top
        status[s.top] = s
        if key ~= s.top then status[key] = nil end
      end
      if again then look(cwd, true) end
    end,
  })
end

local function cwd_of(p)
  if not p or elsewhere[p.id] then return nil end
  return p:cwd()
end

local function focused_cwd()
  return cwd_of(ranma.pane())
end

local function refresh()
  if shown() then look(focused_cwd(), true) end
end

local function fill(s)
  local changed = s.staged + s.changed + s.untracked + s.conflicts
  local n = {
    branch = s.branch,
    staged = s.staged, changed = s.changed, untracked = s.untracked, conflicts = s.conflicts,
    ahead = s.ahead or 0, behind = s.behind or 0,
    dirty = changed > 0 and (" *" .. changed) or "",
  }
  local ab = ""
  if (s.ahead or 0) > 0 then ab = ab .. " ↑" .. s.ahead end
  if (s.behind or 0) > 0 then ab = ab .. " ↓" .. s.behind end
  n.ab = ab
  return (ranma.get("git.format"):gsub("{(%w+)}", function(k)
    local v = n[k]
    return v ~= nil and tostring(v) or nil
  end)), changed
end

local function popup(cmd)
  if not focused_cwd() then return ranma.notify("git: the pane has no local directory") end
  local size = ranma.get("git.float")
  ranma.action("exec " .. cmd)
  ranma.action("float_size " .. size .. " " .. size)
end

local function open_status()
  popup(ranma.get("git.status_command"))
end

-- Run a git command in the focused pane's directory and hand its first line
-- of output to `fn`; say why when it fails.
local function git_line(args, what, fn)
  local cwd = focused_cwd()
  if not cwd then return ranma.notify("git: the pane has no directory") end
  local cmd = { "git" }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  ranma.spawn(cmd, { cwd = cwd, timeout = 10, on_exit = function(r)
    local line = (r.stdout or ""):match("^[^\n]+")
    if r.code ~= 0 or not line then
      local err = (r.stderr or ""):match("^[^\n]+") or r.error or "failed"
      return ranma.notify("git: " .. what .. ": " .. err)
    end
    fn(line)
  end })
end

local function copy_sha()
  git_line({ "rev-parse", "HEAD" }, "no HEAD", function(sha)
    ranma.copy(sha)
    ranma.notify("copied " .. sha:sub(1, 12))
  end)
end

local function copy_branch()
  git_line({ "symbolic-ref", "--short", "HEAD" }, "no branch", function(name)
    ranma.copy(name)
    ranma.notify("copied " .. name)
  end)
end

-- A remote's URL as a web address: git@host:owner/repo.git,
-- ssh://git@host:22/owner/repo.git and https://user@host/owner/repo.git all
-- become https://host/owner/repo. nil for a local path.
local function web_url(url)
  url = url:gsub("%.git/?$", ""):gsub("/$", "")
  local host, path = url:match("^%w[%w+.-]*://[^/]*@([^/:]+)[:%d]*/(.+)$")
  if not host then host, path = url:match("^%w[%w+.-]*://([^/:]+)[:%d]*/(.+)$") end
  if not host then host, path = url:match("^[^/@]+@([^:/]+):/?(.+)$") end
  if not host then host, path = url:match("^([%w.-]+%.%w+):/?(.+)$") end
  if not host then return nil end
  return "https://" .. host .. "/" .. path
end

local function visit(url)
  if ranma.client().remote then
    ranma.copy(url)
    return ranma.notify("copied " .. url .. " (ranma runs on the server, not here)")
  end
  ranma.spawn({ "sh", "-c", "xdg-open \"$1\" || open \"$1\"", "sh", url }, { timeout = 10 })
  ranma.notify("opening " .. url)
end

local function browse()
  local how = ranma.get("git.browse")
  local remote = ranma.get("git.remote")
  local cwd = focused_cwd()
  if not cwd then return ranma.notify("git: the pane has no directory") end
  local use_gh = how == "gh" or (how == "auto" and HAS_GH)
  local function by_url()
    git_line({ "remote", "get-url", remote }, "no remote " .. remote, function(url)
      local web = web_url(url)
      if not web then return ranma.notify("git: " .. remote .. " is no web address: " .. url) end
      visit(web)
    end)
  end
  if use_gh and not ranma.client().remote then
    return ranma.spawn({ "gh", "browse" }, { cwd = cwd, timeout = 20, on_exit = function(r)
      if r.code == 0 then return end
      local why = (r.stderr or ""):match("^[^\n]+") or r.error or "failed"
      -- Not a GitHub repository, or gh not logged in: the URL still works.
      if how == "auto" then return by_url() end
      ranma.notify("gh browse: " .. why)
    end })
  end
  by_url()
end

ranma.module("git", {
  interval = 1,
  render = function()
    local was_shown = shown()
    shown_at = os.time()
    local cwd = focused_cwd()
    if not cwd then return nil end
    local s = status[key_of(cwd)]
    -- A directory never looked at, or the module just came into view.
    if s == nil or not was_shown then look(cwd, not was_shown) end
    if not s then return nil end
    local text, changed = fill(s)
    if text == "" then return nil end
    local style = s.conflicts > 0 and "urgent" or changed > 0 and "accent" or "normal"
    return { text = text, style = style }
  end,
  on_click = open_status,
})

ranma.on("cwd_change", function(e)
  local h = short(e.host)
  elsewhere[e.pane] = (h and h ~= "" and h ~= "localhost" and h ~= HOST) or nil
  local p = ranma.pane()
  if p and p.id == e.pane then refresh() end
end)
-- A command in the focused pane, or in another pane in the same repository
-- (a commit in the split beside it).
ranma.on("command_finished", function(e)
  local p = ranma.pane()
  if not p then return end
  if p.id == e.pane then return refresh() end
  local here, there = focused_cwd(), cwd_of(ranma.pane(e.pane))
  if here and there and top[here] and top[here] == top[there] then refresh() end
end)
ranma.on("pane_close", function(e) elsewhere[e.pane] = nil end)
ranma.on("focus_change", refresh)

-- The fallback: a branch switched from outside, a fetch that moved upstream.
local function tick()
  local secs = ranma.get("git.interval")
  if secs > 0 then
    refresh()
    ranma.defer(secs * 1000, tick)
  else
    ranma.defer(30000, tick)
  end
end
ranma.defer(1000, tick)

ranma.bind("shift+g", { folder = "git", group = "plugins" })
ranma.bind("shift+g s", open_status, { desc = "status", exit = true })
if HAS_LAZYGIT then
  ranma.bind("shift+g l", function()
    if not ranma.get("git.lazygit") then return ranma.notify("git: lazygit is off (git.lazygit)") end
    popup("lazygit")
  end, { desc = "lazygit", exit = true })
end
ranma.bind("shift+g c", copy_sha, { desc = "copy HEAD's SHA", exit = true })
ranma.bind("shift+g b", copy_branch, { desc = "copy the branch", exit = true })
ranma.bind("shift+g o", browse, { desc = "open the remote", exit = true })
ranma.bind("shift+g r", function() look(focused_cwd(), true) end, { desc = "refresh the bar", exit = true })
