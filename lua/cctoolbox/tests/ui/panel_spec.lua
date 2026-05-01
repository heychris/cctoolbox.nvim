local panel = require("cctoolbox.ui.panel")
local config = require("cctoolbox.config")

describe("panel", function()
    before_each(function()
        config.values.panel = { position = "right", width = 40 }
    end)

    after_each(function()
        -- Close all cctoolbox panels between tests
        panel.close_all()
    end)

    describe("panel.get_or_create", function()
        it("returns a handle with buf and win fields", function()
            local h = panel.get_or_create("test_panel")
            assert.is_not_nil(h)
            assert.is_not_nil(h.buf)
            assert.is_not_nil(h.win)
            assert.truthy(vim.api.nvim_buf_is_valid(h.buf))
            assert.truthy(vim.api.nvim_win_is_valid(h.win))
        end)

        it("returns the same handle on second call with same name", function()
            local h1 = panel.get_or_create("reuse_panel")
            local h2 = panel.get_or_create("reuse_panel")
            assert.are.equal(h1.buf, h2.buf)
            assert.are.equal(h1.win, h2.win)
        end)

        it("creates different buffers for different names", function()
            local h1 = panel.get_or_create("panel_a")
            local h2 = panel.get_or_create("panel_b")
            assert.are_not.equal(h1.buf, h2.buf)
        end)
    end)

    describe("panel.append", function()
        it("adds text lines to the buffer", function()
            local h = panel.get_or_create("append_panel")
            h.append("line one")
            h.append("line two")
            local lines = vim.api.nvim_buf_get_lines(h.buf, 0, -1, false)
            local found_one = false
            local found_two = false
            for _, l in ipairs(lines) do
                if l:find("line one") then
                    found_one = true
                end
                if l:find("line two") then
                    found_two = true
                end
            end
            assert.truthy(found_one)
            assert.truthy(found_two)
        end)

        it("handles multiline text with newlines", function()
            local h = panel.get_or_create("multiline_panel")
            h.append("first\nsecond\nthird")
            local lines = vim.api.nvim_buf_get_lines(h.buf, 0, -1, false)
            local combined = table.concat(lines, "\n")
            assert.truthy(combined:find("first"))
            assert.truthy(combined:find("second"))
            assert.truthy(combined:find("third"))
        end)
    end)

    describe("panel.replace", function()
        it("replaces all buffer content", function()
            local h = panel.get_or_create("replace_panel")
            h.append("old content")
            h.replace("new content")
            local lines = vim.api.nvim_buf_get_lines(h.buf, 0, -1, false)
            local combined = table.concat(lines, "\n")
            assert.falsy(combined:find("old content"))
            assert.truthy(combined:find("new content"))
        end)
    end)

    describe("panel.close", function()
        it("closes the window", function()
            local h = panel.get_or_create("close_panel")
            local win = h.win
            assert.truthy(vim.api.nvim_win_is_valid(win))
            h.close()
            assert.falsy(vim.api.nvim_win_is_valid(win))
        end)

        it("creates a new window after close when get_or_create called again", function()
            local h1 = panel.get_or_create("reopen_panel")
            local win1 = h1.win
            h1.close()
            local h2 = panel.get_or_create("reopen_panel")
            assert.truthy(vim.api.nvim_win_is_valid(h2.win))
            assert.are_not.equal(win1, h2.win)
        end)
    end)
end)
