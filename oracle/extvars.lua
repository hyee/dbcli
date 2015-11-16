local env=env
local db,cfg,event=env.oracle,env.set,env.event 
local extvars={}

local instance_pattern={
    string.case_insensitive_pattern('%f[%w_%$:%.](("?)gv_?%$%a%a[%w_%$]*%2)([%s%),;])'),
    string.case_insensitive_pattern('%f[%w_%$:%.](sys%. *("?)gv_?%%a%a$[%w_%$]*%2)([%s%),;])'),
    string.case_insensitive_pattern('%f[%w_%$:%.](("?)x$%a[%w_%$]+%2)([%s%),;])'),
    string.case_insensitive_pattern('%f[%w_%$:%.](sys%. *("?)x$%a[%w_%$]+%2)([%s%),;])'),
    string.case_insensitive_pattern('%f[%w_%$:%.]( *("?)xv_?$%a[%w_%$]+%2)([%s%),;])'),
    string.case_insensitive_pattern('%f[%w_%$:%.](sys%. *("?)xv_?$%a[%w_%$]+%2)([%s%),;])')
}


function extvars.on_before_db_exec(item)
    local db,sql,args=table.unpack(item)
    args.starttime,args.endtime=cfg.get("starttime"),cfg.get("endtime")
    local instance=tonumber(cfg.get("instance"))
    args.instance=tostring(instance>0 and instance or instance<0 and "" or db.props.instance)
    return item
end

function extvars.on_before_parse(item)
    local db,sql,args,params=table.unpack(item)
    local instance=tonumber(cfg.get("instance"))
    if instance>-1 and sql:find('$',1,true) then
        if instance==0 then instance=db.props.instance end
        local rep='(select /*+merge*/ * from %s%%1 where inst_id='..instance..')%%3'
        for idx,pat in ipairs(instance_pattern) do
            sql= sql:gsub(pat,rep:format(idx>4 and 'sys.' or ''))
        end
        item[2]=sql
    end
    return item
end

function extvars.set_title(name,value,orig)
    local get=env.set.get
    if name~="STARTTIME" and name~="ENDTIME" and name~="INSTANCE" then return end
    local title=table.concat({tonumber(get("INSTANCE"))>-1   and "Inst="..get("INSTANCE") or "",
                              get("STARTTIME")~='' and "Start="..get("STARTTIME") or "",
                              get("ENDTIME")~=''   and "End="..get("ENDTIME") or ""},"  ")
    title=title:trim()
    env.set_title(title~='' and "Filter: ["..title.."]" or nil)
end

function extvars.check_time(name,value)
    if not value or value=="" then return "" end
    print("Time set as",db:check_date(value,'YYMMDDHH24MISS'))
    return value:trim()
end

function extvars.onload()
    event.snoop('BEFORE_DB_EXEC',extvars.on_before_parse,nil,1)
    event.snoop('BEFORE_ORACLE_EXEC',extvars.on_before_db_exec)
    event.snoop('ON_SETTING_CHANGED',extvars.set_title)
    cfg.init("instance",-1,nil,"oracle","Auto-limit the inst_id of gv$/x$ tables. -1: unlimited, 0: current, >0: specific instance","-1 - 99")
    cfg.init("starttime","",extvars.check_time,"oracle","Specify the start time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    cfg.init("endtime","",extvars.check_time,"oracle","Specify the end time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
end
return extvars