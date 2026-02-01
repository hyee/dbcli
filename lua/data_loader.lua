local loader=env.class()
local env=env

local db_loader=java.require("com.opencsv.DBLoader",true)
local db_unloader=java.require("com.opencsv.DBUnloader",true)
function loader:ctor()
    self.load_command='load'
    self.unload_command='unload'
    self.db=env.getdb()
    self.load_helps=[[
        Load data from a CSV file into a table. usage: @@NAME <target_table> <src_csv> [SET options]

        Load options(case-insensitive):
        ===============================
        * show off|all|ddl|dml              : Show DDL/DML statement only and do not load CSV file:  ddl=show DDL only, dml=show DML only, all=show both DDL and DML
        * show_ddl|ddl                      : Show DDL only and do not load CSV file
        * show_dml|dml                      : Show DML only and do not load CSV file
        * create|new  off|on                : Show DDL and create table from CSV (default: off)
        * scan_rows|scanrows|scan <number>  : Used together with show/show_ddl/create, number of rows to scan for column names (default: 200)
        * column_size auto|actual|maximum   : Used together with show/show_ddl/create, Column size strategy (default: auto)
        * truncate on|off                   : Truncate table before loading (default: off)
        * errors <number>|-1                : Number of errors to allow before stopping, -1 as unlimited (default: 100)
        * batch_rows|batchrows <number>     : Number of rows to batch per insert (default: 2048)
        * bad_file|badfile auto|<filepath>  : Bad file path to store failed rows, auto as create at target csv folder(default: auto)
        * row_limit|rowlimit|limit <number> : Maximum number of rows to load (default: 0, unlimited)
        * report_mb|report <number>|-1      : Report progress every N MB loaded, -1 will suppress all messages (default: 8)
        * strict_mode|strict                : Strict number conversion to avoid overflow,such as number with decimal digits cannot cast to integer (default: off)
        * variable_format|var ?|:           : Variable format used in DML statement (default: ?)
        * platform auto|<platform>          : Database platform used to generate DDL/DML statement(default: auto)
                                              Avail options: mysql, oracle, pgsql, sqlserver, db2, mssql, postgresql
        * map_column_names|mapcolumnnames   : Map CSV column names to table column names,column mappings are case-insensitive.
          |mapnames (CSV_COL=TABLE_COL,...)   e.g.: map_column_names (ID=OBJECT_ID,NAME=OBJECT_NAME)
        
        CSV format options(case-insensitive):
        =====================================   
        * has_header|header on|off                                  : Whether the first row is a header row (default: on)
        * encoding <charset>                                        : Character encoding of CSV file (default: "")
        * delimiter <chars>                                         : CSV delimiter character (default: ,)
        * enclosure <chars>                                         : CSV enclosure character (default: ")
        * escape <char>                                             : CSV escape character (default: \)
        * unescape_newline|unescape                                 : Whether to unescape string "\n" and "\r" as CRLF for string column (default: off)
        * skip_rows|skiprows|skip <number>                          : Number of rows to skip if CSV rows is not started from the first row (default: 0)
        * skip_columns|skipcols (column1,column2,...)|off|auto      : Columns to be skipped from loading (default: auto)
        
        Timestamp format options:
        =============================
        * format :  Transform the blow 3 formats from Oracle format to Java format when values,if set as 'java' then no transformation will be taken.
                    When format is 'oracle'(default), the formats will be replaced into Java format:
                        * YYYY or yyyy or yy => yyyy or yy
                        * MON or mon         => MMMM
                        * MM or mm           => MM
                        * DD or dd           => dd
                        * HH or hh           => hh
                        * HH24 or hh24       => HH
                        * MI or mi           => mm
                        * SS or ss           => ss
                        * .ff or xff or xff3 => .SSS
                        * .ff5 or xff6       => .SSSSS
                        * TZH:TZM or tzh:tzm => XXX
                        * TZR or tzr         => XXX
                    You should set this option as 'java' firstly if you want to directly specify the Java formats.
        * date_format|dateformat|date <format>                      : Date format string (default: auto)
        * timestamp_format|timestampformat|timestamp <format>       : Timestamp format string (default: auto)
        * timestamptz_format|timestamptzformat|timestamptz <format> : Timestamp with timezone format string (default: auto)
        * locale <locale>                                           : Locale used to parse date/timestamp (default: "")
    ]]

    self.unload_helps=[[
        Unload data from SELECT statement into CSV/SQL/JSON file. usage: @@NAME <savepath> <SQL_file>|"<SQL>" [SET <options>]

        Unload options(case-insensitive):
        ===============================
        * file_format|file_type|type        : Target file type, can be CSV, SQL or JSON (default:CSV)
        * batch_rows|batchrows <number>     : Number of rows prefeched from ResultSet (default: 2048)
        * row_limit|rowlimit|limit <number> : Maximum number of rows to unload (default: 0, unlimited)
        * report_mb|report <number>|-1      : Report progress every N MB loaded, -1 will suppress all messages (default: 8)
        * has_header|header on|off          : Whether the first row is a header row (default: on)
        * platform auto|<platform>          : Database platform used to generate DDL/DML statement(default: auto)
                                              Avail options: mysql, oracle, pgsql, sqlserver, db2, mssql, postgresql
        * map_column_names|mapcolumnnames   : Map CSV column names to table column names,column mappings are case-insensitive.
          |mapnames (CSV_COL=TABLE_COL,...)   e.g.: map_column_names (ID=OBJECT_ID,NAME=OBJECT_NAME)
        * skip_columns|skipcols             : Columns to be skipped from unloading (default: auto)
          (column1,column2,...)|off|auto    
        
        JSON format options(case-insensitive):
        =====================================
        * JSON_ROW_TYPE|JSON_TYPE OBJECT|ARRAY                      : Number of spaces to indent for JSON output (default: OBJECT)
                                                                      OBJECT: Each row is a JSON object.
                                                                      ARRAY: Each row is a JSON array,the first row is the header row(controlled by HASH_HEADER).
        * JSON_KEEP_NULLS|JSONKEEPNULLS ON|OFF                      : When JSON_ROW_TYPE is OBJECT, whether to keep null values in JSON output (default: on)
        * JSON_NULL_VALUE|JSONNULLVALUE <value>                     : JSON null value (default: null)
        
                                                                      CSV format options(case-insensitive):
        =====================================
        * delimiter <chars>                                         : CSV delimiter character (default: ,)
        * enclosure <chars>                                         : CSV enclosure character (default: ")
        * escape <char>                                             : CSV escape character (default: \)
        * unescape_newline|unescape                                 : Whether to unescape string "\n" and "\r" as CRLF for string column (default: off)
        * skip_rows|skiprows|skip <number>                          : Number of rows to skip if CSV rows is not started from the first row (default: 0)
        
        
        Timestamp format options:
        =============================
        * format :  Transform the blow 3 formats from Oracle format to Java format when values,if set as 'java' then no transformation will be taken.
                    When format is 'oracle'(default), the formats will be replaced into Java format:
                        * YYYY or yyyy or yy => yyyy or yy
                        * MON or mon         => MMMM
                        * MM or mm           => MM
                        * DD or dd           => dd
                        * HH or hh           => hh
                        * HH24 or hh24       => HH
                        * MI or mi           => mm
                        * SS or ss           => ss
                        * .ff or xff or xff3 => .SSS
                        * .ff5 or xff6       => .SSSSS
                        * TZH:TZM or tzh:tzm => XXX
                        * TZR or tzr         => XXX
                    You should set this option as 'java' firstly if you want to directly specify the Java formats.
        * date_format|dateformat|date <format>                      : Date format string (default: auto)
        * timestamp_format|timestampformat|timestamp <format>       : Timestamp format string (default: auto)
        * timestamptz_format|timestamptzformat|timestamptz <format> : Timestamp with timezone format string (default: auto)
        * locale <locale>                                           : Locale used to parse date/timestamp (default: "")
    ]]
end

function loader:parse_options(src_file,options)
    local typ,file=os.exists(src_file)
    if not typ then
        if not src_file:sub(1,128):find('[\\/]') then
            file=env.join_path(env._CACHE_BASE,src_file)
        else
            file=env.resolve_file(src_file)
        end
    end
    --env.checkerr(typ=="file","Target file %s does not exist.",src_file)
    local function next_token(pattern,lower)
        if options:sub(1,1)=='"' then
            local st,ed=(options..' '):find('"[^"]+"%s')
            env.checkerr(st,"Unrecognized options: "..options)
            local piece=options:sub(st,ed):trim():sub(2,-2):trim()
            options=options:sub(ed):trim()
            return lower~=false and piece:lower() or piece
        else
            local st,ed=options:find('^'..(pattern or '%S+'))
            if st then
                local piece=options:sub(st,ed)
                options=options:sub(ed+1):trim()
                return lower~=false and piece:lower() or piece
            end
            return nil
        end
    end

    local cfg={TARGET_FILE=file}
    local function push(opt,value,upper)
        if type(value)=="string" then 
            value=value:trim()
            if upper~=false then value=value:upper() end
        end
        cfg[opt:upper()]=value
    end

    local names={
        file_format={"csv","sql","json"},
        show={"off","all","ddl","dml"},
        create={"off","on"},
        truncate={"off","on"},
        errors={100},
        bad_file={"auto"},
        batch_rows={2048},
        has_header={"on","off"},
        row_limit={0},
        skip_rows={0},
        skip_columns={"auto"},
        scan_rows={200},
        report_mb={8},
        trict_mode={"off","on"},
        variable_format={"?",":"},
        json_row_type={"object","array"},
        json_keep_nulls={"on","off"},
        json_null_value={"null"},
        platform={"auto","oracle","mysql","pgsql","sqlserver","db2",'mssql','postgresql'},
        delimiter={","},
        enclosure={'"'},
        escape={[[\]]},
        unescape_newline={"on","off"},
        column_size={"auto","actual","maximum"},
        format={"oracle","java","mysql","pgsql","sqlserver","db2",'mssql','postgresql'},
        date_format={"auto"},
        timestamp_format={"auto"},
        timestamptz_format={"auto"},
        map_column_names={},
        encoding={"auto"}
    }

    for n,v in pairs(names) do
        v.name=n
        if #v>1 then
            local maps={}
            for _,v in ipairs(v) do
                maps[v:upper()]=true
            end
            v.maps=maps
        end
        push(n,v[1])
    end

    push("platform",env.set.get("platform"))
    for _,v in ipairs(names.file_format) do
        if file:lower():find('.'..v,1,true) then
            push('FILE_FORMAT',v)
        end
    end

    for n,v in pairs{
        type=names.file_format,
        file_type=names.file_format,
        new=names.create,
        show_ddl={"ddl","ddl",name="show"},
        show_dml={"dml","ddl",name="show"},
        ddl={"ddl","ddl",name="show"},
        dml={"dml","ddl",name="show"},
        strict=names.trict_mode,
        badfile=names.bad_file,
        jsonrowtype=names.json_row_type,
        json_type=names.json_row_type,
        jsonkeepnulls=names.json_keep_nulls,
        jsonnullvalue=names.json_null_value,
        bad=names.bad_file,
        skip=names.skip_rows,
        skiprows=names.skip_rows,
        skipcols=names.skip_columns,
        rowlimit=names.row_limit,
        limit=names.row_limit,
        header=names.has_header,
        scan=names.scan_rows,
        scanrows=names.scan_rows,
        date=names.date_format,
        dateformat=names.date_format,
        timestamp=names.timestamp_format,
        timestampformat=names.timestamp_format,
        timestamptz=names.timestamptz_format,
        timestamptzformat=names.timestamptz_format,
        mapcolumnnames=names.map_column_names,
        mapnames=names.map_column_names,
        batchrows=names.batch_rows,
        report=names.report_mb,
        var=names.variable_format,
        unescape=names.unescape_newline,
        locale={""}
    } do
        names[n]=v
        if #v>1 then
            local maps={}
            for _,v in ipairs(v) do
                maps[v:upper()]=true
            end
            v.maps=maps
        end
    end

    if self.init_options then
        self.init_options(cfg)
    end

    if options and options:trim()~="" then
        options=options:trim()
        local opt=next_token()
        env.checkhelp(opt=='set' and true or nil)
        while true do
            opt=next_token()
            ::parse_opt::
            if not opt then break end
            local val=names[opt]
            env.checkerr(val,"Unrecognized option: "..opt:upper())
            if val.name=="map_column_names" then
                local maps=next_token("%b()")
                if not maps then
                    local next_=(next_token() or "nil")
                    env.checkerr(maps,"Invalid option \""..opt:upper().."\" value: "..next_)
                end
                local mappings={}
                for csv_col,table_col in maps:sub(2,-2):gmatch("%s*([^= ]+)%s*=%s*([^, ]+)") do
                    mappings[csv_col:upper()]=table_col
                end
                push(val.name,mappings)
            elseif val.name=="skip_columns" then
                local cols=next_token("%b()")
                if cols then
                    push(val.name,cols)
                else
                    cols=next_token()
                    env.checkerr(cols=="off" or cols=="auto","Invalid option \""..opt:upper().."\" value: "..(cols or "nil"))
                    push(val.name,cols)
                end
            elseif val.name=='bad_file' then
                local fmt=next_token(nil,false)
                env.checkerr(fmt and not names[fmt:lower()],"Invalid option \""..opt:upper().."\" value: "..(fmt or "nil"))
                if fmt:lower()~='auto' then
                    fmt=env.join_path(fmt)
                    if not fmt:find('[\\/]') then
                        fmt=env.join_path(env._CACHE_BASE,fmt)
                    end
                end
                push(val.name,fmt,false)
            elseif val.name=="date_format" or val.name=="timestamp_format" or val.name=="timestamptz_format" then
                local fmt=next_token(nil,false)
                env.checkerr(fmt and not names[fmt:lower()],"Invalid option \""..opt:upper().."\" value: "..(fmt or "nil"))
                if cfg.FORMAT~='JAVA' then
                    fmt=fmt:lower()
                    fmt=fmt:gsub('%.(S+)',function(s) return '.'..s:upper() end)
                    fmt=fmt:gsub('([%.x]ff)(%d*)',function(s,d) return '.'..('S'):rep(tonumber(d) or 3) end)
                    for k,v in pairs{
                        ['mm']='MM',
                        ['mon']='MMM',
                        ['hh24']='HH',
                        ['mi']='mm',
                        ['"']="'",
                        ['tzh:tzm']='XXX',
                        ['tzr']='XXX'
                    } do
                        fmt=fmt:gsub(k,v)
                    end
                    fmt=fmt:gsub('z$','Z'):gsub('(x+)$',function(s) return '.'..s:upper() end)
                end
                push(val.name,fmt,false)
            elseif type(val[1])=="number" then
                local num=next_token()
                env.checkerr(num and tonumber(num),"Invalid option \""..opt:upper().."\" value: "..(num or "nil"))
                push(val.name,tonumber(num))
            else
                local option=next_token() or ""
                if val.maps then
                    if val.maps[option:upper()] then
                        push(val.name,option)
                    else
                        if option=='' or names[option] then
                            push(val.name,val[2])
                            if option=='' then
                                break
                            end
                        end
                        opt=option
                        goto parse_opt
                    end
                elseif option then
                    if names[option] then
                        goto parse_opt
                    else
                        push(val.name,option)
                    end
                end
            end
        end
        env.checkerr(options=="","Unrecognized remaining options: "..options:upper())
    end

    return cfg,typ
end

function loader:load(target_table,src_file,options)
    env.checkhelp(src_file)
    local cfg,typ=self:parse_options(src_file,options)
    env.checkerr(typ=="file","Target file %s does not exist.",src_file)
    local db=self.db
    if db:is_connect() and db.check_obj then
        local validate=cfg.CREATE=='OFF' and cfg.show~='OFF'
        local obj=db:check_obj(target_table,validate and 1 or 0)
        env.checkerr(not validate or obj and obj.object_name,"Cannot find target object: "..target_table)
        if obj and obj.object_name then
            target_table=obj.object_fullname or obj.object_name
            cfg.TARGET_TABLE=obj.target_table
            cfg.object_owner,cfg.object_name=obj.object_owner,obj.object_name
        end
    end

    print("Parameters:")
    print("===========")
    print(table.dump(cfg))

    if self.validate_options then
        self.validate_options(cfg)
    end

    env.checkerr(cfg.SHOW~='OFF' or env.set.get("readonly")=="off",'Operation not allowed in readonly mode.')
    db_loader.importCSVData(db.conn,target_table,cfg.TARGET_FILE,cfg)
end

function loader:unload(target_file,query,options)
    env.checkhelp(query)
    local cfg=self:parse_options(target_file,options)
    local db=self.db
    db:assert_connect()
    local rs
    if type(query)=="userdata" then
        rs=query
    else
        local typ,file=os.exists(query)
        if type=='file' then 
            query=env.read_file(file)
        end
        query=env.COMMAND_SEPS.match(query)
        local sql_type=db.get_command_type(query)
        env.checkerr(sql_type=="SELECT" or sql_type=="WITH","Unload query must be a SELECT statement.")
        rs=db:internal_call(query)
    end
    env.checkerr(type(rs)=="userdata" and rs.isClosed and not rs:isClosed(),tostring(rs).." must be an opened resultset.")
    print("Parameters:")
    print("===========")
    print(table.dump(cfg))
    db_unloader.exportToFile(rs,cfg.TARGET_FILE,cfg);
end

function loader:__onload()
    env.set_command(self,self.load_command,self.load_helps,self.load,true,4)
    env.set_command(self,self.unload_command,self.unload_helps,self.unload,true,4)
end

return loader