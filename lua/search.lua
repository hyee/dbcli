local env=env

local uv=env.uv

local search={}

function search.do_search(typ,filter)
    local grid=env.grid
    env.checkhelp(typ)
    if not filter then 
        typ,filter=nil,typ
    elseif typ:lower()=="cmd" then
        typ={sql=1,snap=1,chart=1}
    else
        typ={[typ:lower()]=1} 
    end
    local dirs={env.WORK_DIR}
    env.event.callback("ON_SEARCH",dirs)
    local excludes={'dump','bin','cache','docs','data','jre'}
    for k,subdir in ipairs(excludes) do excludes[k]=env.join_path(env.WORK_DIR,subdir,''):lower() end
    excludes[#excludes+1]=env._CACHE_BASE:lower()
    filter=filter:gsub('%%','\1\2\1'):lower():escape():gsub('\1\2\1','.*')
    local fmt,count="%-99s: %s",0
    local rows=grid.new()

    rows:add{"File",'Line#','Text'}
    local function scan(event,file)
        if count>=10000 or file.data and file.data:sub(1,64):find('[\1-\8]') then return end
        if typ then
            local suffix=file.fullname:lower():match('%.([^%.]+)$')
            if not suffix or not typ[suffix] then return end
        end
        if event=='ON_SCAN' then
            for _,subdir in ipairs(excludes) do
                if file.fullname:lower():find(subdir,1,true) then return end
            end
            return 1024*1024
        end

        if file.fullname:find(filter) then
            rows:add({file.fullname,0,""})
        end

        for line_text,_,line_no in file.data:gsplit('\n',true) do
            if #line_text<=1000 and line_text:lower():find(filter) then
                count=count+1
                rows:add({file.fullname,line_no,(line_text:trim():gsub('%s+',' '))})
            end
            if count>=10000 then return end
        end
    end
    os.list_dir(dirs,nil,nil,scan,nil,true)
    rows:print()
    print('\n'..count.. ' lines matched.')
end

function search.onload()
    env.set_command{cmd='search',help_func='Search text based on Lua regular expression. Usage: @@NAME [cmd|<file extension>] <text>',parameters=3,call_func=search.do_search}
end

return search