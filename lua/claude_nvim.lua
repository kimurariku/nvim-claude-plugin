local M = {}

local state = {
  sessions = {},  -- list of { buf, cwd, started }
  idx      = 0,   -- current session index (1-based)
  win      = nil,
}

local input_state = {
  buf = nil,
  win = nil,
}

local claude_cmd    = vim.fn.expand("$HOME") .. "/.npm-global/bin/claude"
local template_dir  = vim.fn.expand("$HOME") .. "/.claude/templates/"
local projects_dir  = vim.fn.expand("$HOME") .. "/.claude/projects/"
local agent_dir     = vim.fn.expand("$HOME") .. "/.claude/agents/"
local status_timer  = nil
local cached_stats  = nil

-- ── helpers ──────────────────────────────────────────────────────────

local function buf_valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function input_win_valid()
  return input_state.win and vim.api.nvim_win_is_valid(input_state.win)
end

local function current_session()
  return state.sessions[state.idx]
end

-- ── status ───────────────────────────────────────────────────────────

local function latest_session_stats()
  local handle = io.popen("ls -t " .. projects_dir .. "*/*.jsonl 2>/dev/null | head -1")
  if not handle then return nil end
  local path = handle:read("*l")
  handle:close()
  if not path or path == "" then return nil end

  local handle2 = io.popen("tail -20 '" .. path .. "' 2>/dev/null")
  if not handle2 then return nil end
  local content = handle2:read("*a")
  handle2:close()

  local model, input_tok, output_tok, cache_read = "unknown", 0, 0, 0
  for line in content:gmatch("[^\n]+") do
    local ok, d = pcall(vim.json.decode, line)
    if ok and d then
      local msg = d.message or {}
      if msg.model and msg.model ~= "" then model = msg.model end
      local u = msg.usage or {}
      input_tok  = u.input_tokens or input_tok
      output_tok = u.output_tokens or output_tok
      cache_read = u.cache_read_input_tokens or cache_read
    end
  end
  return { model = model, input = input_tok, output = output_tok, cache = cache_read }
end

local function update_winbar()
  if not win_valid() then return end
  local parts = {}
  for i, s in ipairs(state.sessions) do
    local label = " " .. vim.fn.fnamemodify(s.cwd, ":~") .. " "
    if i == state.idx then
      table.insert(parts, "%#TabLineSel#" .. label .. "%#TabLine#")
    else
      table.insert(parts, label)
    end
  end

  local stats = cached_stats
  local model = stats and stats.model:gsub("claude%-", ""):gsub("%-2%d%d%d%d%d%d%d", "") or "?"
  local right = stats
    and string.format(" %s  in:%d out:%d cache:%d ", model, stats.input, stats.output, stats.cache)
    or string.format(" %s ", model)

  vim.wo[state.win].winbar = table.concat(parts, "│") .. "%=" .. right
end

local function refresh_stats()
  cached_stats = latest_session_stats()
  update_winbar()
  vim.cmd("redrawstatus")
end

local function start_status_timer()
  if status_timer then return end
  status_timer = vim.loop.new_timer()
  status_timer:start(0, 5000, vim.schedule_wrap(refresh_stats))
end

-- ── session management ────────────────────────────────────────────────

local function set_session_keymaps(buf)
  local opts = { buffer = buf, silent = true }
  vim.keymap.set("t", "<M-Right>", M.next_session, vim.tbl_extend("force", opts, { desc = "Claude: Next session" }))
  vim.keymap.set("t", "<M-Left>",  M.prev_session, vim.tbl_extend("force", opts, { desc = "Claude: Prev session" }))
end

local function show_session(session)
  if not win_valid() then return end
  vim.api.nvim_set_current_win(state.win)

  if not session.started then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(state.win, buf)
    vim.fn.termopen(claude_cmd, { cwd = session.cwd })
    session.buf     = vim.api.nvim_get_current_buf()
    session.started = true
    set_session_keymaps(session.buf)
  else
    vim.api.nvim_win_set_buf(state.win, session.buf)
  end

  update_winbar()
end

local function open_win()
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd L")        -- pin to far right, full height
  vim.cmd("vertical resize 90")
  start_status_timer()
end

local function pick_directory(prompt, callback)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = prompt,
    finder = finders.new_oneshot_job(
      { "find", vim.fn.getcwd(), "-maxdepth", "4", "-type", "d", "-not", "-path", "*/.*" },
      { entry_maker = function(e)
          return { value = e, display = vim.fn.fnamemodify(e, ":~"), ordinal = e }
        end }
    ),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then callback(sel.value) end
      end)
      return true
    end,
  }):find()
