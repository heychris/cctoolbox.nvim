local task = require("cctoolbox.features.task")

describe("task state machine", function()
    before_each(function()
        task._reset()
    end)

    describe("task.register", function()
        it("creates a task entry and returns a task_id", function()
            local id = task.register({
                bufnr = 1,
                lnum = 0,
                description = "do something",
                range = { 1, 1 },
            })
            assert.is_not_nil(id)
            assert.are.equal("string", type(id))
        end)

        it("generates unique ids for each task", function()
            local id1 =
                task.register({ bufnr = 1, lnum = 0, description = "task 1", range = { 1, 1 } })
            local id2 =
                task.register({ bufnr = 1, lnum = 1, description = "task 2", range = { 2, 2 } })
            assert.are_not.equal(id1, id2)
        end)

        it("initial status is pending", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            assert.are.equal("pending", task.get_status(id))
        end)

        it("stores the range size", function()
            local id =
                task.register({ bufnr = 1, lnum = 2, description = "test", range = { 3, 7 } })
            assert.are.equal(5, task._get(id).range_size)
        end)

        it("starts with no panel handle", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            assert.is_nil(task._get(id).panel_handle)
        end)

        it("starts with an empty output buffer", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            assert.are.same({}, task._get(id).output)
        end)
    end)

    describe("task output buffering", function()
        it("append_output adds chunks to the output table", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            task.append_output(id, "chunk one")
            task.append_output(id, " chunk two")
            assert.are.same({ "chunk one", " chunk two" }, task._get(id).output)
        end)

        it("get_output returns concatenated output string", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            task.append_output(id, "Hello ")
            task.append_output(id, "world")
            assert.are.equal("Hello world", task.get_output(id))
        end)

        it("get_output returns empty string for task with no output", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            assert.are.equal("", task.get_output(id))
        end)
    end)

    describe("task.extract_code_block", function()
        it("extracts code from a fenced block with language tag", function()
            local output = "Here is the fix:\n```lua\nreturn 42\n```\n"
            assert.are.equal("return 42", task.extract_code_block(output))
        end)

        it("extracts code from a fenced block with no language tag", function()
            local output = "```\nhello world\n```"
            assert.are.equal("hello world", task.extract_code_block(output))
        end)

        it("returns nil when no code block is present", function()
            assert.is_nil(task.extract_code_block("Just some prose."))
        end)

        it("returns the last code block when multiple are present", function()
            local output = "First:\n```lua\nfirst()\n```\nThen:\n```lua\nsecond()\n```"
            assert.are.equal("second()", task.extract_code_block(output))
        end)

        it("strips trailing newlines from extracted code", function()
            local output = "```lua\nfoo()\n\n```"
            assert.falsy(task.extract_code_block(output):match("\n$"))
        end)

        it("preserves internal newlines", function()
            local output = "```lua\nfunction foo()\n  return 1\nend\n```"
            assert.are.equal("function foo()\n  return 1\nend", task.extract_code_block(output))
        end)
    end)

    describe("task.apply_to_range", function()
        local bufnr

        before_each(function()
            bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "line 1",
                "line 2",
                "line 3",
                "line 4",
                "line 5",
            })
        end)

        after_each(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.api.nvim_buf_delete(bufnr, { force = true })
            end
        end)

        it("replaces the specified range with new lines", function()
            task.apply_to_range(bufnr, { 2, 4 }, "new line A\nnew line B")
            assert.are.same(
                { "line 1", "new line A", "new line B", "line 5" },
                vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            )
        end)

        it("handles replacement with more lines than original range", function()
            task.apply_to_range(bufnr, { 2, 3 }, "a\nb\nc")
            assert.are.same(
                { "line 1", "a", "b", "c", "line 4", "line 5" },
                vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            )
        end)

        it("handles replacement with fewer lines than original range", function()
            task.apply_to_range(bufnr, { 2, 5 }, "only one")
            assert.are.same(
                { "line 1", "only one" },
                vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            )
        end)

        it("handles a single-line range (cursor position)", function()
            task.apply_to_range(bufnr, { 3, 3 }, "replaced")
            assert.are.same(
                { "line 1", "line 2", "replaced", "line 4", "line 5" },
                vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            )
        end)
    end)

    describe("task.get_current_range", function()
        local bufnr

        before_each(function()
            bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "line 1",
                "line 2",
                "line 3",
                "line 4",
                "line 5",
            })
        end)

        after_each(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.api.nvim_buf_delete(bufnr, { force = true })
            end
        end)

        it("returns the original range when buffer is unchanged", function()
            local id =
                task.register({ bufnr = bufnr, lnum = 1, description = "test", range = { 2, 4 } })
            local t = task._get(id)
            t.extmark_id = require("cctoolbox.ui.marker").place(bufnr, 1, id)
            assert.are.same({ 2, 4 }, task.get_current_range(id))
        end)

        it("tracks correctly after lines are inserted above the marker", function()
            local id =
                task.register({ bufnr = bufnr, lnum = 1, description = "test", range = { 2, 3 } })
            local t = task._get(id)
            t.extmark_id = require("cctoolbox.ui.marker").place(bufnr, 1, id)

            -- Insert 2 lines above the selection
            vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "inserted 1", "inserted 2" })

            -- Range should have shifted down by 2
            assert.are.same({ 4, 5 }, task.get_current_range(id))
        end)

        it("tracks correctly after lines are deleted above the marker", function()
            local id =
                task.register({ bufnr = bufnr, lnum = 3, description = "test", range = { 4, 5 } })
            local t = task._get(id)
            t.extmark_id = require("cctoolbox.ui.marker").place(bufnr, 3, id)

            -- Delete the first line above the selection
            vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})

            -- Range should have shifted up by 1
            assert.are.same({ 3, 4 }, task.get_current_range(id))
        end)

        it("preserves range size regardless of mutations above", function()
            local id =
                task.register({ bufnr = bufnr, lnum = 2, description = "test", range = { 3, 5 } })
            local t = task._get(id)
            t.extmark_id = require("cctoolbox.ui.marker").place(bufnr, 2, id)
            vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "a", "b", "c" })
            local r = task.get_current_range(id)
            assert.are.equal(3, r[2] - r[1] + 1)
        end)
    end)

    describe("task tools config", function()
        it("does not include Edit in allowed tools", function()
            assert.is_false(vim.tbl_contains(task.ALLOWED_TOOLS, "Edit"))
        end)

        it("includes Read in allowed tools", function()
            assert.is_true(vim.tbl_contains(task.ALLOWED_TOOLS, "Read"))
        end)

        it("system prompt instructs single code block output", function()
            assert.truthy(task.SYSTEM_PROMPT:find("code block"))
        end)
    end)

    describe("task.set_status", function()
        it("transitions from pending to running", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            task.set_status(id, "running")
            assert.are.equal("running", task.get_status(id))
        end)

        it("transitions from running to done", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            task.set_status(id, "running")
            task.set_status(id, "done")
            assert.are.equal("done", task.get_status(id))
        end)

        it("transitions from running to error", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            task.set_status(id, "running")
            task.set_status(id, "error")
            assert.are.equal("error", task.get_status(id))
        end)
    end)

    describe("task.cancel", function()
        it("sets status to cancelled", function()
            local id =
                task.register({ bufnr = 1, lnum = 0, description = "test", range = { 1, 1 } })
            task.set_status(id, "running")
            task.cancel(id)
            assert.are.equal("cancelled", task.get_status(id))
        end)

        it("does not error when cancelling a non-existent task", function()
            assert.has_no.errors(function()
                task.cancel("nonexistent_task_id")
            end)
        end)
    end)

    describe("task.get_status", function()
        it("returns nil for unknown task id", function()
            assert.is_nil(task.get_status("unknown_id"))
        end)
    end)

    describe("task.list_active", function()
        it("returns empty table initially", function()
            assert.are.same({}, task.list_active())
        end)

        it("includes pending and running tasks", function()
            task.register({ bufnr = 1, lnum = 0, description = "t1", range = { 1, 1 } })
            local id2 = task.register({ bufnr = 1, lnum = 1, description = "t2", range = { 2, 2 } })
            task.set_status(id2, "running")
            assert.are.equal(2, #task.list_active())
        end)

        it("excludes done and cancelled tasks", function()
            local id1 =
                task.register({ bufnr = 1, lnum = 0, description = "done", range = { 1, 1 } })
            local id2 =
                task.register({ bufnr = 1, lnum = 1, description = "cancelled", range = { 2, 2 } })
            task.set_status(id1, "running")
            task.set_status(id1, "done")
            task.set_status(id2, "running")
            task.cancel(id2)
            assert.are.same({}, task.list_active())
        end)
    end)
end)
