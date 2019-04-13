/*[[Show Nls_Database_Parameters]]*/

SELECT parameter,a.VALUE database_value,c.value instance_value,b.value session_value 
from Nls_Database_Parameters a 
full JOIN NLS_SESSION_PARAMETERS b USING(PARAMETER)
full JOIN NLS_INSTANCE_PARAMETERS c USING(PARAMETER)  order by 1