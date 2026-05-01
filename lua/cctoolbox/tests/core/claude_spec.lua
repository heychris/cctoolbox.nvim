local claude = require("cctoolbox.core.claude")

describe("claude.parse_stream_line", function()
    it("extracts text from assistant events", function()
        local line = vim.json.encode({
            type = "assistant",
            message = {
                content = {
                    { type = "text", text = "Hello world" },
                },
            },
        })
        local result = claude.parse_stream_line(line)
        assert.are.equal("text", result.type)
        assert.are.equal("Hello world", result.text)
    end)

    it("returns nil for system events", function()
        local line = vim.json.encode({
            type = "system",
            subtype = "init",
        })
        assert.is_nil(claude.parse_stream_line(line))
    end)

    it("returns nil for rate_limit events", function()
        local line = vim.json.encode({
            type = "rate_limit_error",
        })
        assert.is_nil(claude.parse_stream_line(line))
    end)

    it("returns done result for result events with success", function()
        local line = vim.json.encode({
            type = "result",
            subtype = "success",
            result = "Final answer here",
            is_error = false,
        })
        local result = claude.parse_stream_line(line)
        assert.are.equal("done", result.type)
        assert.are.equal("Final answer here", result.text)
        assert.is_false(result.is_error)
    end)

    it("passes is_error=true for error result events", function()
        local line = vim.json.encode({
            type = "result",
            subtype = "error_max_turns",
            result = "Max turns exceeded",
            is_error = true,
        })
        local result = claude.parse_stream_line(line)
        assert.are.equal("done", result.type)
        assert.is_true(result.is_error)
        assert.are.equal("Max turns exceeded", result.text)
    end)

    it("returns nil for empty or blank lines", function()
        assert.is_nil(claude.parse_stream_line(""))
        assert.is_nil(claude.parse_stream_line("   "))
    end)

    it("returns nil for non-JSON lines", function()
        assert.is_nil(claude.parse_stream_line("not json at all"))
    end)

    it("returns nil for assistant events with no text content", function()
        local line = vim.json.encode({
            type = "assistant",
            message = {
                content = {
                    { type = "tool_use", id = "toolu_01", name = "Bash", input = {} },
                },
            },
        })
        assert.is_nil(claude.parse_stream_line(line))
    end)

    it("handles assistant events with multiple content items, picks first text", function()
        local line = vim.json.encode({
            type = "assistant",
            message = {
                content = {
                    { type = "tool_use", id = "toolu_01", name = "Bash", input = {} },
                    { type = "text", text = "Here is the result" },
                },
            },
        })
        local result = claude.parse_stream_line(line)
        assert.are.equal("text", result.type)
        assert.are.equal("Here is the result", result.text)
    end)
end)

describe("claude.collect_chunks", function()
    it("accumulates text chunks and calls on_done with full text on result", function()
        local chunks = {}
        local done_text = nil
        local done_err = nil

        local on_chunk = function(text)
            table.insert(chunks, text)
        end
        local on_done = function(text, err)
            done_text = text
            done_err = err
        end

        local processor = claude.make_processor(on_chunk, on_done)

        processor(vim.json.encode({
            type = "assistant",
            message = { content = { { type = "text", text = "Hello " } } },
        }))
        processor(vim.json.encode({
            type = "assistant",
            message = { content = { { type = "text", text = "world" } } },
        }))
        processor(vim.json.encode({
            type = "result",
            subtype = "success",
            result = "Hello world",
            is_error = false,
        }))

        assert.are.same({ "Hello ", "world" }, chunks)
        assert.are.equal("Hello world", done_text)
        assert.is_nil(done_err)
    end)

    it("calls on_done with error when is_error=true", function()
        local done_text = nil
        local done_err = nil

        local processor = claude.make_processor(function() end, function(text, err)
            done_text = text
            done_err = err
        end)

        processor(vim.json.encode({
            type = "result",
            subtype = "error_max_turns",
            result = "Something went wrong",
            is_error = true,
        }))

        assert.is_nil(done_text)
        assert.are.equal("Something went wrong", done_err)
    end)
end)
