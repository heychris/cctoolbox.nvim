local claude = require("cctoolbox.core.claude")

local M = {}

-- Pure parser: converts Claude's "file:line" output text into quickfix-style entries.
function M.parse_find_output(text)
    if not text or text == "" then
        return {}
    end

    local entries = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$") -- trim
        if line ~= "" then
            -- Match file:line or file:line:col or file:line: description
            -- Use [^:]+ so filename stops at first colon, picking the first :number not the last
            local filename, lnum_str, rest = line:match("^([^:]+):(%d+):?(.*)$")
            if filename and lnum_str then
                local lnum = tonumber(lnum_str)
                local description = rest and rest:match("^%s*(.+)") or nil
                table.insert(entries, {
                    filename = filename,
                    lnum = lnum,
                    col = 1,
                    text = description or line,
                })
            end
        end
    end
    return entries
end

local FIND_SYSTEM_PROMPT = [[
You are a code search assistant. Your task is to find all relevant locations in the codebase that match the user's query.
Output ONLY a list of file:line entries, one per line. Format: path/to/file.lua:42
Include a brief description after the line number if helpful: path/to/file.lua:42: why this is relevant
Do not include any other text, headings, or explanations — only the file:line entries.
]]

function M.run()
    local ok, prompt_ui = pcall(require, "cctoolbox.ui.prompt")
    if not ok then
        return
    end

    prompt_ui.open({
        title = "Find: describe what to look for",
        on_submit = function(query)
            if not query or query == "" then
                return
            end

            local full_prompt = string.format(
                "Search the codebase in directory: %s\n\nFind: %s",
                vim.fn.getcwd(),
                query
            )

            local fidget = require("fidget")
            fidget.notify("Find: " .. query, vim.log.levels.INFO, {
                key = "cctoolbox_find",
                annote = "searching...",
                skip_history = true,
            })

            claude.run(full_prompt, {
                append_system_prompt = FIND_SYSTEM_PROMPT,
                allowed_tools = { "Bash", "Read" },
            }, function(result, err)
                if err then
                    fidget.notify("Find failed", vim.log.levels.ERROR, {
                        key = "cctoolbox_find",
                        annote = "error",
                        ttl = 5,
                    })
                    vim.notify("cc-toolbox find error: " .. err, vim.log.levels.ERROR)
                    return
                end

                local entries = M.parse_find_output(result or "")
                if #entries == 0 then
                    fidget.notify("Find: " .. query, vim.log.levels.WARN, {
                        key = "cctoolbox_find",
                        annote = "no results",
                        ttl = 4,
                    })
                    return
                end

                fidget.notify(
                    string.format("Find: %d result%s", #entries, #entries == 1 and "" or "s"),
                    vim.log.levels.INFO,
                    { key = "cctoolbox_find", annote = query, ttl = 4 }
                )

                vim.fn.setqflist({}, "r", {
                    title = "cc-toolbox find: " .. query,
                    items = entries,
                })
                vim.cmd("copen")
            end)
        end,
        on_cancel = function() end,
    })
end

return M
