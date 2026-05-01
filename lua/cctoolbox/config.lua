local M = {}

M.values = {
    claude_bin = "/Users/chriswilson/.local/bin/claude",
    model = "sonnet",
    jobs_dir = vim.fn.stdpath("data") .. "/cctoolbox/jobs/",
    panel = { position = "right", width = 60 },
}

function M.setup(opts)
    M.values = vim.tbl_deep_extend("force", M.values, opts or {})
end

return M
