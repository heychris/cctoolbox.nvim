local claude = require("cctoolbox.core.claude")
local marker = require("cctoolbox.ui.marker")
local panel = require("cctoolbox.ui.panel")
local job = require("cctoolbox.features.job")

local M = {}

local _tasks = {}
local _counter = 0

local function next_id()
    _counter = _counter + 1
    return "task_" .. _counter
end

function M._reset()
    _tasks = {}
    _counter = 0
end

function M._get(id)
    return _tasks[id]
end

function M.register(opts)
    local id = next_id()
    _tasks[id] = {
        id = id,
        bufnr = opts.bufnr,
        lnum = opts.lnum,
        range_size = opts.range[2] - opts.range[1] + 1,
        description = opts.description,
        selected_lines = opts.selected_lines or {},
        status = "pending",
        output = {},
        handle = nil,
        extmark_id = nil,
        panel_handle = nil,
        session_id = nil,
    }
    return id
end

function M.append_output(id, chunk)
    local t = _tasks[id]
    if not t then
        return
    end
    table.insert(t.output, chunk)
    if t.panel_handle then
        t.panel_handle.append(chunk)
    end
end

function M.get_output(id)
    local t = _tasks[id]
    if not t then
        return ""
    end
    return table.concat(t.output, "")
end

-- Extracts the last ```diff block from markdown text. Returns nil if none found.
function M.extract_diff_block(text)
    if not text then
        return nil
    end
    local last
    for block in text:gmatch("```diff\n(.-)\n```") do
        last = block
    end
    return last
end

-- Kept for tests and fallback use.
function M.extract_code_block(text)
    if not text then
        return nil
    end
    local last
    for block in text:gmatch("```[^\n]*\n(.-)\n```") do
        last = block
    end
    if last then
        last = last:gsub("\n+$", "")
    end
    return last
end

-- Applies a unified diff to lines range[1]..range[2] using the `patch` command.
-- original_lines is a table of strings (no trailing newlines).
-- Returns new_line_count, nil on success or nil, err_string on failure.
function M.apply_diff_to_range(bufnr, range, diff_text, original_lines)
    local tmp_orig = vim.fn.tempname()
    local tmp_patch = vim.fn.tempname()
    local tmp_out = vim.fn.tempname()

    vim.fn.writefile(original_lines, tmp_orig)
    vim.fn.writefile(vim.split(diff_text, "\n", { plain = true }), tmp_patch)

    vim.fn.system(
        "patch -f -s -o "
            .. vim.fn.shellescape(tmp_out)
            .. " "
            .. vim.fn.shellescape(tmp_orig)
            .. " "
            .. vim.fn.shellescape(tmp_patch)
    )
    local ok = vim.v.shell_error == 0

    vim.fn.delete(tmp_orig)
    vim.fn.delete(tmp_patch)

    if not ok then
        vim.fn.delete(tmp_out)
        return nil, "patch did not apply cleanly — view output to inspect the diff"
    end

    local new_lines = vim.fn.readfile(tmp_out)
    vim.fn.delete(tmp_out)

    vim.api.nvim_buf_set_lines(bufnr, range[1] - 1, range[2], false, new_lines)
    return #new_lines, nil
end

-- Kept for tests.
function M.apply_to_range(bufnr, range, text)
    local lines = vim.split(text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, range[1] - 1, range[2], false, lines)
end

-- Derives the current range from the extmark's live position + stored range_size.
function M.get_current_range(id)
    local t = _tasks[id]
    if not t or not t.extmark_id then
        return nil
    end
    local ns = vim.api.nvim_get_namespaces()["cctoolbox_tasks"]
    local marks = vim.api.nvim_buf_get_extmarks(t.bufnr, ns, 0, -1, {})
    for _, mark in ipairs(marks) do
        if mark[1] == t.extmark_id then
            local start_line = mark[2] + 1
            return { start_line, start_line + t.range_size - 1 }
        end
    end
    return nil
end

function M.get_status(id)
    if not _tasks[id] then
        return nil
    end
    return _tasks[id].status
end

function M.set_status(id, status)
    if not _tasks[id] then
        return
    end
    _tasks[id].status = status
    local t = _tasks[id]
    if t.extmark_id and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
        marker.update(t.bufnr, t.extmark_id, status)
    end
end

function M.cancel(id)
    if not _tasks[id] then
        return
    end
    local t = _tasks[id]
    if t.handle then
        pcall(function()
            t.handle:kill(9)
        end)
        t.handle = nil
    end
    M.set_status(id, "cancelled")
    if t.extmark_id and t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
        marker.remove(t.bufnr, t.extmark_id)
    end
end

function M.list_active()
    local active = {}
    for _, t in pairs(_tasks) do
        if t.status == "pending" or t.status == "running" then
            table.insert(active, t)
        end
    end
    return active
end

function M.show_progress(id)
    local t = _tasks[id]
    if not t then
        return
    end
    local h = panel.get_or_create("cctoolbox_task_" .. id)
    t.panel_handle = h
    h.replace("## Task\n" .. t.description .. "\n\n---\n\n" .. M.get_output(id))
    if vim.api.nvim_win_is_valid(h.win) then
        vim.api.nvim_set_current_win(h.win)
    end
end

local function on_done(id)
    local t = _tasks[id]
    if not t then
        return
    end
    local diff = M.extract_diff_block(M.get_output(id))
    local range = M.get_current_range(id)
    if diff and range and vim.api.nvim_buf_is_valid(t.bufnr) then
        local new_size, err = M.apply_diff_to_range(t.bufnr, range, diff, t.selected_lines)
        if err then
            M.set_status(id, "error")
            M.append_output(id, "\n\n**Patch error:** " .. err)
            vim.notify(
                "cc-toolbox: patch failed — press <leader>cct on marker to view",
                vim.log.levels.WARN
            )
        else
            t.range_size = new_size
            M.set_status(id, "done")
        end
    else
        M.set_status(id, "error")
        vim.notify(
            "cc-toolbox: no diff in response — press <leader>cct on marker to view",
            vim.log.levels.WARN
        )
    end
end

function M.suggest_change(id)
    local t = _tasks[id]
    if not t then
        return
    end

    -- Snapshot current range lines now; user may not submit the prompt immediately.
    local range = M.get_current_range(id)
    local current_lines = range
            and vim.api.nvim_buf_get_lines(t.bufnr, range[1] - 1, range[2], false)
        or {}

    require("cctoolbox.ui.prompt").open({
        title = "Suggest Change",
        multiline = true,
        on_submit = function(suggestion)
            if not suggestion or suggestion == "" then
                return
            end

            t.selected_lines = current_lines
            t.output = {}
            M.set_status(id, "running")

            local resolved = job.resolve_refs(suggestion)
            local current_code = table.concat(current_lines, "\n")
            local prompt = string.format(
                "Current code in the range:\n```\n%s\n```\n\nRequested change: %s",
                current_code,
                resolved
            )

            t.handle = claude.stream(prompt, {
                persist_session = true,
                resume_session_id = t.session_id,
                append_system_prompt = M.SYSTEM_PROMPT,
                allowed_tools = M.ALLOWED_TOOLS,
            }, function(chunk)
                M.append_output(id, chunk)
            end, function(_, err, session_id)
                if session_id then
                    t.session_id = session_id
                end
                if err then
                    M.set_status(id, "error")
                    M.append_output(id, "\n\n**Error:** " .. err)
                    vim.notify(
                        "cc-toolbox task error — press <leader>cct on marker to view",
                        vim.log.levels.ERROR
                    )
                else
                    M.set_status(id, "done")
                    on_done(id)
                end
            end)
        end,
        on_cancel = function() end,
    })
end

-- Shows the menu for the task under the cursor. Returns true if a task was found.
function M.show_menu_at_cursor()
    local task_id = marker.get_task_at_cursor()
    if not task_id then
        return false
    end
    local t = _tasks[task_id]
    if not t then
        return false
    end

    local choices = { "View output" }
    if t.status == "done" or t.status == "error" then
        table.insert(choices, "Suggest Change")
    end
    if t.status == "running" or t.status == "pending" then
        table.insert(choices, "Cancel")
    end

    vim.ui.select(choices, {
        prompt = "[" .. t.status .. "] " .. t.description:sub(1, 50),
    }, function(choice)
        if choice == "View output" then
            M.show_progress(task_id)
        elseif choice == "Suggest Change" then
            M.suggest_change(task_id)
        elseif choice == "Cancel" then
            M.cancel(task_id)
        end
    end)
    return true
end

M.ALLOWED_TOOLS = { "Read", "Bash" }

M.SYSTEM_PROMPT = [[
You are a coding assistant. Produce ONLY a unified diff showing the minimal changes needed to complete the task.
Output a single fenced code block with the ```diff language tag. No explanation or prose outside the block.
The diff must be relative to the provided code snippet (treat it as a standalone file starting at line 1).
Use `--- a/code` and `+++ b/code` as the file headers in the diff.
Read files and run read-only commands to gather context if needed.
]]

