local env=env
local hotkeys={}
function hotkeys.help()
    return [[
        Ctrl+G                       : Cancle command
        Ctrl+C     or Ctrl+D         : Kill the whole command line
        Ctrl+Back  or Shift+Back     : Kill previous word
        Ctrl+Left  or Shift+Left     : Move to previous word
        Ctrl+Right or Shift+Right    : Move to next word
        Ctrl+C     or Ctrl+D or 'Q'  : Abort running command
        Ctrl+L                       : Clear screen
        Ctrl+U                       : Kill all words that before cursor
        Ctrl+K                       : Kill all words that after cursor]]
end

function hotkeys.call(_,_,x)
    env.checkhelp(x)
    print(1)
end


function hotkeys.onload()
    env.set_command(nil,"HOTKEYS",{"Show available hot keys. type '@@NAME' for more information.",hotkeys.help},hotkeys.call,false,2)
end

return hotkeys