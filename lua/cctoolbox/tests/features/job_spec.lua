local job = require("cctoolbox.features.job")
local config = require("cctoolbox.config")

local test_jobs_dir

describe("job storage", function()
    before_each(function()
        test_jobs_dir = vim.fn.tempname() .. "_cctoolbox_jobs/"
        config.values.jobs_dir = test_jobs_dir
        vim.fn.mkdir(test_jobs_dir, "p")
    end)

    after_each(function()
        vim.fn.delete(test_jobs_dir, "rf")
    end)

    describe("job.create", function()
        it("creates a markdown file in jobs_dir", function()
            job.create("myfeature", { content = "Initial content" })
            local path = test_jobs_dir .. "myfeature.md"
            assert.are.equal(1, vim.fn.filereadable(path))
        end)

        it("writes provided content into the file", function()
            job.create("myfeature", { content = "# My Feature\nDo the thing" })
            local content = job.read("myfeature")
            assert.is_not_nil(content)
            assert.truthy(content:find("My Feature"))
        end)

        it("default template includes yaml frontmatter with tag matching the job name", function()
            job.create("my_job", {})
            local content = job.read("my_job")
            assert.is_not_nil(content)
            assert.truthy(content:find("^---"), "should start with frontmatter fence")
            assert.truthy(content:find("tag: my_job"), "should contain tag field")
            assert.truthy(content:find("---"), "should close frontmatter fence")
        end)

        it("default template tag matches the job name exactly", function()
            job.create("auth_flow", {})
            local tag = job.read_tag("auth_flow")
            assert.are.equal("auth_flow", tag)
        end)
    end)

    describe("job.read_tag", function()
        it("reads tag from frontmatter", function()
            job.create("tagged", {})
            assert.are.equal("tagged", job.read_tag("tagged"))
        end)

        it("returns nil when job has no frontmatter", function()
            job.create("no_front", { content = "# No frontmatter here\n\nJust body." })
            assert.is_nil(job.read_tag("no_front"))
        end)

        it("returns nil for non-existent job", function()
            assert.is_nil(job.read_tag("ghost"))
        end)
    end)

    describe("job.read", function()
        it("returns nil for non-existent job", function()
            assert.is_nil(job.read("does_not_exist"))
        end)

        it("returns file content for existing job", function()
            job.create("readable", { content = "some content here" })
            local content = job.read("readable")
            assert.truthy(content:find("some content here"))
        end)
    end)

    describe("job.delete", function()
        it("removes the job file", function()
            job.create("to_delete", { content = "bye" })
            assert.are.equal(1, vim.fn.filereadable(test_jobs_dir .. "to_delete.md"))
            job.delete("to_delete")
            assert.are.equal(0, vim.fn.filereadable(test_jobs_dir .. "to_delete.md"))
        end)

        it("does not error when job does not exist", function()
            assert.has_no.errors(function()
                job.delete("nonexistent_job")
            end)
        end)
    end)

    describe("job.list", function()
        it("returns empty table when no jobs exist", function()
            local names = job.list()
            assert.are.same({}, names)
        end)

        it("returns names of all created jobs without extension", function()
            job.create("alpha", {})
            job.create("beta", {})
            job.create("gamma", {})
            local names = job.list()
            table.sort(names)
            assert.are.same({ "alpha", "beta", "gamma" }, names)
        end)
    end)

    describe("job.resolve_refs", function()
        it("returns text unchanged when no @refs present", function()
            local text = "Just a normal task description"
            assert.are.equal(text, job.resolve_refs(text))
        end)

        it("expands @jobName to job file content", function()
            job.create("mywork", { content = "This is the job details" })
            local result = job.resolve_refs("Do task for @mywork please")
            assert.truthy(result:find("This is the job details"))
        end)

        it("leaves unresolved @refs intact when job does not exist", function()
            local result = job.resolve_refs("reference to @unknownjob here")
            assert.truthy(result:find("@unknownjob"))
        end)

        it("expands multiple @refs in one string", function()
            job.create("job1", { content = "job1 content" })
            job.create("job2", { content = "job2 content" })
            local result = job.resolve_refs("@job1 and @job2")
            assert.truthy(result:find("job1 content"))
            assert.truthy(result:find("job2 content"))
        end)
    end)

    describe("job popup buffer", function()
        it("make_popup_buf returns a valid buffer", function()
            job.create("popup_job", {})
            local buf = job.make_popup_buf("popup_job")
            assert.truthy(vim.api.nvim_buf_is_valid(buf))
        end)

        it("popup buffer has buftype acwrite", function()
            job.create("popup_job", {})
            local buf = job.make_popup_buf("popup_job")
            assert.are.equal("acwrite", vim.bo[buf].buftype)
        end)

        it("popup buffer contains the job file content", function()
            job.create("popup_job", { content = "hello from popup" })
            local buf = job.make_popup_buf("popup_job")
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            local text = table.concat(lines, "\n")
            assert.truthy(text:find("hello from popup"))
        end)

        it("writing the popup buffer saves content to the job file", function()
            job.create("saveable", {})
            local buf = job.make_popup_buf("saveable")

            -- Modify buffer content
            vim.bo[buf].modifiable = true
            vim.api.nvim_buf_set_lines(
                buf,
                0,
                -1,
                false,
                { "---", "tag: saveable", "---", "", "# Updated content" }
            )

            -- Trigger BufWriteCmd (simulates :w)
            vim.api.nvim_buf_call(buf, function()
                vim.cmd("silent write")
            end)

            -- Verify file was updated
            local saved = job.read("saveable")
            assert.truthy(saved:find("Updated content"))
        end)

        it("buffer is not modified after a write", function()
            job.create("clean_write", {})
            local buf = job.make_popup_buf("clean_write")
            vim.bo[buf].modifiable = true
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new content" })
            vim.api.nvim_buf_call(buf, function()
                vim.cmd("silent write")
            end)
            assert.is_false(vim.bo[buf].modified)
        end)
    end)
end)
