local db,var=env.getdb(),env.var
local credential,bucket=''

local adb=env.class(db.C.ora)
function adb:ctor()
    self.db=env.getdb()
    self.command={"adb"}
    self.help_title='Run SQL script relative to Oracle Autonomous Database(ADW/ATP).'
    self.script_dir,self.extend_dirs=self.db.ROOT_PATH.."adb",{}
    env.set.init('credential','',adb.set_credential,'oracle.cloud','Set account default credential that defined in user_credentials','*')
    env.set.init('bucket','',adb.set_credential,'oracle.cloud','Set account default Object Storage bucket','*')
    
    env.event.snoop("AFTER_ORACLE_CONNECT",adb.on_login,nil,99)
    env.event.snoop("BEFORE_DB_EXEC",adb.set_param,nil,99)
    env.event.snoop("BEFORE_DB_CONNECT",
        function()
            credential,bucket='','';
            env.set.force_set('credential','')
            env.set.force_set('bucket','') 
        end,nil,99)
end


function adb.set_credential(name,value)
    if (name=='CREDENTIAL' and credential or bucket)~=value then
        db:assert_connect()
        if value~='' and name=='CREDENTIAL' then 
            value=db:get_value([[select max(credential_name) from user_credentials where upper(credential_name)=upper(:1) and enabled='TRUE']],{value})
            if value=='' then
                return print('Cannot find the enabled credential in view user_credentials.')
            end
        else
            value=value:trim('/')
        end
        if name=='CREDENTIAL' then
            db.last_login_account.credential=value~='' and value or nil
        else
            db.last_login_account.objbucket=value~='' and value or nil
        end
        env.login.capture(db,nil,db.last_login_account)
        print('Setting default '..name:lower()..' as "'..value..'".')
    end
    if name=='CREDENTIAL' then
        credential=value
    else
        bucket=value
    end
    return value
end

function adb.set_param(db) 
    if var.outputs['CREDENTIAL']==nil then var.setInputs('CREDENTIAL',credential) end;
    if var.outputs['OBJBUCKET']==nil then var.setInputs('OBJBUCKET',bucket) end;
end 

function adb.on_login(oracle,url,props)
    if props.credential then
        credential=props.credential
        env.set.force_set('credential',credential)
        print('Default credential as "'..credential..'".')
    end

    if props.objbucket then
        bucket=props.objbucket
        env.set.force_set('bucket',bucket)
        print('Default bucket as "'..bucket..'".')
    end
end

return adb.new()