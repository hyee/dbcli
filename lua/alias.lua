local env, globalcmds = env, env._CMDS
local alias = {command_dir = env.join_path(env.WORK_DIR, "aliases", ""), cmdlist = {}}
alias.db_dir = alias.command_dir
local comment = "(.-)[\n\r\b\t%s]*$"

function alias.rehash()
    for k, v in pairs(alias.cmdlist) do
        if v.active then
            globalcmds[k] = nil
            env.remove_command(k)
        end
    end
    
    alias.cmdlist = {}
    local keys = os.list_dir(alias.command_dir, "alias", nil, function(event, file)
        if event == 'ON_SCAN' then
            if file.fullname:lower() == (alias.command_dir .. file.name):lower() or
                file.fullname:lower() == (alias.db_dir .. file.name):lower() then
                return true
            end
            return false
        end
        if not file.data then return end
        local text
        if type(comment) == "string" then
            text = file.data:match(comment)
        elseif type(comment) == "function" then
            text = comment(file.data)
        end
        return text or ""
    end)
    for _, file in ipairs(keys) do
        alias.set(file.shortname, file.data, false)
    end
end

function alias.parser(s, default_value)
    if s ~= "*" then
        local v = tonumber(s)
        if v < 1 or v > 9 then return ("$" .. s) .. (default_value and '[' .. default_value .. ']' or '') end
        if (not alias.args[v] or alias.args[v] == "") and default_value then alias.args[v] = default_value end
        alias.rest[v] = ""
        return alias.args[v]
    else
        for i = #alias.rest, 1, -1 do
            if alias.rest[i] == "" then table.remove(alias.rest, i) end
        end
        local res = table.concat(alias.rest, " ")
        alias.rest = {}
        return res
    end
end

function alias.make_command(name, args, is_print)
    name = name:upper()
    if alias.cmdlist[name] and env._CMDS[name] and env._CMDS[name].FUNC == alias.run_command then
        local target = alias.cmdlist[name].text
        if type(target) == "function" then target = target(alias) end
        target = target .. " $*"
        alias.args = args
        alias.rest = {}
        for i = 1, 99 do
            local v = alias.args[i] or ""
            if v:find("%s") and not v:find('"') then v = '"' .. v .. '"' end
            alias.args[i] = v
            alias.rest[i] = v
        end
        target = target:gsub("%f[\\%$]%$(%d+)%[(.-)%]", alias.parser)
        target = target:gsub("%f[\\%$]%$([%d%*]+)", alias.parser)
        target = target:gsub("%s+$", "")
        target = target:gsub("\\%$", "$")
        --if env.COMMAND_SEPS.match(target)==target then target=target..env.COMMAND_SEPS[1] end
        if is_print ~= false and type(alias.cmdlist[name].text) == "string" and not target:find('[\n\r]') then
            print('$ ' .. target)
        end
        return target
    end
end

function alias.run_command(...)
    local cmd = alias.make_command(env.CURRENT_CMD, {...})
    if cmd then
        env.eval_line(cmd .. '\0', true, false, true)
    end
end


