local M = {}

-- Opens a small floating input popup.
-- opts: { title, multiline, on_submit(text), on_cancel() }
-- multiline = true: taller buffer, submit with <CR>/<C-s> in normal mode or <C-s> in insert mode
function M.open(opts)
    opts = opts or {}
    local on_submit = opts.on_submit or function() end
    local on_cancel = opts.on_cancel or function() end
    local title = opts.title or "Input"
    local multiline = opts.multiline or false

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"

    local width = math.min(60, math.floor(vim.o.columns * 0.6))
    local height = multiline and 6 or 1
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local footer = multiline and { { " <CR> submit  <S-CR> newline  <Esc> cancel ", "Comment" } }
        or nil

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " " .. title .. " ",
        title_pos = "center",
        footer = footer,
        footer_pos = footer and "center" or nil,
    })

    local submitted = false

    local function do_submit()
        if submitted then
            return
        end
        submitted = true
        local lines = multiline and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or nil
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        vim.cmd("stopinsert")
        if multiline then
            on_submit(table.concat(lines, "\n"))
        end
    end

    local function cancel()
        if submitted then
            return
        end
        submitted = true
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        vim.cmd("stopinsert")
        on_cancel()
    end

    if multiline then
        vim.keymap.set({ "n", "i" }, "<CR>", do_submit, { buffer = buf, nowait = true })
        vim.keymap.set("i", "<S-CR>", "<CR>", { buffer = buf, nowait = true })
        vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
        vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
        vim.cmd("startinsert")
    else
        vim.bo[buf].buftype = "prompt"
        vim.fn.prompt_setprompt(buf, "")
        vim.fn.prompt_setcallback(buf, function(text)
            submitted = true
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
            on_submit(text)
        end)
        vim.keymap.set("i", "<Esc>", cancel, { buffer = buf, nowait = true })
        vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
        vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
        vim.cmd("startinsert")
    end
end

return M
