local env=env
local hotkeys={}
local map={
    ["\8"]="BACKSPACE",
    ["^%?"]="BACKSPACE",
    ["^H"]="BACKSPACE",
    ["^[^H"]="ALT-BACKSPACE",
    ["^_"]="ALT-BACKSPACE",
    ["\9"]="TAB",
    ["^[[2~"]="INSERT",
    ["^[[3~"]="DEL",
    ["^[[5~"]="PGUP",
    ["^[[6~"]="PGON",
    ["^[[H"]="HOME",
    ["^[[1;%dH"]="HOME",
    ["^[[4~"]="END",
    ["^[[1;%dF"]="END",
    ["^[OP"]="F1",
    ["^[[1;%dP"]="F1",
    ["^[OQ"]="F2",
    ["^[[1;%dQ"]="F1",
    ["^[OR"]="F3",
    ["^[[1;%dR"]="F1",
    ["^[OS"]="F4",
    ["^[[1;%dS"]="F1",
    ["^[[15~"]="F5",
    ["^[[15;%d~"]="F5",
    ["^[[17~"]="F6",
    ["^[[17;%d~"]="F6",
    ["^[[18~"]="F7",
    ["^[[18;%d~"]="F7",
    ["^[[19~"]="F8",
    ["^[[19;%d~"]="F8",
    ["^[[20~"]="F9",
    ["^[[20;%d~"]="F9",
    ["^[[21~"]="F10",
    ["^[[21;%d~"]="F10",
    ["^[[23~"]="F11",
    ["^[[23;%d~"]="F11",
    ["^[[24~"]="F12",
    ["^[[24;%d~"]="F12",
    ["^[[D"]="LEFT",
    ["^[OD"]="LEFT",
    ["^[[1;%dD"]="LEFT",
    ["^[[C"]="RIGHT",
    ["^[OC"]="RIGHT",
    ["^[[1;%dC"]="RIGHT",
    ["^[[A"]="UP",
    ["^[OA"]="UP",
    ["^[[1;%dA"]="UP",
    ["^[[B"]="DOWN",
    ["^[[1;%dB"]="DOWN",
    ["^[OB"]="DOWN"}
function hotkeys.call(event,_,x)
    local maps=console:getKeyMap("-L");
    local keys,keys1={},{}
    local matched=false
    for key,desc in maps:gmatch('("[^\n\r]+") +([^\n\r]+)[\n\r]') do
        if not desc:find('LineReaderImpl',1,true) then
            if desc==event then matched=true end
            keys[key]=desc
            if key:find('^',1,true) then keys1[#keys1+1]={key,desc} end
        end
    end
    table.sort(keys1,function(a,b) return a[2]<b[2] end)

    if event then
        env.checkerr(matched,"No such event: "..event)
        console:setKeyCode(event,nil)
        return
    end
    local hdl=env.grid.new()
    hdl:add{"Key","*","Description",'Code','|',"Key","*","Description",'Code'}
    local row
    for _,keys in ipairs(keys1) do
        local key,desc,found=table.unpack(keys)
        local code=key:gsub('"(.-)"',' %1 ')
        key=key:gsub('"(.-)"',function(s)
            local s1=s
            for k,v in pairs(map) do
                k=k:gsub("([%^%[%]])","%%%1"):gsub("%%d","(%1)")
                local p
                if k:find('%d') then
                    local idx=tonumber(s:match(k))
                    if idx then
                        idx=idx-1
                        local p=" + "
                        if bit.band(idx,4)>0 then p=p.."CTRL-" end
                        if bit.band(idx,2)>0 then p=p.."ALT-" end
                        if bit.band(idx,1)>0 then p=p.."SHIFT-" end
                        p=p..v.." + "
                        s=s:gsub(k,p)
                    end
                else
                    s=s:gsub(k,v)
                end
            end
            s=s:gsub("%^%[%^(.)","+ CTRL-ALT-%1"):gsub('%^%[(.)',' + ALT-%1'):gsub('%^(.)',' + CTRL-%1'):gsub('^%s*%+ ',''):gsub(' %+%s*$','')
            return ' $HEADCOLOR$'..s..'$NOR$ ' 
        end)
        if not row then 
            row={key,' ',desc,code} 
        else
            row[#row+1],row[#row+2],row[#row+3],row[#row+4],row[#row+5]='|',key,' ',desc,code
            hdl:add(row)
            row=nil
        end
    end
    if row then hdl:add(row) end
    hdl:print()
    print("\n*Tips: input 'keymap <description> to manually define the keymap.")
end


function hotkeys.onload()
    env.set_command(nil,"KEYMAP",{"Show available hot keys. type '@@NAME' for more information."},hotkeys.call,false,2)
end

return hotkeys