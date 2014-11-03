/*[[Show nls parameters]]*/

SELECT parameter,a.VALUE database_value,b.value session_value from Nls_Database_Parameters a full JOIN NLS_SESSION_PARAMETERS b USING(PARAMETER) order by 1