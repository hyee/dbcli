/*****************************************************************************************
   
    SQLD360 - Enkitec's Oracle SQL 360-degree View
    Copyright (C) 2015  Mauro Pagano

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

*****************************************************************************************/

-- The script creates a driver based on the rows inside the plan table and the according flags+days stored in column options 
-- the flags right now are 3 "000" plus 3 chars for the number of days
-- the first "bit" is for diagnostics_pack
-- the second "bit" is for tuning_pack
-- the third "bit" is for TCB
-- the next 3 chars are used for number of days
-- so ie. if customer has no license, wants TCB and 31 days then it would be 001031

SET SERVEROUT ON FEED OFF DEF OFF TERM OFF TIMI OFF
SPO sqld360_driver.sql
DECLARE 
  num_sqlids NUMBER;
  license    VARCHAR2(1);
  num_days   NUMBER;
  PROCEDURE put (p_line IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put;
BEGIN

  put('PRO Please Wait ...');

  SELECT count(*)
    INTO num_sqlids
    FROM plan_table
   WHERE statement_id = 'SQLD360_SQLID';

  IF num_sqlids = 0 THEN
    -- this is a standalone execution, just proceed without values
    -- for standalone execution we want to collect TCB
    put('DEF skip_tcb=''''');
	put('DEF from_edb360=''''');
    put('@@sql/sqld360_0a_main.sql');
	put('HOS unzip -l &&sqld360_main_filename._&&sqld360_file_time.');
  ELSE
	put('DEF from_edb360=''--''');
    -- this execution is from edb360, call SQLd360 several times passing the appropriare flag	
    FOR i IN (SELECT operation, options FROM plan_table WHERE statement_id = 'SQLD360_SQLID') LOOP

       -- check if need to run TCB 
	   IF SUBSTR(i.options,3,1) = 0 THEN
         put('DEF skip_tcb=''--''');
	   ELSE
         put('DEF skip_tcb=''''');
	   END IF;	

	   -- check the license to use
	   IF SUBSTR(i.options,2,1) = 1 THEN
		  -- if T is enabled then D is enabled too
		  license := 'T';
	   ELSIF SUBSTR (i.options,1,1) = 1 THEN
		  -- no tuning but diagnostics
          license := 'D';
	   ELSE
		  -- no license
		  license := 'N';
	   END IF;

       num_days := TO_NUMBER(TRIM(SUBSTR(i.options,4,3)));

       put('@@sql/sqld360_0a_main.sql '||i.operation||' '||license||' '||num_days);
  	   put('HOS unzip -l &&sqld360_main_filename._&&sqld360_file_time.');

	END LOOP;	
      
  END IF;

END;
/
SPO OFF 
SET DEF ON TERM ON
@sqld360_driver.sql
HOS rm sqld360_driver.sql