function alias.set(name, cmd, write)
    if not name and write ~= false then
        return exec_command("HELP", {"ALIAS"})
    end
    
    name = name:upper()
    
    if name == "-R" then
        return alias.rehash()
    elseif name == "-E" and cmd then
        local text = alias.cmdlist[cmd:upper()]
        if not text then
            return print("Error: Cannot find this alias :" .. cmd)
        end
        if type(text.text) == "function" then
            return print("Error: Command has been encrypted: " .. cmd)
        end
        alias.set(cmd, packer.unpack_str(text.text))
    elseif not cmd then
        if not alias.cmdlist[name] then return end
        if alias.cmdlist[name].active then
            globalcmds[name] = nil
            env.remove_command(name)
        end
        alias.cmdlist[name] = nil
        os.remove(alias.command_dir .. name:lower() .. ".alias")
        os.remove(alias.db_dir .. name:lower() .. ".alias")
        print('Alias "' .. name .. '" is removed.')
    else
        if not name:match("^[%w_]+$") then
            return print("Alias '" .. name .. "' is invalid. ")
        end
        cmd = env.COMMAND_SEPS.match(cmd)
        if not cmd or cmd:trim() == "" then return end
        local sub_cmd = env.parse_args(2, cmd)[1]:upper()

        
        if write ~= false then
            os.remove(alias.command_dir .. name:lower() .. ".alias")
            os.remove(alias.db_dir .. name:lower() .. ".alias")
            local f = io.open(alias.db_dir .. name:lower() .. ".alias", "w")
            f:write(cmd)
            f:close()
        end
        
        if not alias.cmdlist[name] then
            alias.cmdlist[name] = {}
        end
        
        local desc
        if cmd:sub(1, 5) ~= "FUNC:" then
            desc = cmd:gsub("%s+", " "):sub(1, 300)
        else
            cmd = packer.unpack(cmd)
            desc = cmd
        end
        if type(desc) == "string" then desc = env.COMMAND_SEPS.match(desc) end
        alias.cmdlist[name].desc = desc
        alias.cmdlist[name].text = cmd
        alias.cmdlist[name].active = false
        if not globalcmds[name] then
            env.set_command(nil, name, "#Alias command(" .. sub_cmd .. ")", alias.run_command, false, 99, false, true)
            alias.cmdlist[name].active = true
        elseif globalcmds[name].FUNC == alias.run_command then
            alias.cmdlist[name].active = true
        end

        if alias.cmdlist[name].active then
            env._CMDS[name].ALIAS_TO=desc:match('%S+'):upper()
        end
    end
end

function alias.helper()
    local help = [[
    Set a shortcut of other existing command. Usage: @@NAME [-r] | {<name> [parameters]} | {-e <name>}
    1) Set/modify alias: @@NAME <name> <command>. Available wildcards: $1 - $9, or $*
                         $1 - $9 can have default value, format as: <$1-$9>[<value>]
    2) Remove alias    : @@NAME <name>
    3) Reload aliases  : @@NAME -r
    4) Encrypt alias   : @@NAME -e <name>

    All aliases are permanently stored in the "aliases" folder.
    Examples:
         @@NAME test pro $1                  => "test 122"                    = "pro 122"
         @@NAME ss select * from $1[dual]    => "ss"                          = "select * from dual"
         @@NAME test conn $1/$2@$*           => "test sys pwd orcl as sysdba" = "conn sys/pwd@orcl as sysdba"
    Current aliases:
    ================]]

    local grid, rows = env.grid, {{"Name", "Active?", "Command"}}
    local active
    for k, v in pairs(alias.cmdlist) do
        if not env._CMDS[k]['FILE']:match("alias") then
            active = 'No'
        else
            active = 'Yes'
        end
        alias.cmdlist[k].active = active
        table.insert(rows, {k, active, tostring(alias.cmdlist[k].desc)})
    end
    grid.sort(rows, 1, true)
    for _, k in ipairs(grid.format(rows)) do
        help = help .. '\n' .. k
    end
    return help
end

function alias.load_db_aliases(db_name)
    alias.db_dir = env.join_path(alias.command_dir, db_name, '')
    loader:mkdir(alias.db_dir)
    alias.rehash()
end

function alias.rewrite(command)
    local cmd, args = table.unpack(command)
    local name = cmd:upper()
    if alias.cmdlist[name] then
        local line = alias.make_command(name, args)
        if line then
            command[1], command[2] = env.eval_line(line, false)
        end
        return command
    end
    return nil
end

function alias.onload()
    --alias.rehash()
    --env.event.snoop('BEFORE_COMMAND',alias.rewrite,nil,80)
    --env.event.snoop('ON_ENV_LOADED',alias.rehash,nil,1)
    loader:mkdir(alias.command_dir)
    env.event.snoop('ON_DB_ENV_LOADED', alias.load_db_aliases, nil, 1)
    env.set_command{obj = nil, cmd = "alias",
        help_func = alias.helper,
        call_func = alias.set,
        is_multiline = '__SMART_PARSE__', parameters = 3, color = "PROMPTCOLOR"}
end

return alias
