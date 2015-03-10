local env=env
local db,grid=env.oracle,env.grid
local cfg=env.set

local ora=env.class(env.scripter)
function ora:ctor()
    self.db=env.oracle
    self.command="ora"
    self.help_title='Run SQL script under the "ora" directory. Usage: ora [<script_name>|-r|-p|-h|-s] [parameters]'
    self.script_dir,self.extend_dirs=env.WORK_DIR.."oracle"..env.PATH_DEL.."ora",{}
end

function ora:validate_accessable(name,options,values)
    local check_flag,expect_name,default,option,expect
    local db=self.db
    
    for i=1,#options do
        option=options[i]
        default=option
        if name=="CHECK_USER" then--check user
            check_flag=3
            expect_name="user"
            if db.props.db_user ~= option and option~="DEFAULT" then default=nil end
            expect=option
        elseif name=="CHECK_ACCESS" then--objects are sep with the / symbol
            check_flag=2
            expect_name="access"
            for obj in option:gmatch("([^/%s]+)") do
                if not db:check_obj(obj) then
                    default=nil
                    expect='the accesses to: '.. option
                    break
                end
            end
        else--check version                                
            local check_ver=option:match('^([%d%.]+)$')
            if check_ver then
                check_flag=1
                expect_name="database version"
                local db_version=self:format_version(db.props.db_version or "8.0.0.0.0")
                if db_version<self:format_version(check_ver) then default=nil end
                expect=option
            end
        end
        if default~=nil then break end
    end

    if not default then
        env.raise("This command doesn't support current %s %s, expected as %s!",
            expect_name,
            check_flag==1 and db.props.db_version 
                or check_flag==2 and "rights"
                or check_flag==3 and db.props.db_user,
            expect) 
    end

    return default
end

return ora.new()