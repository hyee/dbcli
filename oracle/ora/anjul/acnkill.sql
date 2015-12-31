/* [[ Kill Session using APPDBA.KILL_SESSION package.  Usage: @@NAME <sid> <serial#>
 --[[ ]]--
]] */
BEGIN
appdba.kill_session(:V1,:V2);
END;
/
