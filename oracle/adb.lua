local db,var=env.getdb(),env.var
local current_credential=''

local adb=env.class(db.C.ora)
function adb:ctor()
    self.db=env.getdb()
    self.command={"adb"}
    self.help_title='Run SQL script relative to Oracle Autonomous Database(ADW/ATP). User must have the access to DBMS_CLOUD package'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."adb",{}
    env.set.init('credential','',adb.set_credential,'oracle.cloud','Set session default credential that defined in dba_credentials','*')
    env.event.snoop("AFTER_ORACLE_CONNECT",adb.on_login,nil,99)
    env.event.snoop("BEFORE_DB_EXEC",adb.set_param,nil,99)
    env.event.snoop("BEFORE_DB_CONNECT",function() current_credential='';env.set.force_set('credential','') end,nil,99)
end


function adb.set_credential(name,value)
    if current_credential~=value then
        db:assert_connect()
        if value~='' then 
            value=db:get_value([[select max(credential_name) from user_credentials where upper(credential_name)=upper(:1)]],{value})
            if value=='' then
                return print('Cannot find the target credential in view user_credentials.')
            end
        end

        db.last_login_account.credential=value~='' and value or nil
        env.login.capture(db,nil,db.last_login_account)
        print('Setting default credential as "'..value..'".')
    end
    current_credential=value
    return value
end

function adb.set_param(db) 
    if var.outputs['CREDENTIAL']==nil then var.setInputs('CREDENTIAL',current_credential) end;
end 

function adb.on_login(oracle,url,props)
    if props.credential then
        current_credential=props.credential
        env.set.force_set('credential',current_credential)
        print('Setting default credential as "'..current_credential..'".')
    end
end

function adb:run_sql(sql,args,cmds,files)
    env.checkerr(db:check_access('DBMS_CLOUD',true),"You must have the execution privilege on package DBMS_CLOUD");
    
    return self.super.run_sql(self,sql,args,cmds,files)
end


return adb.new()