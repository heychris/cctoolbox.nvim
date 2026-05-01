local claude = require("cctoolbox.core.claude")
local panel = require("cctoolbox.ui.panel")

local M = {}

local LEARN_SYSTEM_PROMPT = [[
You are a technical research assistant. Answer the user's question thoroughly but concisely.
Use markdown formatting with headers, code blocks, and bullet points as appropriate.
Focus on practical, actionable information.
]]

function M.run()
    local prompt_ui = require("cctoolbox.ui.prompt")

    prompt_ui.open({
        title = "Learn: ask a question",
        on_submit = function(question)
            if not question or question == "" then
                return
            end

            local h = panel.get_or_create("cctoolbox_learn")
            h.replace("## " .. question .. "\n\n")

            claude.stream(question, {
                append_system_prompt = LEARN_SYSTEM_PROMPT,
            }, function(chunk)
                h.append(chunk)
            end, function(_, err)
                if err then
                    h.append("\n\n**Error:** " .. err)
                    vim.notify("cc-toolbox learn error: " .. err, vim.log.levels.ERROR)
                end
            end)
        end,
        on_cancel = function() end,
    })
end

return M
