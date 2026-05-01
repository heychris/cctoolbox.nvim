local M = {}

local NS = vim.api.nvim_create_namespace("cctoolbox_tasks")

-- Build characters from codepoints to avoid encoding issues with private-use glyphs
local function ch(n)
    return vim.fn.nr2char(n)
end

local SPINNER = {
    ch(0x280B),
    ch(0x2819),
    ch(0x2839),
    ch(0x2838),
    ch(0x283C),
    ch(0x2834),
    ch(0x2826),
    ch(0x2827),
    ch(0x2807),
    ch(0x280F),
}
local CAP_L = ch(0xE0B6) -- Nerd Font: left rounded pill cap
local CAP_R = ch(0xE0B4) -- Nerd Font: right rounded pill cap
local ICON_DONE = ch(0x25CB) -- ○ white circle
local ICON_ERROR = ch(0x2717) -- ✗
local ICON_CANCELLED = ch(0x25CC) -- ◌ dotted circle

local _task_ids = {}
local _timers = {}
local _start_ms = {}
local _frame_idx = {}

local function format_elapsed(ms)
    local s = math.floor(ms / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function stop_timer(extmark_id)
    local t = _timers[extmark_id]
    if t then
        t:stop()
        t:close()
        _timers[extmark_id] = nil
    end
    _frame_idx[extmark_id] = nil
end

local function pill(segments)
    local t = { { CAP_L, "CctoolboxCap" } }
    for _, s in ipairs(segments) do
        t[#t + 1] = s
    end
    t[#t + 1] = { CAP_R, "CctoolboxCap" }
    return t
end

local function set_virt(bufnr, extmark_id, virt)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})
    for _, mark in ipairs(marks) do
        if mark[1] == extmark_id then
            vim.api.nvim_buf_set_extmark(bufnr, NS, mark[2], mark[3], {
                id = extmark_id,
                virt_text = virt,
                virt_text_pos = "eol",
                right_gravity = false,
            })
            return true
        end
    end
    return false
end

function M.place(bufnr, lnum, task_id)
    local id = vim.api.nvim_buf_set_extmark(bufnr, NS, lnum, 0, {
        virt_text = pill({
            { " " .. SPINNER[1] .. " ", "CctoolboxSpinner" },
            { "Working", "CctoolboxLabel" },
            { " \xC2\xB7 ", "CctoolboxTimer" },
            { "0:00 ", "CctoolboxTimer" },
        }),
        virt_text_pos = "eol",
        right_gravity = false,
    })
    _task_ids[id] = task_id
    _start_ms[id] = vim.uv.now()
    _frame_idx[id] = 1

    local timer = vim.uv.new_timer()
    _timers[id] = timer
    timer:start(
        100,
        100,
        vim.schedule_wrap(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then
                stop_timer(id)
                return
            end
            _frame_idx[id] = (_frame_idx[id] % #SPINNER) + 1
            local elapsed = vim.uv.now() - _start_ms[id]
            local virt = pill({
                { " " .. SPINNER[_frame_idx[id]] .. " ", "CctoolboxSpinner" },
                { "Working", "CctoolboxLabel" },
                { " \xC2\xB7 ", "CctoolboxTimer" },
                { format_elapsed(elapsed) .. " ", "CctoolboxTimer" },
            })
            if not set_virt(bufnr, id, virt) then
                stop_timer(id)
            end
        end)
    )

    return id
end

function M.update(bufnr, extmark_id, status)
    if status == "running" then
        return
    end

    stop_timer(extmark_id)
    local elapsed = _start_ms[extmark_id] and (vim.uv.now() - _start_ms[extmark_id]) or 0

    local virt
    if status == "done" then
        virt = pill({
            { " " .. ICON_DONE .. " ", "CctoolboxDoneIcon" },
            { "Worked for " .. format_elapsed(elapsed) .. " ", "CctoolboxLabel" },
        })
    elseif status == "error" then
        virt = pill({
            { " " .. ICON_ERROR .. " ", "CctoolboxError" },
            { "Error ", "CctoolboxLabel" },
        })
    elseif status == "cancelled" then
        virt = pill({
            { " " .. ICON_CANCELLED .. " Cancelled ", "CctoolboxLabel" },
        })
    end

    if virt then
        set_virt(bufnr, extmark_id, virt)
    end
end

function M.remove(bufnr, extmark_id)
    stop_timer(extmark_id)
    _start_ms[extmark_id] = nil
    pcall(vim.api.nvim_buf_del_extmark, bufnr, NS, extmark_id)
    _task_ids[extmark_id] = nil
end

function M.get_task_id(bufnr, extmark_id)
    return _task_ids[extmark_id]
end

function M.get_task_at_cursor()
    local bufnr = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { row, 0 }, { row, -1 }, {})
    if marks and marks[1] then
        return _task_ids[marks[1][1]]
    end
    return nil
end

return M
