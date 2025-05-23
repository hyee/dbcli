/*[[Show the messages that background processes (dest) store and fetch and about what they do. Usage: @@NAME [keyword] ]]*/
select * 
from table(gv$(cursor(
    select * from sys.x$messages
    where :V1 is null 
    or    lower(DESCRIPTION) like lower('%&V1%') 
    or    lower(DESCRIPTION) like lower('%&V1%') 
    or    lower(DEST) like lower('%&V1%')
)));