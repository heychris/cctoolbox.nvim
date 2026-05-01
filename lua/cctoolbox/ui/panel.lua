local config = require("cctoolbox.config")

local M = {}

local _panels = {}

local function make_handle(name, buf, win)
    local handle = { buf = buf, win = win }

    function handle.append(text)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        local lines = vim.split(text, "\n", { plain = true })
        local modifiable = vim.bo[buf].modifiable
        vim.bo[buf].modifiable = true
        local line_count = vim.api.nvim_buf_line_count(buf)
        -- If buffer is empty (single empty line), replace it
        local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if #current == 1 and current[1] == "" then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        else
            vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, lines)
        end
        vim.bo[buf].modifiable = modifiable
        if vim.api.nvim_win_is_valid(win) then
            local new_count = vim.api.nvim_buf_line_count(buf)
            vim.api.nvim_win_set_cursor(win, { new_count, 0 })
        end
    end

    function handle.replace(text)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        local lines = vim.split(text, "\n", { plain = true })
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_cursor(win, { 1, 0 })
        end
    end

    function handle.close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        _panels[name] = nil
    end

    return handle
end

function M.get_or_create(name)
    local existing = _panels[name]
    if
        existing
        and vim.api.nvim_win_is_valid(existing.win)
        and vim.api.nvim_buf_is_valid(existing.buf)
    then
        return existing
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = false

    local width = (config.values.panel and config.values.panel.width) or 60
    local win = vim.api.nvim_open_win(buf, false, {
        split = "right",
        win = -1,
        width = width,
    })

    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"

    local handle = make_handle(name, buf, win)
    _panels[name] = handle
    return handle
end

function M.close_all()
    for name, h in pairs(_panels) do
        if vim.api.nvim_win_is_valid(h.win) then
            vim.api.nvim_win_close(h.win, true)
        end
        _panels[name] = nil
    end
end

return M
