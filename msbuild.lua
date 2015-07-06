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

-- from https://stackoverflow.com/a/15278426
local function table_concat(t1, t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

--from https://stackoverflow.com/a/12674376/67873
local function table_keys(tbl)
	local keyset={}
	local n=0

	for k,v in pairs(tbl) do
	  n=n+1
	  keyset[n]=k
	end
	return keyset
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

local default_targets = {"Clean", "Build", "Rebuild"}

local function get_targets(filename)
	if filename:ends('.sln') then
		return default_targets
	end

	local f = io.open(filename, "r")
	if f == nil then
		return default_targets
	end
	local content = f:read("*all")
	f:close()

	local targets = {}
	for tgt in content:gmatch('<Target[^>]+Name="([^"]+)"') do
		table.insert(targets, tgt)
	end

	-- a VS project file: all the interesting targets are imported
	-- but we don't search the imports, so add in the defaults anyway
	if filename:ends('proj') and not filename:ends('.proj') then
		table_concat(targets, default_targets)
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
	return targets
	--local built = cross_build(target_prefixes, targets)
	--return built
end

-- flags either without arguments, or with arguments we can't complete
local plain_flags = {
	"/help", "/h",
	"/detailedsummary", "/ds",
	"/ignoreprojectextensions:", "/ignore:",
	"/maxcpucount", "/maxcpucount:", "/m", "/m:",
	"/noautoresponse", "/noautorsp",
	"/nodeReuse", "/nr",
	"/toolsversion:", "/tv:",
	"/ver", "/version",
	"/distributedFileLogger", "/dfl",
	"/distributedlogger:", "/dl:",
	"/fileLogger", "/fl",
	"/fileloggerparameters:", "/flp:",
	"/logger:", "/l:",
	"/noconsolelogger", "/noconlog"
}

-- flags with arguments we can complete
local flags_with_arguments = {}

local verbosities = {"q", "quiet", "m", "minimal", "n", "normal", "d", "detailed", "diag", "diagnostic"}
flags_with_arguments["/verbosity:"] = verbosities
flags_with_arguments["/v:"] = verbosities

local consoleloggerparameters = {"PerformanceSummary", "Summary", "NoSummary", "ErrorsOnly",
								 "WarningsOnly", "NoItemAndPropertyList", "ShowCommandLine",
								 "ShowTimestamp", "ShowEventId", "ForceNoAlign",
								 "DisableConsoleColor", "DisableMPLogging", "EnableMPLogging",
								 "Verbosity"}
flags_with_arguments["/consoleloggerparameters:"] = consoleloggerparameters
flags_with_arguments["/clp:"] = consoleloggerparameters

flags_with_arguments["/targets:"] = build_targets
flags_with_arguments["/t:"] = build_targets

-- NB: this doesn't actually list any schemas for some reason
local schemas_generator = files_with_extension_generator('.xsd')
flags_with_arguments["/validate:"] = schemas_generator
flags_with_arguments["/val:"] = schemas_generator

local all_flags = {}
table_concat(all_flags, plain_flags)
table_concat(all_flags, table_keys(flags_with_arguments))

local buildable_files_generator = files_with_extension_generator({'proj', '.sln'})

local function msbuild_parser2(text)
	if not text:starts('/') then
		return {} -- buildable_files_generator(text)
	end
	local idx = text:find(':')
	if idx == nil then
		for _, flg in ipairs(all_flags) do
			if clink.is_match(text, flg) then
				clink.add_match(flg)
				if flg:ends(':') then
					clink.suppress_char_append()
				end
			end
		end
		return {}
	end

	local flag = text:sub(0, idx)
	local follows = flags_with_arguments[flag]
	if type(follows) == "table" then
		return cross_build({flag}, follows)
	end
	if type(follows) == "function" then
		return cross_build({flag}, follows(text))
	end
end

-- Make assumption that the build file comes first.
-- This isn't really valid, but it makes things much easier.
local real_parser = clink.arg.new_parser()
real_parser:set_arguments({buildable_files_generator}, {msbuild_parser2})
real_parser:loop(2)

clink.arg.register_parser("msbuild", real_parser)