end

local function ensure_claude_open()
  if #state.sessions == 0 then
    pick_directory("Claude dir", function(path)
      table.insert(state.sessions, { buf = nil, cwd = path, started = false })
      state.idx = 1
      if not win_valid() then open_win() end
      show_session(current_session())
    end)
    return false  -- async: session opens inside callback
  end
  if not win_valid() then
    open_win()
    show_session(current_session())
  end
  return true
end

-- ── send to current terminal ──────────────────────────────────────────

local function send(text)
  local s = current_session()
  if not s or not buf_valid(s.buf) then return end
  local job_id = vim.b[s.buf].terminal_job_id
  if job_id then vim.fn.chansend(job_id, text) end
end

-- ── input buffer ─────────────────────────────────────────────────────

local function send_input()
  if not buf_valid(input_state.buf) then return end
  local lines = vim.api.nvim_buf_get_lines(input_state.buf, 0, -1, false)
  local text = vim.trim(table.concat(lines, "\n"))
  if text == "" then return end

  if not ensure_claude_open() then return end

  send(text .. "\r")
  vim.api.nvim_buf_set_lines(input_state.buf, 0, -1, false, { "" })

  if input_win_valid() then
    vim.api.nvim_win_close(input_state.win, false)
    input_state.win = nil
  end
end

