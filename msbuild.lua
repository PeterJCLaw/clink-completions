-- starts and ends from http://lua-users.org/wiki/StringRecipes

if string.starts == nil then
	function string.starts(String,Start)
		return string.sub(String,1,string.len(Start))==Start
	end
end

if string.ends == nil then
	function string.ends(String,End)
		return End=='' or string.sub(String,-string.len(End))==End
	end
end

local function get_command_line_parts(command_line)
    -- Split the given command line into parts.
    local parts = {}
    for _, sub_str in ipairs(clink.quote_split(command_line, "\"")) do
        -- Quoted strings still have their quotes. Look for those type of
        -- strings, strip the quotes and add it completely.
        if sub_str:sub(1, 1) == "\"" then
            local l, r = sub_str:find("\"[^\"]+")
            if l then
                local part = sub_str:sub(l + 1, r)
                table.insert(parts, part)
            end
        else
            -- Extract non-whitespace parts.
            for _, r, part in function () return sub_str:find("^%s*([^%s]+)") end do
                table.insert(parts, part)
                sub_str = sub_str:sub(r + 1)
            end
        end
    end
	return parts
end

local function get_specific_file(leading)
	local parts = get_command_line_parts(leading)

	for i, part in ipairs(parts) do
		-- 0th will be 'msbuild' or similar so skip it
		if i ~= 1 and not part:starts('/') then
			return part
		end
	end
end

local function self_test()
	local tests = {
		'',
		'msbuild /p:Configuration=Debug',
		'msbuild /t:Build thing.proj',
		'msbuild thing.proj',
		'msbuild something.xml',
		'msbuild nope'
	}
	for _, txt in ipairs(tests) do
		local ans = get_specific_file(txt)
		if ans == nil then
			ans = '<nil>'
		end
		print("Ans: -"..ans..'-')
	end
end

--self_test() do return end

local function files_with_extension(extensions)
    return function(mask, case_map)
        all_files = clink.find_files(mask, false)
        matching = {}
        for _, file in ipairs(all_files) do
			for _, ext in ipairs(extensions) do
				if file:ends(ext) then
					table.insert(matching, file)
				end
			end
        end
        return matching
    end
end

local function files_with_extension_generator(extensions)
	return function(word)
		-- directories
		clink.match_files(word.."*", true, clink.find_dirs)
		-- files matching the extension
		clink.match_files(word.."*", true, files_with_extension(extensions))
		clink.matches_are_files()
		return {}
	end
end

local function get_targets(filename)
	local f = io.open(filename, "r")
	if f == nil then
		return {}
	end
	local content = f:read("*all")
	f:close()

	local targets = {}
	for tgt in content:gmatch('<Target[^>]+Name="([^"]+)"') do
		table.insert(targets, tgt)
	end

	return targets
end

local function cross_build(prefixes, postfixes)
	local output = {}
	for _, prefix in ipairs(prefixes) do
		for _, postfix in ipairs(postfixes) do
			table.insert(output, prefix..postfix)
		end
	end
	return output
end

local target_prefixes = {"/t:", "/targets:"}
local function build_targets(word)
	local leading = rl_state.line_buffer:sub(0, rl_state.first)
	local filename = get_specific_file(leading)
	local targets = get_targets(filename)
	local built = cross_build(target_prefixes, targets)
	return built
end

parser = clink.arg.new_parser

local files_parser = parser({
	function(word) clink.matches_are_files() return clink.find_dirs(word.."*", false) end,
	function(word) return clink.find_files(word.."*", false) end
})

local msbuild_parser = parser()
msbuild_parser:set_flags({
	"/help", "/h",
	"/detailedsummary", "/ds",
	"/ignoreprojectextensions:", "/ignore:",
	"/maxcpucount", "/maxcpucount:", "/m", "/m:",
	"/noautoresponse", "/noautorsp",
	"/nodeReuse", "/nr",
	"/toolsversion:", "/tv:",
	"/validate:"..files_parser,
	"/val:"..files_parser,
	"/ver", "/validate",
	cross_build({"/verbosity:", "/v:"},
				{"q", "quiet", "m", "minimal", "n", "normal", "d", "detailed", "diag", "diagnostic"}),

	cross_build({"/consoleloggerparameters:", "/clp:"},
				{"PerformanceSummary", "Summary", "NoSummary", "ErrorsOnly", "WarningsOnly",
				 "NoItemAndPropertyList", "ShowCommandLine", "ShowTimestamp", "ShowEventId",
				 "ForceNoAlign", "DisableConsoleColor", "DisableMPLogging", "EnableMPLogging",
				 "Verbosity"}),
	"/distributedFileLogger", "/dfl",
	"/distributedlogger:", "/dl:",
	"/fileLogger", "/fl",
	"/fileloggerparameters:", "/flp:",
	"/logger:", "/l:",
	"/noconsolelogger", "/noconlog"
})
msbuild_parser:set_arguments(
    { files_with_extension_generator({'proj', '.sln'}) },
	{ build_targets, cross_build(target_prefixes, {"Clean", "Build", "Rebuild"}) }
)
msbuild_parser:disable_file_matching()

clink.arg.register_parser("msbuild", msbuild_parser)
