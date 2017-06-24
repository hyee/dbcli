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

function hotkeys.call(_,_,x)
    local maps=console:getKeyMap("-L");
    local hdl=env.grid.new()
    hdl:add{"Key","*","Description"}
    for key,desc in maps:gmatch('("[^\n\r]+") +([^\n\r]+)[\n\r]') do
        key=key:gsub('"(.-)"',' $HEADCOLOR$%1$NOR$ ')
        hdl:add({key,' ',desc})
    end
    hdl:sort(3)
    hdl:print()
end


function hotkeys.onload()
    env.set_command(nil,"KEYMAP",{"Show available hot keys. type '@@NAME' for more information.",hotkeys.help},hotkeys.call,false,2)
end

return hotkeys