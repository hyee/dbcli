local env=env
local hotkeys={}
function hotkeys.help()

    return [[
        Ctrl+G                       : Cancle command
        Ctrl+D                       : Delete char
        Alt+BackSpace                : Kill previous word
        Alt+Left                     : Move to previous word
        Alt+Right                    : Move to next word
        Shift+Left                   : Scroll left
        Shift+Right                  : Scroll right
        Ctrl+C  or 'Q'               : Abort running command
        Ctrl+L                      * : Clear screen
        Ctrl+U                       : Kill all words that before cursor
        Ctrl+K                       : Kill all words that after cursor]]
end

function hotkeys.call(event,_,x)
    local maps=console:getKeyMap("-L");
    local keys,keys1={},{}
    local matched=false
    for key,desc in maps:gmatch('("[^\n\r]+") +([^\n\r]+)[\n\r]') do
        if desc==event then matched=true end
        keys[key]=desc
        if key:find('^',1,true) then keys1[#keys1+1]={key,desc} end
    end
    table.sort(keys1,function(a,b) return a[2]<b[2] end)

    if event then
        env.checkerr(matched,"No such event: "..event)
        console:setKeyCode(event,nil)
        return
    end
    local hdl=env.grid.new()
    hdl:add{"Key","*","Description",'|',"Key","*","Description"}
    local row
    for _,keys in ipairs(keys1) do
        local key,desc=table.unpack(keys)
        key=key:gsub('"(.-)"',function(s) return ' $HEADCOLOR$'..(console:translateKey(s))..'$NOR$ ' end)
        if not row then 
            row={key,' ',desc} 
        else
            row[#row+1],row[#row+2],row[#row+3],row[#row+4]='|',key,' ',desc
            hdl:add(row)
            row=nil
        end
    end
    if row then hdl:add(row) end
    hdl:print()
    print("\n*Tips: input 'keymap <description> to manually define the keymap.")
end


function hotkeys.onload()
    env.set_command(nil,"KEYMAP",{"Show available hot keys. type '@@NAME' for more information.",hotkeys.help},hotkeys.call,false,2)
end

return hotkeys