local M = {}

function M.setup(opts)
    local config = require("cctoolbox.config")
    config.setup(opts)

    -- Ensure jobs directory exists
    vim.fn.mkdir(config.values.jobs_dir, "p")

    -- Define highlight groups for task markers.
    -- We resolve Comment's fg at setup time so we can pair it with our bg.
    local function set_hl(name, attrs)
        vim.api.nvim_set_hl(0, name, attrs)
    end

    local comment_raw = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
    local comment_fg = comment_raw.fg and string.format("#%06x", comment_raw.fg) or "#565f89"
    local marker_bg = "#1e2030"

    -- Cap chars (  U+E0B6/U+E0B4) with fg=marker_bg and no bg create a pill shape at EOL
    set_hl("CctoolboxCap", { fg = marker_bg })
    set_hl("CctoolboxSpinner", { fg = "#7aa2f7", bg = marker_bg })
    set_hl("CctoolboxDoneIcon", { fg = "#ffffff", bg = marker_bg }) -- white circle
    set_hl("CctoolboxDone", { fg = "#9ece6a", bg = marker_bg })
    set_hl("CctoolboxError", { fg = "#f7768e", bg = marker_bg })
    set_hl("CctoolboxTimer", { fg = comment_fg, bg = marker_bg })
    set_hl("CctoolboxLabel", { fg = comment_fg, bg = marker_bg })

    -- User commands
    vim.api.nvim_create_user_command("CCToolbox", function(cmd_opts)
        local args = vim.split(cmd_opts.args, "%s+", { trimempty = true })
        local subcmd = args[1]

        if subcmd == "review" then
            require("cctoolbox.features.review").run()
        elseif subcmd == "learn" then
            require("cctoolbox.features.learn").run()
        elseif subcmd == "find" then
            require("cctoolbox.features.find").run()
        elseif subcmd == "job" then
            local action = args[2]
            local job = require("cctoolbox.features.job")
            if action == "create" and args[3] then
                job.create(args[3], {})
                job.edit(args[3])
            elseif action == "delete" and args[3] then
                job.delete(args[3])
                vim.notify("Deleted job: " .. args[3], vim.log.levels.INFO)
            elseif action == "list" then
                local names = job.list()
                if #names == 0 then
                    vim.notify("No jobs found", vim.log.levels.INFO)
                else
                    vim.notify("Jobs: " .. table.concat(names, ", "), vim.log.levels.INFO)
                end
            else
                job.pick()
            end
        elseif subcmd == "task" then
            require("cctoolbox.features.task").run()
        else
            vim.notify("CCToolbox subcommands: review, learn, find, job, task", vim.log.levels.INFO)
        end
    end, {
        nargs = "*",
        desc = "cc-toolbox: AI-powered coding assistant",
    })

    -- Keymaps
    local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
    end

    map("n", "<leader>ccr", function()
        require("cctoolbox.features.review").run()
    end, "CC Review")
    map("n", "<leader>ccl", function()
        require("cctoolbox.features.learn").run()
    end, "CC Learn")
    map("n", "<leader>ccf", function()
        require("cctoolbox.features.find").run()
    end, "CC Find")
    map("n", "<leader>ccj", function()
        require("cctoolbox.features.job").open_list()
    end, "CC Jobs")
    map({ "n", "v" }, "<leader>cct", function()
        local task = require("cctoolbox.features.task")
        local mode = vim.fn.mode()
        if mode == "v" or mode == "V" then
            local start_line = vim.fn.line("v")
            local end_line = vim.fn.line(".")
            if start_line > end_line then
                start_line, end_line = end_line, start_line
            end
            task.run({ range = { start_line, end_line } })
        else
            task.run()
        end
    end, "CC Task")
end

return M
