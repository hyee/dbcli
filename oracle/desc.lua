local env=env
local db,cfg=env.getdb(),env.set
local desc={}

local desc_sql={}

function desc.desc(name,option)
    env.checkhelp(name)
    env.set.set("autohide","on")
    local rs,success,err
    local obj=db:check_obj(name,1)
    local sql=(name..' '..(option or '')):trim(';')
    local typ=db.get_command_type(sql)
    if sql:sub(1,128):find(" ",1,true) and (typ=="WITH" or typ=="SELECT") then
        rs={query=sql,
            object_type="QUERY",
            object_name=loader:computeSQLIdFromText(sql),
            owner='<CURRENT_SCHEMA>'}
        rs[1],rs[2],rs[3],rs[4]=rs.owner,rs.object_name,rs.object_subname or "",rs.object_type
    elseif not obj and #name==13 and not name:find("%s") and name:find('^[a-z0-9]+$') then
        rs={object_type="SQL_ID",
            object_name=name,
            sql_id=name,
            owner=name}
        rs[1],rs[2],rs[3],rs[4]=rs.owner,rs.object_name,rs.object_subname or "",rs.object_type
    else
        env.checkerr(obj,"Cannot find target object: "..name)
        if obj.object_type=='SYNONYM' then
            local new_obj=db:dba_query(db.get_value,[[
                WITH r AS (
                SELECT /*+materialize cardinality(p 1) opt_param('_connect_by_use_union_all','old_plan_mode')*/
                        REFERENCED_OBJECT_ID OBJ, rownum lv
                FROM   PUBLIC_DEPENDENCY p
                START  WITH OBJECT_ID = :1
                CONNECT BY NOCYCLE PRIOR REFERENCED_OBJECT_ID = OBJECT_ID AND LEVEL<4)
                SELECT *
                FROM   (SELECT regexp_substr(obj,'[^/]+', 1, 1) + 0 object_id,
                            regexp_substr(obj,'[^/]+', 1, 2) owner,
                            regexp_substr(obj,'[^/]+', 1, 3) object_name,
                            regexp_substr(obj,'[^/]+', 1, 4) object_type
                        FROM (SELECT (SELECT o.object_id || '/' || o.owner || '/' || o.object_name || '/' ||
                                            o.object_type
                                    FROM   ALL_OBJECTS o
                                    WHERE  OBJECT_ID = obj) OBJ, lv
                            FROM   r)
                        ORDER  BY lv)
                WHERE  object_type != 'SYNONYM'
                AND    object_type NOT LIKE '% BODY'
                AND    owner IS NOT NULL
                AND    rownum<2]],{obj.object_id})
            if new_obj and new_obj[1] then
                obj.object_id,obj.owner,obj.object_name,obj.object_type=table.unpack(new_obj)
            end
        end

        rs={obj.owner,obj.object_name,obj.object_subname or "",
        (obj.object_subname or '')~='' and (obj.object_type=="PACKAGE" or obj.object_type=="TYPE") and "PROCEDURE" or obj.object_type}

        for k,v in pairs{owner=rs[1],object_name=rs[2],object_subname=rs[3],object_type=rs[4],object_id=obj.object_id} do
            rs[k]=v
        end

        if rs.object_type:find('^TABLE') and rs.object_name:find('MLOG$_',1,true)==1 then
            local is_mvlog=db:dba_query(db.get_value,[[select count(1) from all_mview_logs where LOG_OWNER=:owner and LOG_TABLE=:object_name]],rs)
            if is_mvlog==1 then
                rs.object_type='MATERIALIZED VIEW LOG'
            end
        end
    end

    local file=env.join_path(db.ROOT_PATH,'cmd','desc.'..rs.object_type:lower():gsub(' ','_')..'.lua')
    local sqls

    rs.desc=''
    if not os.exists(file) then
        sqls=desc_sql[rs[4]]
    else
        if (db.props.ccflags or "")~="" and db.props.ccflags~=db.props.curr_ccflags then
            pcall(db.internal_call,db,"ALTER SESSION SET PLSQL_CCFLAGS='"..db.props.ccflags.."'")
            db.props.curr_ccflags=db.props.ccflags
        end
        rs.load_sql=function(file,func)
            local res,rtn
            res,rtn=loadfile(file,'bt',{env=env,db=db,obj=rs,file=file})
            if type(res)=='function' then
                res,rtn=env.pcall(res)
            end
            env.checkerr(res,'Error on executing '..tostring(rtn):gsub(env.WORK_DIR,""))
            return rtn or res
        end
        rs.redirect=function(target)
            return rs.load_sql(file:gsub(rs.object_type:lower():gsub(' ','_')..'.lua$',target:lower()..'.lua'))
        end
        sqls=rs.load_sql(file)
        env.checkerr(type(sqls)=='table' or type(sqls)=='string',"Describing "..rs.object_type..' returns no result.')
    end

    if not sqls then return print("Cannot describe "..rs[4]..'!') end
    if type(sqls)~="table" then 
        sqls={sqls}
    else
        sqls={table.unpack(sqls)}
    end
    
    local dels='\n'..string.rep("=",80)
    local feed,autohide=cfg.get("feed"),cfg.get("autohide")
    cfg.set("feed","off",true)
    local title=("| %s : %s%s%s%s |"):format(rs.object_type,rs[1],rs[2]=="" and "" or "."..rs[2],rs[3]=="" and "" or "."..rs[3],rs.desc)
    print(("%s\n%s\n%s"):format(string.rep('-',#title),title,string.rep('-',#title)))
    for i,sql in ipairs(sqls) do
        if cfg.get("COLWRAP")==0 then cfg.set("COLWRAP",120) end
        cfg.set("PIVOT",sql:sub(1,256):find("/*PIVOT*/",1,true) and 1 or 0)
        cfg.set("autohide",sql:sub(1,256):find("/*NO_HIDE*/",1,true) and 'off' or 'col')

        local typ=db.get_command_type(sql)
        local result
        rs['v_cur']='#CURSOR'
        if typ=='DECLARE' or typ=='BEGIN' then
            db:dba_query(db.internal_call,sql,rs)
        else
            db:dba_query(db.internal_call,'BEGIN OPEN :v_cur FOR '..sql..';END;',rs)
        end
        result=rs.v_cur
        if type(result)=='userdata' then
            result=db.resultset:rows(result,-1)
            if #result>1 then
                local title=sql:match([[topic%s*=%s*['"](.-)['"].*]])
                if not title then 
                    print(dels)
                else
                    print('\n'..title..':\n'..string.rep('=',#title+1))
                end
                env.grid.print(result)
            end
        elseif db.C and db.C.dbmsoutput then
            db.C.dbmsoutput.getOutput({db,sql},true)
        end
        cfg.set("PIVOT",0)
    end
    cfg.set("COLWRAP",'default')

    if option and option:upper()=='ALL' then
        if rs[2]==""  then rs[2],rs[3]=rs[3],rs[2] end
        print(dels)
        cfg.set("PIVOT",1)
        db:dba_query([[SELECT * FROM ALL_OBJECTS WHERE OWNER=:1 AND OBJECT_NAME=:2 AND nvl(SUBOBJECT_NAME,' ')=nvl(:3,' ')]],rs)
    end
    cfg.temp("autohide",autohide,true)
    cfg.temp("feed",feed,true)
end

env.set_command(nil,{"describe","desc"},'Describe database object. Usage: @@NAME {[owner.]<object>[.<partition>|.<sub_program>] [all]} | <sql_id> | <query>',desc.desc,false,3)
return desc
