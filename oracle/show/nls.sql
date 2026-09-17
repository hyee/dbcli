/*[[Show NLS_DATABASE_PARAMETERS together with the instance and session values.]]*/

SELECT parameter, a.value database_value, c.value instance_value, b.value session_value
FROM   nls_database_parameters a
FULL   JOIN nls_session_parameters b USING (parameter)
FULL   JOIN nls_instance_parameters c USING (parameter)
ORDER  BY 1