local env=env
local db,grid=env.getdb(),env.grid
local cfg=env.set

local ora=env.class(env.scripter)
function ora:ctor()
    self.db=env.getdb()
    self.command="ora"
    self.help_title='Run SQL script under the "ora" directory. '
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."ora",{}
end

function ora:validate_accessable(name,options,values)
    local check_flag,expect_name,default,option,expect
    local db=self.db
    local check_container
    for i=1,#options do
        option=options[i]
        default=option
        if name:find("CHECK_USER",1,true)==1 then--check user
            check_flag=3
            expect_name="user"
            default=nil
            for role in option:gmatch("([^/]+)") do
                role=role:upper()
                if role:upper()=="DEFAULT" or db.props.privs[role] then
                    default=option
                    break
                end
            end
            expect=option
        elseif name:find("CHECK_ACCESS",1,true)==1 then--objects are sep with the / symbol
            local ispdb=(tonumber(db.props.container_id) or 0)>1
            for obj in option:gmatch("([^/%s]+)") do
                if obj:upper()=='CDB' then
                    if (db.props.container_id or 2)>1 then
                        check_flag=4
                        expect_name='non-CDB'
                        expect='CDB mode'
                        default=nil
                        break
                    else
                        check_container=true
                    end
                elseif obj:upper()=='PDB' then
                    if not ispdb then
                        check_flag=4
                        expect_name='non-PDB'
                        expect='PDB mode'
                        default=nil
                        break
                    else
                        check_container=true
                    end
                elseif obj:upper()=='AWRPDB' then
                    local rtn,c=nil,0
                    if ispdb then
                        rtn,c=pcall(db.get_value,db,'select /*BYPASS_DBCLI_REWRITE*/ /*+INDEX(A)*/ count(1) from awr_pdb_snapshot a where dbid=&dbid and rownum<2')
                    end
                    if c==0 then
                        check_flag=4
                        expect_name='non-PDB'
                        expect='PDB mode'
                        default=nil
                        break
                    else
                        check_container=true
                    end
                elseif obj:upper()~="DEFAULT" then
                    local is_accessed=db:check_access(obj,1)
                    if is_accessed and check_container then --check whether target view has record
                        local rtn,c=pcall(db.get_rows,db,'select /*INTERNAL_DBCLI_CMD*/ 1 from '..obj..' where rownum<2')
                        is_accessed=#c>1 
                    end
                    if not is_accessed then
                        default=nil
                        check_flag=2
                        expect_name="access"
                        expect='the accesses to: '.. option
                        break
                    end
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

return ora.new()