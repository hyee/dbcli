local loader=env.class()
local env=env

local db_loader=java.require("com.opencsv.DBLoader",true)
function loader:ctor()
    self.command='load'
    self.db=env.getdb()
    self.helps=[[
        Load data from a CSV file into a table. usage: @@NAME <target_table> <src_csv> [SET options]

        Load options(case-insensitive):
        ===============================
        * show [off|all|ddl|dml]            : Show DDL/DML statement only and do not load CSV file:  ddl=show DDL only, dml=show DML only, all=show both DDL and DML
        * show_ddl|ddl                      : Show DDL only and do not load CSV file
        * show_dml|dml                      : Show DML only and do not load CSV file
        * create|new <off|on>               : Show DDL and create table from CSV (default: off)
        * scan_rows|scanrows|scan <number>  : Used together with show/show_ddl/create, number of rows to scan for column names (default: 200)
        * column_size <auto|actual|maximum> : Used together with show/show_ddl/create, Column size strategy (default: auto)
        * truncate <on|off>                 : Truncate table before loading (default: off)
        * errors <number>                   : Number of errors to allow before stopping (default: -1, unlimited)
        * batch_rows|batchrows <number>     : Number of rows to batch per insert (default: 2048)
        * row_limit|rowlimit|limit <number> : Maximum number of rows to load (default: 0, unlimited)
        * report_mb|report <number>         : Report progress every N MB loaded (default: 8)
        * variable_format|var <?|:>         : Variable format used in DML statement (default: ?)
        * platform auto|<platform>          : Database platform used to generate DDL/DML statement(default: auto)
                                              Avail options: mysql, oracle, pgsql, sqlserver, db2, mssql, postgresql
        * map_column_names|mapcolumnnames   : Map CSV column names to table column names,column mappings are case-insensitive.
          |mapnames (CSV_COL=TABLE_COL,...)   e.g.: map_column_names (ID=OBJECT_ID,NAME=OBJECT_NAME)
        
        CSV format options(case-insensitive):
        =====================================
        * has_header|header <on|off>                                : Whether the first row is a header row (default: on)
        * encoding <charset>                                        : Character encoding of CSV file (default: "")
        * delimiter <chars>                                         : CSV delimiter character (default: ,)
        * enclosure <chars>                                         : CSV enclosure character (default: ")
        * escape <char>                                             : CSV escape character (default: \)
        * unescape_newline|unescape                                 : Whether to unescape string "\n" and "\r" as CRLF for string column (default: off)
        * skip_rows|skiprows|skip <number>                          : Number of rows to skip if CSV rows is not started from the first row (default: 0)
        * skip_columns|skipcols (column1,column2,...)|off|auto      : Columns to be skipped from loading (default: auto)
        
        CSV Timestamp format options:
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


function loader:load(target_table,src_csv,options)
    env.checkhelp(src_csv)
    local typ,file=os.exists(src_csv)
    env.checkerr(typ=="file","Input CSV file %s does not exist.",src_csv)
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

    local cfg={TARGET_TABLE=target_table,CSV_FILE=file}
    local function push(opt,value,upper)
        if type(value)=="string" then 
            value=value:trim()
            if upper~=false then value=value:upper() end
        end
        cfg[opt:upper()]=value
    end

    local names={
        show={"off","all","ddl","dml"},
        create={"off","on"},
        truncate={"off","on"},
        errors={-1},
        batch_rows={2048},
        has_header={"on","off"},
        row_limit={0},
        skip_rows={0},
        skip_columns={"auto"},
        scan_rows={200},
        report_mb={8},
        variable_format={"?",":"},
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

    for n,v in pairs{
        new=names.create,
        show_ddl={"ddl","ddl",name="show"},
        show_dml={"dml","ddl",name="show"},
        ddl={"ddl","ddl",name="show"},
        dml={"dml","ddl",name="show"},
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
                env.checkerr(maps and maps:sub(1,1)=="(" and maps:sub(-1,-1)==")","Invalid option \""..opt:upper().."\" value: "..(maps or "nil"))
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
                else
                    print(fmt)
                end
                push(val.name,fmt,false)
            elseif type(val[1])=="number" then
                local num=next_token()
                env.checkerr(num and tonumber(num),"Invalid option \""..opt:upper().."\" value: "..(num or "nil"))
                push(val.name,tonumber(num))
            else
                local option=next_token()
                if val.maps then
                    if option and val.maps[option:upper()] then
                        push(val.name,option)
                    else
                        if not option or names[option] then
                            push(val.name,val[2])
                        elseif not option then
                            break
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

    local db=self.db
    if db:is_connect() and db.check_obj then
        local obj=db:check_obj(target_table,1)
        if obj then
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
    db_loader.importCSVData(db.conn,target_table,file,cfg)
end

function loader:__onload()
    env.set_command(self,self.command,self.helps,self.load,true,4)
end

return loader