/* [[ Kill Session using APPDBA.KILL_SESSION package.  Usage acnkill <sid> <serial#>
 --[[ ]]--
]] */
BEGIN
appdba.kill_session(:V1,:V2);
END;
/
