local marker = require("cctoolbox.ui.marker")

describe("marker", function()
    local bufnr

    before_each(function()
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            "line 1",
            "line 2",
            "line 3",
        })
    end)

    after_each(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)

    describe("marker.place", function()
        it("returns a numeric extmark id", function()
            local id = marker.place(bufnr, 0, "task_abc")
            assert.are.equal("number", type(id))
            assert.truthy(id > 0)
        end)

        it("places an extmark on the correct line", function()
            local id = marker.place(bufnr, 1, "task_xyz")
            local ns = vim.api.nvim_get_namespaces()["cctoolbox_tasks"]
            local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
            local found = false
            for _, m in ipairs(marks) do
                if m[1] == id and m[2] == 1 then
                    found = true
                end
            end
            assert.truthy(found)
        end)
    end)

    describe("marker.update", function()
        it("updates the virtual text without error", function()
            local id = marker.place(bufnr, 0, "task_upd")
            assert.has_no.errors(function()
                marker.update(bufnr, id, "done")
            end)
        end)

        it("accepts running, done, and error statuses", function()
            local id = marker.place(bufnr, 0, "task_status")
            assert.has_no.errors(function()
                marker.update(bufnr, id, "running")
                marker.update(bufnr, id, "done")
                marker.update(bufnr, id, "error")
            end)
        end)
    end)

    describe("marker.remove", function()
        it("removes the extmark", function()
            local id = marker.place(bufnr, 0, "task_rm")
            local ns = vim.api.nvim_get_namespaces()["cctoolbox_tasks"]
            marker.remove(bufnr, id)
            local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
            for _, m in ipairs(marks) do
                assert.are_not.equal(id, m[1])
            end
        end)

        it("does not error when removing non-existent mark", function()
            assert.has_no.errors(function()
                marker.remove(bufnr, 99999)
            end)
        end)
    end)

    describe("marker.get_task_id", function()
        it("returns task_id for a mark placed on the given extmark id", function()
            local id = marker.place(bufnr, 0, "task_lookup")
            local task_id = marker.get_task_id(bufnr, id)
            assert.are.equal("task_lookup", task_id)
        end)

        it("returns nil for unknown extmark id", function()
            local task_id = marker.get_task_id(bufnr, 99999)
            assert.is_nil(task_id)
        end)
    end)
end)
