local env=env
local db,grid=env.db2,env.grid
local cfg=env.set

local sql=env.class(env.scripter)
function sql:ctor()
    self.db=env.db2
    self.command="sql"
    self.help_title='Run SQL script under the "sql" directory. Usage: sql [<script_name>|-r|-p|-h|-s] [parameters]'
    self.script_dir,self.extend_dirs=env.WORK_DIR.."db2"..env.PATH_DEL.."sql",{}
end

local function format_version(version)
    return version:gsub("(%d+)",function(s) return s:len()<3 and string.rep('0',3-s:len())..s or s end)
end

return sql.new()