local env=env
local db,grid=env.getdb(),env.grid
local cfg=env.set

local sql=env.class(env.scripter)
function sql:ctor()
    self.db=env.getdb()
    self.command={"pg","sql"}
    self.help_title='Run SQL script under the "sql" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."sql",{}
end

function sql:validate_accessable(name,options,values)
    local check_flag,expect_name,default,option,expect
    local db=self.db
    local check_container
    for i=1,#options do
        option=options[i]
        default=option

        if name:upper():find("CHECK_USER",1,true)==1 then--check user
            check_flag=3
            expect_name="user"
            default=nil
            for role in option:gmatch("([^/]+)") do
                if role=="DEFAULT" or db.props.privs[role] or db.props[role] or db.props[role:lower()] then
                    default=option
                    break
                end
            end
            expect=option
        elseif name:upper():find("CHECK_ACCESS",1,true)==1 or name:upper():find("CHECK_FUNC",1,true)==1 then--objects are sep with the / symbol
            local func=name:upper():find("CHECK_ACCESS",1,true)==1 and 'check_access' or 'check_function'
            local info=name:upper():find("CHECK_ACCESS",1,true)==1 and 'the accesses to: ' or 'the function'
            for obj in option:gmatch("([^/%s]+)") do
                if obj:upper()~="DEFAULT" then
                    local is_accessed=db[func](db,obj)
                    if not is_accessed then
                        default=nil
                        check_flag=2
                        break
                    end
                end
            end
            expect_name="access"
            expect=info .. option
        else--check version
            local check_ver=option:match('^([%d%.]+)$')
            if check_ver then
                check_flag=1
                expect_name="database version"
                local db_version=self:format_version(db.props.db_version or "5.0.0")
                if db_version<self:format_version(check_ver) then default=nil end
                expect=option
            end
        end
        if default~=nil then break end
    end

    if not default and expect then
        env.raise('The command doesn\'t support current %s %s, expected %s.',
            expect_name,
            check_flag==1 and (db.props.db_version or 'unknown')
                or check_flag==2 and "rights"
                or check_flag==3 and (db.props.db_user or 'unknown')
                or check_flag==4 and 'mode',
            expect)
    end
    return default
end


return sql.new()