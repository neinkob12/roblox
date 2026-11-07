--!nocheck
-- Tiny assertion helper for scenarios.
--
--   T.check("cash went up", after > before, `before={before} after={after}`)
--   T.expectFail("#41", "plot freed on leave", cond)   -- known game bug, filed as an issue
--   T.finish()                                         -- prints a summary and exits 1 on failure

local process = require("@lune/process")

local T = {}
T.results = {}

local function record(kind, name, detail)
	table.insert(T.results, { kind = kind, name = name, detail = detail })
	local tag = if kind == "pass"
		then "PASS"
		elseif kind == "fail" then "FAIL"
		elseif kind == "xfail" then "XFAIL"
		else "XPASS"
	print(string.format("  %-5s %s%s", tag, name, if detail and kind ~= "pass" then "  (" .. detail .. ")" else ""))
end

function T.section(name)
	print("\n== " .. name)
end

function T.check(name, cond, detail)
	record(if cond then "pass" else "fail", name, detail)
	return cond
end

function T.eq(name, actual, expected)
	return T.check(name, actual == expected, `expected {tostring(expected)}, got {tostring(actual)}`)
end

-- A check that currently fails because of a filed game bug. If it starts passing, it is
-- reported as XPASS (also a failure) so the marker gets removed when the bug is fixed.
function T.expectFail(issue, name, cond, detail)
	if cond then
		record("xpass", `{name} [{issue} looks fixed: remove the expectFail]`, detail)
	else
		record("xfail", `{name} [known bug {issue}]`, detail)
	end
end

function T.finish()
	local counts = { pass = 0, fail = 0, xfail = 0, xpass = 0 }
	for _, r in T.results do
		counts[r.kind] += 1
	end
	print(
		string.format(
			"\n%d passed, %d failed, %d expected failures (known bugs), %d unexpected passes",
			counts.pass,
			counts.fail,
			counts.xfail,
			counts.xpass
		)
	)
	if counts.fail > 0 or counts.xpass > 0 then
		process.exit(1)
	end
	process.exit(0)
end

return T
