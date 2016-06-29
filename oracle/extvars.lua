local env=env
local db,cfg,event,var=env.getdb(),env.set,env.event,env.var
local extvars={}
local datapath=debug.getinfo(1, "S").source:sub(2):gsub('[%w%.]+$','dict')
local re=env.re

function extvars.on_before_db_exec(item)
    if not var.outputs['INSTANCE'] then
        local instance=tonumber(cfg.get("INSTANCE"))
        var.setInputs("INSTANCE",tostring(instance>0 and instance or instance<0 and "" or db.props.instance))
    end
    if not var.outputs['STARTTIME'] then
        var.setInputs("STARTTIME",cfg.get("STARTTIME"))
    end
    if not var.outputs['ENDTIME'] then
        var.setInputs("ENDTIME",cfg.get("ENDTIME"))
    end
    return item
end

local fmt='%s(select /*+merge*/ * from %s where %s=%d :others:)%s'
local instance,container
local function rep_instance(prefix,full,obj,suffix)
    obj=obj:upper()
    local flag,str=0
    if instance>0 and extvars.dict[obj] and extvars.dict[obj].inst_col then
        str=fmt:format(prefix,full,extvars.dict[obj].inst_col,instance,suffix)
        flag=flag+1
    end
    if container>0 and extvars.dict[obj] and extvars.dict[obj].cdb_col then
        if flag==0 then
            str=fmt:format(prefix,full,extvars.dict[obj].cdb_col,container,suffix)
        else
            str=str:gsub(':others:','and '..extvars.dict[obj].cdb_col..'='..container)
        end
        flag=flag+2
    end
    if flag==0 then
        str=prefix..full..suffix
    elseif flag<3 then 
        str=str:gsub(' :others:','') 
    end
    env.log_debug('extvars',str)
    return str
end

function extvars.on_before_parse(item)
    local db,sql,args,params=table.unpack(item)
    instance,container=tonumber(cfg.get("instance")),tonumber(cfg.get("container"))
    if instance==0 then instance=tonumber(db.props.instance) end
    if container==0 then container=tonumber(db.props.container_id) end
    if instance>0 or container>0 then
        item[2]=re.gsub(sql..' ',extvars.P,rep_instance):sub(1,-2)
    end
    return item
end

function extvars.set_title(name,value,orig)
    local get=env.set.get
    local title=table.concat({tonumber(get("INSTANCE"))>-1   and "Inst="..get("INSTANCE") or "",
                              tonumber(get("CONTAINER"))>-1   and "Con_id="..get("CONTAINER") or "",
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

function extvars.set_instance(name,value)
    if tonumber(value)==-2 then
        local dict={}
        local rs=db:internal_call([[
            SELECT table_name,
                   MAX(CASE WHEN COLUMN_NAME IN ('INST_ID', 'INSTANCE_NUMBER') THEN COLUMN_NAME END) INST_COL,
                   MAX(CASE WHEN COLUMN_NAME IN ('CON_ID') THEN COLUMN_NAME END) CON_COL
            FROM   (SELECT table_name, column_name
                    FROM   dba_tab_cols, dba_users
                    WHERE  user_id IN (SELECT SCHEMA# FROM sys.registry$ UNION ALL SELECT SCHEMA# FROM sys.registry$schemas)
                    AND    username = owner
                    AND    column_name IN ('INST_ID', 'INSTANCE_NUMBER', 'CON_ID')
                    UNION ALL
                    SELECT t.kqftanam, c.kqfconam
                    FROM   x$kqfta t, x$kqfco c
                    WHERE  c.kqfconam IN ('INST_ID', 'INSTANCE_NUMBER', 'CON_ID')
                    AND    c.kqfcotab = t.indx
                    AND    c.inst_id = t.inst_id)
            GROUP  BY TABLE_NAME]])
        local rows=db.resultset:rows(rs,-1)
        for i=2,#rows do
            dict[rows[i][1]]={inst_col=(rows[i][2]~="" and rows[i][2] or nil),cdb_col=(rows[i][3]~="" and rows[i][3] or nil)}
            local prefix,suffix=rows[i][1]:match('(.-$)(.*)')
            if prefix=='GV_$' or prefix=='V_$' then
                dict[prefix:gsub('_','')..suffix]=dict[rows[i][1]]
            end
        end
        env.save_data(datapath,dict)
        extvars.dict=dict
        print((#rows-1)..' records saved into '..datapath)
    end
    return tonumber(value)
end

function extvars.set_container(name,value)
    env.checkerr(db.props.db_version and tonumber(db.props.db_version:match('%d+')),'Unsupported version!')
    return tonumber(value)
end

function extvars.onload()
    event.snoop('BEFORE_DB_EXEC',extvars.on_before_parse,nil,50)
    event.snoop('BEFORE_ORACLE_EXEC',extvars.on_before_db_exec)
    event.snoop('ON_SETTING_CHANGED',extvars.set_title)
    cfg.init("instance",-1,extvars.set_instance,"oracle","Auto-limit the inst_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-2 - 99")
    cfg.init({"container","con","con_id"},-1,extvars.set_container,"oracle","Auto-limit the con_id of impacted tables. -1: unlimited, 0: current, >0: specific instance","-1 - 99")
    cfg.init("starttime","",extvars.check_time,"oracle","Specify the start time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    cfg.init("endtime","",extvars.check_time,"oracle","Specify the end time(in 'YYMMDD[HH24[MI[SS]]]') of some queries, mainly used for AWR")
    extvars.dict=env.load_data(datapath)
    extvars.P=re.compile([[
        pattern <- {pt} {owner* obj} {suffix}
        suffix  <- [%s,;)]
        pt      <- [%s,(]
        owner   <- ('SYS.'/ 'PUBLIC.'/'"SYS".'/'"PUBLIC".')
        obj     <- full/name
        full    <- '"' name '"'
        name    <- {prefix %a%a [%w$#__]+}
        prefix  <- "GV_$"/"GV$"/"V_$"/"V$"/"DBA_"/"ALL_"/"CDB_"
    ]],nil,true)
end
return extvars