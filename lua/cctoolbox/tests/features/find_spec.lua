local find = require("cctoolbox.features.find")

describe("find.parse_find_output", function()
    it("parses a simple file:line entry", function()
        local entries = find.parse_find_output("lua/foo.lua:10")
        assert.are.equal(1, #entries)
        assert.are.equal("lua/foo.lua", entries[1].filename)
        assert.are.equal(10, entries[1].lnum)
    end)

    it("parses multiple entries", function()
        local text = "lua/foo.lua:10\nlua/bar.lua:25\nsrc/baz.ts:100"
        local entries = find.parse_find_output(text)
        assert.are.equal(3, #entries)
        assert.are.equal("lua/foo.lua", entries[1].filename)
        assert.are.equal(10, entries[1].lnum)
        assert.are.equal("lua/bar.lua", entries[2].filename)
        assert.are.equal(25, entries[2].lnum)
        assert.are.equal("src/baz.ts", entries[3].filename)
        assert.are.equal(100, entries[3].lnum)
    end)

    it("returns empty table for empty input", function()
        local entries = find.parse_find_output("")
        assert.are.same({}, entries)
    end)

    it("skips blank lines", function()
        local text = "\nlua/foo.lua:5\n\nlua/bar.lua:10\n"
        local entries = find.parse_find_output(text)
        assert.are.equal(2, #entries)
    end)

    it("skips lines without a colon+number pattern", function()
        local text = "just some text\nlua/foo.lua:42\nno match here"
        local entries = find.parse_find_output(text)
        assert.are.equal(1, #entries)
        assert.are.equal("lua/foo.lua", entries[1].filename)
    end)

    it("handles file:line:col format by ignoring column", function()
        local entries = find.parse_find_output("lua/foo.lua:10:5")
        assert.are.equal(1, #entries)
        assert.are.equal("lua/foo.lua", entries[1].filename)
        assert.are.equal(10, entries[1].lnum)
    end)

    it("preserves optional description text after file:line", function()
        local entries = find.parse_find_output("lua/foo.lua:10: some description here")
        assert.are.equal(1, #entries)
        assert.truthy(entries[1].text and entries[1].text:find("some description"))
    end)

    it("handles Windows-style paths with backslashes", function()
        local entries = find.parse_find_output("src\\foo.ts:15")
        assert.are.equal(1, #entries)
        assert.are.equal(15, entries[1].lnum)
    end)
end)
