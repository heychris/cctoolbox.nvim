-- luacheck: ignore
globals = {
    "vim",
}

overrides = {
    -- Change "spec" to "tests" if that is what your folder is named
    ["spec"] = {
        std = "+busted",
    },
}
