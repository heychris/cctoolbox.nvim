local claude = require("cctoolbox.core.claude")
local git = require("cctoolbox.core.git")
local panel = require("cctoolbox.ui.panel")

local M = {}

-- Opens DiffviewOpen for the PR if we're inside the matching repo (no working tree changes).
-- Falls back to a ft=diff scratch buffer for cross-repo reviews.
-- Returns the review panel handle.
local function open_review_layout(pr, parsed)
    local source_win = vim.api.nvim_get_current_win()
    local h

    if git.remote_matches(parsed.owner, parsed.repo) and pr.base_ref then
        local ok = git.fetch_pr_head(parsed.number)
        if ok then
            -- DiffviewOpen is synchronous — layout is fully set up when vim.cmd returns.
            -- Open it first, then add the panel as a right split within the diffview tab.
            vim.cmd("DiffviewOpen origin/" .. pr.base_ref .. "...FETCH_HEAD")
            h = panel.get_or_create("cctoolbox_review")
            return h
        end
        vim.notify("cc-toolbox: git fetch failed, falling back to diff view", vim.log.levels.WARN)
    end

    -- Fallback: scratch buffer with ft=diff, panel on the right
    h = panel.get_or_create("cctoolbox_review")
    local diff_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[diff_buf].filetype = "diff"
    vim.bo[diff_buf].buftype = "nofile"
    vim.bo[diff_buf].modifiable = true
    local diff_lines = vim.split(pr.diff, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
    vim.bo[diff_buf].modifiable = false
    vim.api.nvim_win_set_buf(source_win, diff_buf)

    return h
end

local REVIEW_SYSTEM_PROMPT = [[
You are a senior software engineer performing a focused, actionable code review.

Rules:
- Only include things that matter. Skip praise entirely — if something is fine, say nothing.
- Each item starts with a single bold line: the problem and its severity (e.g. **Bug:** ..., **Critical:** ..., **Minor:** ...). Follow with a short paragraph if more detail is needed, but keep it skimmable.
- Sort each section by importance, most severe first.
- Omit a section entirely if there is nothing to put in it.

## Problems
Bugs, correctness gaps, security issues, missing error handling — anything that needs to be fixed.

## Suggestions
Non-blocking improvements worth considering. High-signal only; keep the list short.
]]

function M.run()
    require("cctoolbox.ui.prompt").open({
        title = "GitHub PR URL",
        on_submit = function(url)
            if not url or url == "" then
                return
            end

            local parsed = git.parse_github_url(url)
            if not parsed then
                vim.notify("cc-toolbox: invalid GitHub PR URL", vim.log.levels.WARN)
                return
            end

            vim.notify("cc-toolbox: fetching PR...", vim.log.levels.INFO)

            local pr = git.fetch_pr(parsed.owner, parsed.repo, parsed.number)
            if not pr then
                vim.notify(
                    "cc-toolbox: failed to fetch PR — check `gh` auth and the URL",
                    vim.log.levels.WARN
                )
                return
            end

            if not pr.diff then
                vim.notify("cc-toolbox: no diff found for PR", vim.log.levels.WARN)
                return
            end

            local h = open_review_layout(pr, parsed)
            h.replace("## Code Review\n\nFetching PR...\n")

            local context_text = (pr.title or "") .. "\n" .. (pr.body or "")
            local ticket = git.extract_linear_ticket(context_text)
            local figma_url = git.extract_figma_url(context_text)

            local prompt_parts = {}

            if pr.title then
                table.insert(prompt_parts, "**PR Title:** " .. pr.title)
            end
            table.insert(prompt_parts, "**PR URL:** " .. url)
            if ticket then
                table.insert(prompt_parts, "**Linear Ticket:** " .. ticket)
            end
            if figma_url then
                table.insert(prompt_parts, "**Figma Design:** " .. figma_url)
            end
            if pr.body and pr.body ~= "" then
                table.insert(prompt_parts, "\n**PR Description:**\n" .. pr.body)
            end
            table.insert(prompt_parts, "\n**Diff:**\n```diff\n" .. pr.diff .. "\n```")

            local full_prompt = table.concat(prompt_parts, "\n")

            local allowed_tools = {}
            if ticket then
                table.insert(allowed_tools, "mcp__linear__get_issue")
                table.insert(allowed_tools, "mcp__linear__search_issues")
            end

            h.replace("## Code Review\n\n**PR:** " .. (pr.title or url) .. "\n\nAnalyzing...\n\n")

            claude.stream(full_prompt, {
                append_system_prompt = REVIEW_SYSTEM_PROMPT,
                allowed_tools = #allowed_tools > 0 and allowed_tools or nil,
            }, function(chunk)
                h.append(chunk)
            end, function(_, err)
                if err then
                    h.append("\n\n**Error:** " .. err)
                    vim.notify("cc-toolbox review error: " .. err, vim.log.levels.ERROR)
                end
            end)
        end,
        on_cancel = function() end,
    })
end

return M