function M.open_input()
  if not buf_valid(input_state.buf) then
    input_state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[input_state.buf].filetype  = "markdown"
    vim.bo[input_state.buf].bufhidden = "hide"
    vim.api.nvim_buf_set_name(input_state.buf, "Claude Input")

    local bopts = { buffer = input_state.buf, silent = true }
    vim.keymap.set("n", "<C-j>", send_input, vim.tbl_extend("force", bopts, { desc = "Claude: Send" }))
    vim.keymap.set("n", "q", function()
      if input_win_valid() then
        vim.api.nvim_win_close(input_state.win, false)
        input_state.win = nil
      end
    end, vim.tbl_extend("force", bopts, { desc = "Claude: Close input" }))
  end

  if input_win_valid() then
    vim.api.nvim_set_current_win(input_state.win)
    vim.cmd("startinsert")
    return
  end

  -- Open below the left-side area (never touch Claude's right column)
  if win_valid() then
    if vim.api.nvim_get_current_win() == state.win then
      vim.cmd("wincmd h")
    end
  end
  vim.cmd("belowright split")
  vim.cmd("resize 10")
  vim.api.nvim_win_set_buf(0, input_state.buf)
  input_state.win = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

-- ── templates ────────────────────────────────────────────────────────

local function load_templates()
  local templates = {}
  local files = vim.fn.glob(template_dir .. "*.md", false, true)
  for _, path in ipairs(files) do
    local name = vim.fn.fnamemodify(path, ":t:r"):gsub("_", " ")
    local text = table.concat(vim.fn.readfile(path), "\n") .. "\n"
    table.insert(templates, { name = name, text = text })
  end
  return templates
end

function M.template()
  local templates = load_templates()
  if #templates == 0 then
    vim.notify("No templates found in " .. template_dir, vim.log.levels.WARN)
    return
  end

  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers   = require("telescope.previewers")

  local previewer = previewers.new_buffer_previewer({
    title = "Preview",
    define_preview = function(self, entry)
      local lines = vim.split(entry.value.text, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "markdown"
    end,
  })

  pickers.new({}, {
    prompt_title = "Claude Template",
    finder = finders.new_table({
      results = templates,
      entry_maker = function(t)
        return { value = t, display = t.name, ordinal = t.name }
      end,
    }),
    sorter    = conf.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local t = action_state.get_selected_entry().value
        -- Load template into input buffer and open it
        M.open_input()
        vim.schedule(function()
          local lines = vim.split(t.text, "\n", { plain = true })
          vim.api.nvim_buf_set_lines(input_state.buf, 0, -1, false, lines)
          vim.cmd("normal! G$")
          vim.cmd("startinsert!")
        end)
      end)
      return true
    end,
  }):find()
end

-- ── subagents ────────────────────────────────────────────────────────

function M.subagent()
  local agents = {}
  local files = vim.fn.glob(agent_dir .. "*.md", false, true)
  for _, path in ipairs(files) do
    local lines = vim.fn.readfile(path)
    local name = vim.fn.fnamemodify(path, ":t:r")
    local description = ""
    for _, line in ipairs(lines) do
      local n = line:match("^name:%s*(.+)")
      if n then name = vim.trim(n) end
      local ja = line:match("^ja_description:%s*(.+)")
      if ja then description = vim.trim(ja) end
      if description == "" then
        local d = line:match("^description:%s*(.+)")
        if d then description = vim.trim(d) end
      end
    end
    table.insert(agents, {
      name        = name,
      description = description,
      text        = table.concat(lines, "\n"),
      path        = path,
    })
  end

  if #agents == 0 then
    vim.notify("No agents found in " .. agent_dir, vim.log.levels.WARN)
    return
  end

  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers   = require("telescope.previewers")

  local previewer = previewers.new_buffer_previewer({
    title = "Agent",
    define_preview = function(self, entry)
      local lines = vim.split(entry.value.text, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "markdown"
    end,
  })

  local in_preview = false

  pickers.new({}, {
    prompt_title = "Claude Sub-Agents",
    finder = finders.new_table({
      results = agents,
      entry_maker = function(a)
        local display = a.description ~= "" and (a.name .. "  " .. a.description) or a.name
        return { value = a, display = display, ordinal = a.name .. " " .. a.description }
      end,
    }),
    sorter    = conf.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<Right>", function() in_preview = true end)
      map("i", "<Left>",  function() in_preview = false end)

      map("i", "<Up>", function()
        if in_preview then
          actions.preview_scrolling_up(prompt_bufnr)
        else
          actions.move_selection_previous(prompt_bufnr)
        end
      end)

      map("i", "<Down>", function()
        if in_preview then
          actions.preview_scrolling_down(prompt_bufnr)
        else
          actions.move_selection_next(prompt_bufnr)
        end
      end)

      actions.select_default:replace(function()
        in_preview = false
        actions.close(prompt_bufnr)
        local a = action_state.get_selected_entry().value
        vim.cmd("edit " .. vim.fn.fnameescape(a.path))
      end)
      return true
    end,
  }):find()
end

-- ── public API ────────────────────────────────────────────────────────

function M.status_line()
  local s = cached_stats
  if not s then return "" end
  local model = s.model:gsub("claude%-", ""):gsub("%-2%d%d%d%d%d%d%d", "")
  return string.format(" %s  in:%d out:%d cache:%d", model, s.input, s.output, s.cache)
end

function M.toggle()
  if win_valid() then
    if vim.api.nvim_get_current_win() == state.win then
      vim.api.nvim_win_close(state.win, false)
      state.win = nil
    else
      vim.api.nvim_set_current_win(state.win)
    end
    return
  end

  if not ensure_claude_open() then return end
end

function M.new_session()
  pick_directory("New Claude dir", function(path)
    table.insert(state.sessions, { buf = nil, cwd = path, started = false })
    state.idx = #state.sessions
    if not win_valid() then open_win() end
    show_session(current_session())
  end)
end

function M.next_session()
  if #state.sessions <= 1 then return end
  state.idx = (state.idx % #state.sessions) + 1
  if win_valid() then show_session(current_session()) end
end

function M.prev_session()
  if #state.sessions <= 1 then return end
  state.idx = ((state.idx - 2) % #state.sessions) + 1
  if win_valid() then show_session(current_session()) end
end

-- ── setup ─────────────────────────────────────────────────────────────

function M.setup(opts)
  opts = opts or {}
  vim.api.nvim_create_user_command("Claude",          M.toggle,    {})
  vim.api.nvim_create_user_command("ClaudeNew",       M.new_session, {})
  vim.api.nvim_create_user_command("ClaudeInput",     M.open_input,  {})
  vim.api.nvim_create_user_command("ClaudeTemplate",  M.template,    {})
  vim.api.nvim_create_user_command("ClaudeSubAgent",  M.subagent,    {})

  vim.keymap.set("n", opts.new_key      or "<M-n>",    M.new_session, { desc = "Claude: New session" })
  vim.keymap.set("n", opts.input_key    or "<M-i>",    M.open_input,  { desc = "Claude: Open input" })
  vim.keymap.set("n", opts.template_key or "<leader>t", M.template,   { desc = "Claude: Template" })
  vim.keymap.set("t", "<M-n>",  M.new_session,                         { desc = "Claude: New session (terminal)" })
  vim.keymap.set("t", "<M-i>",  M.open_input,                          { desc = "Claude: Open input (terminal)" })
  vim.keymap.set("t", "<C-t>",  M.template,                            { desc = "Claude: Template (terminal)" })
  vim.keymap.set("t", "<C-h>",  "<C-\\><C-n><C-w>h",                  { desc = "Terminal: Move to left window" })
end

return M
