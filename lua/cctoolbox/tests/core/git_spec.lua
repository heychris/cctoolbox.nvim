local git = require("cctoolbox.core.git")

describe("git.extract_linear_ticket", function()
    it("extracts a standard Linear ticket ID", function()
        assert.are.equal("ENG-123", git.extract_linear_ticket("ENG-123 fix login bug"))
    end)

    it("extracts ticket from branch name", function()
        assert.are.equal("FEAT-456", git.extract_linear_ticket("feature/FEAT-456-add-thing"))
    end)

    it("returns nil when no ticket present", function()
        assert.is_nil(git.extract_linear_ticket("just a regular message"))
    end)

    it("handles lowercase prefix", function()
        assert.is_nil(git.extract_linear_ticket("eng-123 lowercase prefix"))
    end)

    it("extracts ticket from PR body with surrounding text", function()
        local body = "This PR implements the work for ENG-789.\nSee design doc."
        assert.are.equal("ENG-789", git.extract_linear_ticket(body))
    end)

    it("handles multi-letter team prefixes", function()
        assert.are.equal("BACKEND-42", git.extract_linear_ticket("BACKEND-42: new endpoint"))
    end)
end)

describe("git.extract_figma_url", function()
    it("extracts a figma.com design URL", function()
        local url = "https://www.figma.com/file/abc123/MyDesign?node-id=1:2"
        assert.are.equal(url, git.extract_figma_url("Design: " .. url))
    end)

    it("returns nil when no figma URL present", function()
        assert.is_nil(git.extract_figma_url("no design link here"))
    end)

    it("extracts from figma.com/design/ URLs", function()
        local url = "https://figma.com/design/xyz789/Screen"
        local result = git.extract_figma_url("See " .. url .. " for reference")
        assert.is_not_nil(result)
        assert.truthy(result:find("figma%.com"))
    end)
end)

describe("git.parse_github_url", function()
    it("parses a standard PR URL", function()
        local r = git.parse_github_url("https://github.com/owner/repo/pull/42")
        assert.are.equal("owner", r.owner)
        assert.are.equal("repo", r.repo)
        assert.are.equal(42, r.number)
    end)

    it("handles URLs with trailing slash", function()
        local r = git.parse_github_url("https://github.com/owner/repo/pull/7/")
        assert.are.equal(7, r.number)
    end)

    it("handles URLs with query string or fragment", function()
        local r = git.parse_github_url("https://github.com/org/my-repo/pull/123?diff=split#files")
        assert.are.equal("org", r.owner)
        assert.are.equal("my-repo", r.repo)
        assert.are.equal(123, r.number)
    end)

    it("handles repo names with hyphens and dots", function()
        local r = git.parse_github_url("https://github.com/my-org/my.repo/pull/99")
        assert.are.equal("my-org", r.owner)
        assert.are.equal("my.repo", r.repo)
        assert.are.equal(99, r.number)
    end)

    it("returns nil for non-PR URLs", function()
        assert.is_nil(git.parse_github_url("https://github.com/owner/repo"))
        assert.is_nil(git.parse_github_url("https://github.com/owner/repo/issues/5"))
    end)

    it("returns nil for non-github URLs", function()
        assert.is_nil(git.parse_github_url("https://gitlab.com/owner/repo/merge_requests/1"))
    end)

    it("returns nil for empty or nil input", function()
        assert.is_nil(git.parse_github_url(""))
        assert.is_nil(git.parse_github_url(nil))
    end)
end)

describe("git.parse_branch_ticket", function()
    it("extracts ticket from branch name pattern ticket/description", function()
        local ticket = git.extract_linear_ticket("ENG-101/add-user-auth")
        assert.are.equal("ENG-101", ticket)
    end)

    it("handles branch names without tickets", function()
        assert.is_nil(git.extract_linear_ticket("feature/my-cool-feature"))
    end)
end)

describe("git.remote_matches", function()
    local orig

    before_each(function()
        orig = vim.fn.system
    end)
    after_each(function()
        vim.fn.system = orig
    end)

    it("matches HTTPS remote", function()
        vim.fn.system = function(_)
            return "https://github.com/acme/myrepo.git\n"
        end
        assert.is_true(git.remote_matches("acme", "myrepo"))
    end)

    it("matches SSH remote", function()
        vim.fn.system = function(_)
            return "git@github.com:acme/myrepo.git\n"
        end
        assert.is_true(git.remote_matches("acme", "myrepo"))
    end)

    it("returns false when owner/repo not in remote", function()
        vim.fn.system = function(_)
            return "https://github.com/other/repo.git\n"
        end
        assert.is_false(git.remote_matches("acme", "myrepo"))
    end)

    it("returns false when git command fails (empty output)", function()
        vim.fn.system = function(_)
            return ""
        end
        assert.is_false(git.remote_matches("acme", "myrepo"))
    end)
end)
