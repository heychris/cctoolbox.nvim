local config = require("cctoolbox.config")

local M = {}

local function job_path(name)
  return config.values.jobs_dir .. name .. ".md"
end

local function default_template(name)
  return string.format(
    "---\ntag: %s\n---\n\n# Job: %s\n\n## Description\n\n## Tasks\n\n## Notes\n",
    name, name
  )
end

function M.create(name, opts)
  opts = opts or {}
  vim.fn.mkdir(config.values.jobs_dir, "p")
  local content = opts.content or default_template(name)
  local f = io.open(job_path(name), "w")
  if f then
    f:write(content)
    f:close()
  end
end

function M.read(name)
  local f = io.open(job_path(name), "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- Reads the `tag:` field from YAML frontmatter. Returns nil if absent.
function M.read_tag(name)
  local content = M.read(name)
  if not content then return nil end
  return content:match("^%-%-%-%s*\ntag:%s*(%S+)")
end

function M.delete(name)
  local path = job_path(name)
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

function M.list()
  local dir = config.values.jobs_dir
  if vim.fn.isdirectory(dir) == 0 then return {} end
  local names = {}
  for _, f in ipairs(vim.fn.glob(dir .. "*.md", false, true)) do
    table.insert(names, vim.fn.fnamemodify(f, ":t:r"))
  end
  return names
end

function M.resolve_refs(text)
  return text:gsub("@(%w+)", function(name)
    local content = M.read(name)
    if content then
      return string.format("\n\n--- Job Context: %s ---\n%s\n---\n", name, content)
    end
    return "@" .. name
  end)
end

-- Creates an acwrite scratch buffer loaded with the job's file content.
-- BufWriteCmd on this buffer saves back to the job file so :w works naturally.
function M.make_popup_buf(name)
  local path = job_path(name)
  local content = M.read(name) or default_template(name)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(buf, "job://" .. name .. "#" .. buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
  vim.bo[buf].modified = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local f = io.open(path, "w")
      if f then
        f:write(table.concat(lines, "\n"))
        f:close()
      end
      vim.bo[buf].modified = false
      vim.notify("Saved: @" .. name, vim.log.levels.INFO)
    end,
  })

  return buf
end

-- Opens the job file in a centered floating popup. :w saves back to disk.
function M.open_popup(name)
  local buf = M.make_popup_buf(name)

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " @" .. name .. " ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = true

  local function close()
    if vim.bo[buf].modified then
      vim.ui.select({ "Save and close", "Discard and close", "Cancel" }, {
        prompt = "Unsaved changes —",
      }, function(choice)
        if choice == "Save and close" then
          vim.api.nvim_buf_call(buf, function() vim.cmd("silent write") end)
          if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        elseif choice == "Discard and close" then
          vim.bo[buf].modified = false
          if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        end
      end)
    else
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Close job popup" })
end

-- Opens an oil-style list buffer for managing jobs.
-- <CR>   — edit the job under the cursor (returns to list on close)
-- n      — create a new job and open it
-- :w     — delete any jobs whose lines were removed, then close
-- q      — close without changes
function M.open_list()
  local original_names = M.list()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "cctoolbox-jobs"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_name(buf, "cctoolbox://jobs#" .. buf)

  local display = #original_names > 0 and original_names or {}
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
  vim.bo[buf].modified = false

  local width  = math.min(48, math.floor(vim.o.columns * 0.4))
  local height = math.max(#display + 2, 6)
  height = math.min(height, math.floor(vim.o.lines * 0.6))

  local win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    width      = width,
    height     = height,
    row        = math.floor((vim.o.lines - height) / 2),
    col        = math.floor((vim.o.columns - width) / 2),
    border     = "rounded",
    title      = " Jobs ",
    title_pos  = "center",
    footer     = { { " <CR> edit  n new  :w save  q quit ", "Comment" } },
    footer_pos = "center",
  })
  vim.wo[win].cursorline = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  -- :w — apply deletions
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local kept = {}
      for _, name in ipairs(current) do
        if name ~= "" then kept[name] = true end
      end
      local deleted = {}
      for _, name in ipairs(original_names) do
        if not kept[name] then
          M.delete(name)
          table.insert(deleted, "@" .. name)
        end
      end
      vim.bo[buf].modified = false
      if #deleted > 0 then
        vim.notify("Deleted: " .. table.concat(deleted, ", "), vim.log.levels.INFO)
      end
      close()
    end,
  })

  -- <CR> — open job under cursor
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local name = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not name or name == "" then return end
    -- Check it's a known job (user may have typed a new name — use `n` for that)
    if vim.fn.filereadable(job_path(name)) ~= 1 then return end
    M.open_popup(name)
  end, { buffer = buf, nowait = true, desc = "Edit job" })

  -- n — new job
  vim.keymap.set("n", "n", function()
    require("cctoolbox.ui.prompt").open({
      title = "New job name (@reference)",
      on_submit = function(name)
        if not name or name == "" then return end
        M.create(name, {})
        -- Append to list so it's visible
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if #lines == 1 and lines[1] == "" then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { name })
        else
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, { name })
        end
        -- Add to original_names so :w doesn't delete it
        table.insert(original_names, name)
        vim.bo[buf].modified = false
        M.open_popup(name)
      end,
      on_cancel = function() end,
    })
  end, { buffer = buf, nowait = true, desc = "New job" })

  -- q — close without saving
  vim.keymap.set("n", "q", function()
    vim.bo[buf].modified = false
    close()
  end, { buffer = buf, nowait = true, desc = "Close jobs list" })
end

-- Kept for backward compat with CCToolbox job commands.
function M.pick()
  M.open_list()
end

return M