function M.run(opts)
    if M.show_menu_at_cursor() then
        return
    end

    opts = opts or {}
    local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    local range = opts.range or { cursor_line, cursor_line }
    local lnum = range[1] - 1

    local selected_lines = vim.api.nvim_buf_get_lines(bufnr, range[1] - 1, range[2], false)
    local selected_text = table.concat(selected_lines, "\n")

    local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")

    require("cctoolbox.ui.prompt").open({
        title = "Task",
        multiline = true,
        on_submit = function(description)
            if not description or description == "" then
                return
            end

            local id = M.register({
                bufnr = bufnr,
                lnum = lnum,
                range = range,
                description = description,
                selected_lines = selected_lines,
            })
            local t = _tasks[id]

            t.extmark_id = marker.place(bufnr, lnum, id)
            M.set_status(id, "running")

            local resolved = job.resolve_refs(description)
            local prompt = string.format(
                "File: %s\n\nSelected code (lines %d\xE2\x80\x93%d):\n```\n%s\n```\n\nTask: %s",
                filename,
                range[1],
                range[2],
                selected_text,
                resolved
            )

            t.handle = claude.stream(prompt, {
                persist_session = true,
                append_system_prompt = M.SYSTEM_PROMPT,
                allowed_tools = M.ALLOWED_TOOLS,
            }, function(chunk)
                M.append_output(id, chunk)
            end, function(_, err, session_id)
                if session_id then
                    t.session_id = session_id
                end
                if err then
                    M.set_status(id, "error")
                    M.append_output(id, "\n\n**Error:** " .. err)
                    vim.notify(
                        "cc-toolbox task error — press <leader>cct on marker to view",
                        vim.log.levels.ERROR
                    )
                else
                    M.set_status(id, "done")
                    on_done(id)
                end
            end)
        end,
        on_cancel = function() end,
    })
end

return M
