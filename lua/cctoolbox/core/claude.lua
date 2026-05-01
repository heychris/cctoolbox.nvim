local config = require("cctoolbox.config")

local M = {}

-- Parses a single line of stream-json output from `claude --output-format stream-json`.
-- Returns { type = "text", text = string } for assistant text chunks,
-- { type = "done", text = string, is_error = bool } for result events,
-- or nil for events that should be ignored.
function M.parse_stream_line(line)
    if not line or line:match("^%s*$") then
        return nil
    end

    local ok, event = pcall(vim.json.decode, line)
    if not ok or type(event) ~= "table" then
        return nil
    end

    if event.type == "assistant" then
        local content = event.message and event.message.content
        if type(content) == "table" then
            for _, item in ipairs(content) do
                if item.type == "text" and item.text then
                    return { type = "text", text = item.text }
                end
            end
        end
        return nil
    end

    if event.type == "result" then
        return {
            type = "done",
            text = event.result,
            is_error = event.is_error == true,
            session_id = event.session_id,
        }
    end

    return nil
end

-- Returns a stateful processor function that feeds stream-json lines into
-- on_chunk(text) for text fragments and on_done(text, err, session_id) on completion.
function M.make_processor(on_chunk, on_done)
    return function(line)
        local parsed = M.parse_stream_line(line)
        if not parsed then
            return
        end

        if parsed.type == "text" then
            on_chunk(parsed.text)
        elseif parsed.type == "done" then
            if parsed.is_error then
                on_done(nil, parsed.text, nil)
            else
                on_done(parsed.text, nil, parsed.session_id)
            end
        end
    end
end

-- Runs claude with streaming output. Calls on_chunk(text) for each text fragment
-- and on_done(full_text, err, session_id) when finished. Returns a handle with :kill().
-- opts.persist_session = true  — omits --no-session-persistence so the session can be resumed
-- opts.resume_session_id       — resumes a prior session via --resume <id>
function M.stream(prompt, opts, on_chunk, on_done)
    opts = opts or {}

    local args = {
        config.values.claude_bin,
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--verbose",
        "--model",
        config.values.model,
    }

    if not opts.persist_session then
        vim.list_extend(args, { "--no-session-persistence" })
    end

    if opts.resume_session_id then
        vim.list_extend(args, { "--resume", opts.resume_session_id })
    end

    if opts.append_system_prompt then
        vim.list_extend(args, { "--append-system-prompt", opts.append_system_prompt })
    end

    if opts.allowed_tools and #opts.allowed_tools > 0 then
        vim.list_extend(args, { "--allowedTools", table.concat(opts.allowed_tools, ",") })
    end

    local processor = M.make_processor(function(text)
        vim.schedule(function()
            on_chunk(text)
        end)
    end, function(text, err, session_id)
        vim.schedule(function()
            on_done(text, err, session_id)
        end)
    end)

    local buf = ""
    return vim.system(args, {
        cwd = opts.cwd or vim.fn.getcwd(),
        stdout = function(_, data)
            if not data then
                return
            end
            buf = buf .. data
            local pos = 1
            while true do
                local nl = buf:find("\n", pos, true)
                if not nl then
                    break
                end
                local line = buf:sub(pos, nl - 1)
                pos = nl + 1
                processor(line)
            end
            buf = buf:sub(pos)
        end,
    }, function(result)
        if result.code ~= 0 and result.code ~= nil then
            vim.schedule(function()
                on_done(nil, "claude exited with code " .. result.code)
            end)
        end
    end)
end

-- Runs claude with --output-format json (one-shot). Calls on_done(result, err).
function M.run(prompt, opts, on_done)
    opts = opts or {}

    local args = {
        config.values.claude_bin,
        "-p",
        prompt,
        "--output-format",
        "json",
        "--model",
        config.values.model,
        "--no-session-persistence",
    }

    if opts.append_system_prompt then
        vim.list_extend(args, { "--append-system-prompt", opts.append_system_prompt })
    end

    if opts.allowed_tools and #opts.allowed_tools > 0 then
        vim.list_extend(args, { "--allowedTools", table.concat(opts.allowed_tools, ",") })
    end

    local output = {}
    return vim.system(args, {
        cwd = opts.cwd or vim.fn.getcwd(),
        stdout = function(_, data)
            if data then
                table.insert(output, data)
            end
        end,
    }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                on_done(nil, "claude exited with code " .. result.code)
                return
            end
            local raw = table.concat(output)
            local ok, decoded = pcall(vim.json.decode, raw)
            if not ok then
                on_done(nil, "failed to parse claude JSON output")
                return
            end
            if decoded.is_error then
                on_done(nil, decoded.result)
            else
                on_done(decoded.result, nil)
            end
        end)
    end)
end

return M
