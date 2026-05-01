local M = {}

function M.current_branch()
    local result = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null")
    if vim.v.shell_error ~= 0 then
        return nil
    end
    return result:gsub("%s+$", "")
end

-- Parses a GitHub PR URL and returns { owner, repo, number } or nil.
function M.parse_github_url(url)
    if not url or url == "" then
        return nil
    end
    local owner, repo, number = url:match("github%.com/([^/]+)/([^/]+)/pull/(%d+)")
    if not owner then
        return nil
    end
    return { owner = owner, repo = repo, number = tonumber(number) }
end

-- Fetches PR metadata and diff for a given owner/repo/number using the gh CLI.
-- Returns { title, body, base_ref, diff } or nil on failure.
function M.fetch_pr(owner, repo, number)
    local repo_flag = owner .. "/" .. repo
    local meta_raw = vim.fn.system(
        string.format(
            "gh pr view %d --repo %s --json title,body,baseRefName 2>/dev/null",
            number,
            repo_flag
        )
    )
    if vim.v.shell_error ~= 0 or meta_raw == "" then
        return nil
    end

    local ok, meta = pcall(vim.json.decode, meta_raw)
    if not ok then
        return nil
    end

    local diff =
        vim.fn.system(string.format("gh pr diff %d --repo %s 2>/dev/null", number, repo_flag))
    if vim.v.shell_error ~= 0 then
        diff = nil
    end

    return {
        title = meta.title,
        body = meta.body,
        base_ref = meta.baseRefName,
        diff = diff ~= "" and diff or nil,
    }
end

-- Returns true if the current repo's origin remote matches owner/repo.
function M.remote_matches(owner, repo)
    local remote = vim.fn.system("git remote get-url origin 2>/dev/null"):gsub("%s+$", "")
    if remote == "" then
        return false
    end
    -- Match both HTTPS and SSH remote formats
    return remote:find(owner .. "/" .. repo, 1, true) ~= nil
end

-- Fetches a PR's head into FETCH_HEAD without touching the working tree.
-- Returns true on success.
function M.fetch_pr_head(number)
    vim.fn.system(string.format("git fetch origin pull/%d/head 2>/dev/null", number))
    return vim.v.shell_error == 0
end

-- Extracts a Linear ticket ID (e.g. ENG-123, FEAT-456) from text.
function M.extract_linear_ticket(text)
    if not text then
        return nil
    end
    local ticket = text:match("[A-Z][A-Z]+%-(%d+)")
    if ticket then
        local prefix = text:match("([A-Z][A-Z]+)%-" .. ticket)
        if prefix then
            return prefix .. "-" .. ticket
        end
    end
    return nil
end

-- Extracts the first figma.com URL from text.
function M.extract_figma_url(text)
    if not text then
        return nil
    end
    return text:match("https?://[%w%.%-]*figma%.com/[%S]+")
end

return M
