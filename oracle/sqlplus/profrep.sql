Rem  Copyright (c) Oracle Corporation 1998, 1999. All Rights Reserved.
Rem
Rem    NAME
Rem      profrep.sql
Rem
Rem    DESCRIPTION
Rem      PL/SQL Profiler reporting utilities
Rem
Rem    NOTES
Rem      The reporting procedures expect server output to be set on
Rem      Some of the rollup functions commit the transaction.
Rem
 
-- First create the views used in the reporting package
--
create or replace view plsql_profiler_grand_total as
  select sum(total_time) as grand_total from plsql_profiler_units;
 
create or replace view plsql_profiler_units_cross_run as
  select unit_owner, unit_name, unit_type, sum(total_time) as total_time
    from plsql_profiler_units group by unit_owner, unit_name, unit_type;
 
create or replace view plsql_profiler_lines_cross_run as
  select p1.unit_owner as unit_owner, p1.unit_name as unit_name, 
    p1.unit_type as unit_type, 
    p2.line# as line#,
    sum(p2.total_occur) as total_occur,
    sum(p2.total_time) as total_time, 
    min(p2.min_time) as min_time,
    max(p2.max_time) as max_time
  from plsql_profiler_units p1, plsql_profiler_data p2
  where p1.runid=p2.runid and p1.unit_number = p2.unit_number
  group by p1.unit_owner, p1.unit_name, p1.unit_type, p2.line#;
 
create or replace view plsql_profiler_notexec_lines as
  select owner, name, type, line, text, total_occur
  from all_source t1, plsql_profiler_lines_cross_run t2
  where t2.total_occur = 0 and t2.unit_owner = owner
    and t2.unit_name = name and t2.unit_type = type and t2.line# = line
  order by line asc;
 
create or replace package prof_report_utilities
  authid current_user is
 
  -- Routines to roll up profile information from line level to unit level
  --
  procedure rollup_unit(run_number IN number, unit IN number);
  procedure rollup_run(run_number IN number);
  procedure rollup_all_runs;
 
  -- Routines to print a report, treating each run separately
  --
  procedure print_unit(run_number IN number, unit IN number);
  procedure print_run(run_number IN number);
  procedure print_detailed_report;
 
  -- Routine to print a single report including information from each run
  --
  procedure print_summarized_report;
 
  -- Set size of window for reports
  procedure set_window_size(window_size IN pls_integer);
 
end prof_report_utilities;
/
show errors;
 
create or replace
package body prof_report_utilities is
 
  -- the reports print 'window' lines of source around lines with profiler
  -- data, otherwise skipping lines with no data. This is useful when
  -- viewing data for units with sparse profiler data.
  --
  window pls_integer := 10;
  last_line_printed number := 999999999;
 
  cursor c2(run number, unit number,
            owner_name varchar2, unit_name varchar2, unit_type varchar2) is
    select line, text, total_occur, total_time, min_time, max_time
      from all_source, plsql_profiler_data
      where runid (+) = run and unit_number (+) = unit
        and owner = owner_name and name = unit_name and type = unit_type
        and plsql_profiler_data.line# (+) = line
      order by line asc;
 
  -- c2tab contains the window of lines around any line with interesting
  -- data.
  type c2tab_t is table of c2%rowtype index by binary_integer;
  c2tab    c2tab_t;
  -- index into the window where previous row was inserted
  prev_row pls_integer := 0;
 
  procedure report_exception(which IN varchar2, reraised IN boolean) is
  begin
    dbms_output.new_line();
    dbms_output.new_line();
    dbms_output.put('======================================');
    dbms_output.put_line('======================================');
    dbms_output.put('Exception Number:  ');
    dbms_output.put(sqlcode);
    dbms_output.put(' raised in routine ' || which );
    if (reraised)
    then
      dbms_output.put(' (Will be reraised)');
    end if;
    dbms_output.new_line();
    dbms_output.put('======================================');
    dbms_output.put_line('======================================');
  end;
 
  -- compute the total time spent executing this unit - the sum of the
  -- time spent executing lines in this unit (for this run)
  --
  procedure rollup_unit(run_number IN number, unit IN number) is
  begin
        dbms_profiler.rollup_unit(run_number, unit);
  exception
    when others then
      report_exception('Rollup_Unit', true);
      raise;                    
  end rollup_unit;
 
  -- rollup all units for the given run
  --
  procedure rollup_run(run_number IN number) is
  begin
        dbms_profiler.rollup_run(run_number);
  exception
    when others then
      report_exception('Rollup_Run', true);
      raise;                    
  end rollup_run;
 
  procedure rollup_all_runs is 
    cursor crunid is 
      select runid from plsql_profiler_runs order by runid asc;
  begin
    for runidrec in crunid loop
      dbms_profiler.rollup_run(runidrec.runid);
    end loop crunid;
  end rollup_all_runs;
 
  --
  -- Reporting functions
  --
 
  -- Format and print information on a unit
  --
  procedure print_unit_header(run_number IN number, unit IN number) is
    cursor cuhdr(run_number number, unit number) is
      select * from plsql_profiler_units 
        where runid = run_number and unit_number = unit;
    unit_row cuhdr%rowtype;
  begin
    -- fetch data for the given unit
    open cuhdr(run_number, unit);
    fetch cuhdr into unit_row;
    close cuhdr;
 
    -- format and print the data
    dbms_output.put('Unit #');
    dbms_output.put(unit_row.unit_number);
    dbms_output.put(': ');
    dbms_output.put(unit_row.unit_owner || '.' || unit_row.unit_name);
    dbms_output.put(' - Total time: ');
    dbms_output.put(to_char(unit_row.total_time/1000000000, '99999.99'));
    dbms_output.put_line(' seconds');
  end print_unit_header;
 
  -- Format and print information on a run
  --
  procedure print_run_header(run_number IN number) is
    cursor crun(run_number number) is 
      select * from plsql_profiler_runs where runid = run_number;
    runidrec crun%rowtype;
  begin
    open crun(run_number);
    fetch crun into runidrec;
    close crun;
 
    dbms_output.new_line();
    dbms_output.new_line();
    dbms_output.put('===========================');
    dbms_output.put('Results for run #');
    dbms_output.put(runidrec.runid);
    dbms_output.put(' made on ');
    dbms_output.put(to_char(runidrec.run_date, 'DD-MON-YY HH24:MI:SS'));
    dbms_output.put_line(' =========================');
    if (runidrec.run_comment is not null) then
      dbms_output.put(' (');
      dbms_output.put(runidrec.run_comment);
      dbms_output.put(') ');
    end if;
    dbms_output.put('Run total time: ');
    dbms_output.put(to_char(runidrec.run_total_time/1000000000, '99999.99'));
    dbms_output.put_line(' seconds');
    if (runidrec.run_system_info is not null) then
      dbms_output.put_line(runidrec.run_system_info);
    end if;
  end print_run_header;
     
  -- 
  -- Routines for formatting and printing profiler data
  --
  
  -- Format and print one line of data and source
  --
  procedure print_line(line number, lcount number,
                       running_total number, source varchar2) is
    outline    varchar2(200);         -- temp buffer to hold output
    cline      varchar2(40);          -- number of times this line was executed
    total_time varchar2(40);          -- total time executing this line
    ave_time   varchar2(40);          -- average time for this line
    ave_nano   number;
  begin
    outline := to_char(line, '99G999');
 
    -- format and store away the count and running total
    if (lcount is not null) then
      cline := to_char(lcount, '99G999G999');
    end if;
 
    if (running_total is not null) then
      total_time := substr(to_char(running_total/1000000000), 1, 9);
    end if;
 
    -- compute average time executing this line and stash it away
    if (lcount > 0) then
      ave_nano := running_total/lcount;
      ave_time := substr(to_char(ave_nano/1000000000), 1, 9);
    end if;
 
    -- now put together all the data, the source line and output it
    --
    outline := outline || ' ' || cline || '   ' ||
               total_time || '  ' || ave_time || ' ';
 
    if source is not null then 
      outline := rpad(outline, 55) || substr(source, 1, (length(source) - 1));
    end if;
 
    dbms_output.put_line(outline);
  end print_line;
 
  -- insert a c2 row into the window
  --
  procedure insert_into_window(c2row c2%rowtype) is
    next_row pls_integer;
  begin
    next_row := mod((prev_row + 1), window);
    c2tab(next_row) := c2row;
    prev_row := next_row;
  end insert_into_window;
 
  -- clear out the window (for reuse later)
  --
  procedure clear_window is
    empty_tab c2tab_t;
  begin
    -- throw away table
    c2tab := empty_tab;
    prev_row := 0;
  end clear_window;
 
  -- print the window and throw it away
  --
  procedure print_window(start_separator IN boolean) is
    next_row  pls_integer;
    iter      pls_integer;
    c2row     c2%rowtype;
    first_line boolean := true;
    ct        number := c2tab.count;
  begin
 
    if (window <= 0) then
      return;
    end if;
 
    -- compute first row
    next_row := mod((prev_row + 1), window);
 
    -- Detect the case where the window hasn't wrapped around yet
    if (not c2tab.exists(next_row)) then
      next_row := c2tab.next(next_row);
      if (next_row is NULL) then 
        next_row := c2tab.first; 
      end if; 
    end if;
 
    for iter in 1..window loop
      exit when (ct <= 0);
 
      if (c2tab.exists(next_row)) then
        c2row := c2tab(next_row);
        if (first_line and (last_line_printed < c2row.line-1)) then
          dbms_output.put_line('.');
          dbms_output.put_line('.');
          dbms_output.put_line('.');
        end if;
        first_line := false;
        print_line(c2row.line, c2row.total_occur,
                   c2row.total_time, c2row.text);
        last_line_printed := c2row.line;
        ct := ct - 1;
      end if;
      next_row := mod((next_row + 1), window);
    end loop;
 
    if (not start_separator) then
      last_line_printed := 999999999;
    end if;
    clear_window;
  end print_window;
  
  procedure print_unit(run_number number, unit number) is
    cursor cuhdr(run number, unit number) is
      select * from plsql_profiler_units
        where runid = run and unit_number = unit;
 
    unit_row    cuhdr%rowtype;
    joined_row  c2%rowtype;
    lcount      number;
 
    -- print a trailing window after the last interesting line
    print_trailing_window boolean := false;
    trail_count pls_integer := 0;
 
  begin
    dbms_profiler.rollup_unit(run_number, unit);
 
    -- fetch unit name and type information
    open cuhdr(run_number, unit);
    fetch cuhdr into unit_row;
    close cuhdr;
 
    -- If there was an error previously, cursor "c2" might be open
    -- Close it, and ignore the error if it already was
    --
    begin
      close c2;
    exception
      when others then
        null;
    end;
    
    open c2(run_number, unit,
            unit_row.unit_owner, unit_row.unit_name, unit_row.unit_type);
    loop
      fetch c2 into joined_row;
      exit when c2%notfound;
      lcount := joined_row.total_occur;
 
      -- if there is interesting data at this line, print its prefix window
      -- and the data itself; else stash away this line c2tab - it may get
      -- printed as part of another line's window
      if (lcount is not null and lcount <> 0) then
        print_window (start_separator => false);
        print_line(joined_row.line, joined_row.total_occur,
                   joined_row.total_time, joined_row.text);
        print_trailing_window := true;
        trail_count := 0;
      else
        insert_into_window(joined_row);
        -- if we are now accumulating rows after a row with data, increment
        -- count of rows accumulated since last interesting row. if we have
        -- accumulated a window full of data, print it out.
        if (print_trailing_window) then
          trail_count := trail_count + 1;
          if (trail_count = window) then
            print_window(start_separator => true);
            print_trailing_window := false;
          end if;
        end if;
      end if;
    end loop;
    close c2;
    -- if the window isn't empty, print it out.
    if (print_trailing_window) then
      print_window(start_separator => false);
      print_trailing_window := false;
    end if;
    clear_window;
  exception
    when others then
      report_exception('Print_Unit', false);
  end print_unit;
 
  procedure print_run(run_number number) is
    cursor cunits(run_number number) is
      select unit_number from plsql_profiler_units 
        where runid = run_number order by unit_number asc;
  begin
    print_run_header(run_number);
    dbms_profiler.rollup_run(run_number);
 
    for unitrec in cunits(run_number) loop
      print_unit_header(run_number, unitrec.unit_number);
      print_unit(run_number, unitrec.unit_number);
    end loop;
  exception
    when others then
      report_exception('Print_Run', false);
  end print_run;
 
  procedure print_detailed_report is
    cursor crunid is 
      select runid from plsql_profiler_runs order by runid asc;
  begin
    dbms_output.enable(999999);
 
    dbms_output.put('=================================');
    dbms_output.put('trace info'); 
    dbms_output.put_line('=================================');
   
    rollup_all_runs();
 
    for runidrec in crunid loop
      print_run(runidrec.runid);
    end loop crunid;
 
    dbms_output.new_line;
    dbms_output.put('======================================');
    dbms_output.put_line('======================================');
  exception 
    when others then
      report_exception('Print_Detailed_Report', false);
  end print_detailed_report;
 
  procedure print_summarized_unit(owner_name varchar2,
                                  unit_name varchar2, unit_type  varchar2) is
    cursor c3(uowner varchar2, uname varchar2, utype varchar2) is
      select line, text, total_occur, total_time, min_time, max_time
        from all_source t1, plsql_profiler_lines_cross_run t2
        where owner = uowner and name = uname and type = utype
           and t2.unit_owner (+) = uowner and t2.unit_name (+) = uname
           and t2.unit_type (+) = utype and t2.line# (+) = line
        order by line asc;
 
    datarec c3%rowtype;
    lcount  number;
 
    -- print a trailing window after the last interesting line
    print_trailing_window boolean := false;
    trail_count pls_integer := 0;
  begin
    open c3(owner_name, unit_name, unit_type);
    loop
      fetch c3 into datarec;
      exit when c3%notfound;
      lcount := datarec.total_occur;
 
      if (lcount is not null and lcount <> 0) then
        print_window (start_separator => false);
        print_line(datarec.line,
                   datarec.total_occur,
                   datarec.total_time,
                   datarec.text);
        print_trailing_window := true;
        trail_count := 0;
      else
        insert_into_window(datarec);
        -- if we are now accumulating rows after a row with data, increment
        -- count of rows accumulated since last interesting row. if we have
        -- accumulated a window full of data, print it out.
        if (print_trailing_window) then
          trail_count := trail_count + 1;
          if (trail_count = window) then
            print_window(start_separator => true);
            print_trailing_window := false;
          end if;
        end if;
      end if;
    end loop;
    close c3;
    -- if the window isn't empty, print it out.
    if (print_trailing_window) then
      print_window(start_separator => false);
      print_trailing_window := false;
    end if;
    clear_window;
  exception
    when others then
      report_exception('Print_Summarized_Unit', false);
  end print_summarized_unit;
 
  procedure print_summarized_report is
    cursor cunits is
      select unit_owner, unit_name, unit_type
      from plsql_profiler_units_cross_run
      order by unit_owner, unit_name asc;
  begin
    rollup_all_runs();
    dbms_output.enable(9999999);
 
    dbms_output.put('================== Profiler report - all runs rolled up');
    dbms_output.put_line(' ===================');
 
    for unitrec in cunits loop
      dbms_output.put('Unit ');
      dbms_output.put(unitrec.unit_owner);
      dbms_output.put('.');
      dbms_output.put(unitrec.unit_name);
      dbms_output.put_line(':');
      print_summarized_unit(unitrec.unit_owner,
                            unitrec.unit_name, unitrec.unit_type);  
    end loop;
 
    dbms_output.new_line;
    dbms_output.put('======================================');
    dbms_output.put_line('======================================');
  exception 
    when others then
      report_exception('Print_Summarized_Report', false);
  end print_summarized_report;
 
  -- Set size of window for reports
  procedure set_window_size(window_size IN pls_integer) is
  begin
    if (window_size < 0) then
      window := 999999999;
    else
      window := window_size;
    end if;
  end set_window_size;
 
end prof_report_utilities;
/
show errors;
 

--file_name: profsum.sql
set echo off
set linesize 5000
set trimspool on
set serveroutput on
set termout off
column owner format a11
column unit_name format a14
column text format a21 word_wrapped
column runid format 999999
column secs format 99999.99
column hsecs format 99999.99
column grand_total format 9999.99
column run_comment format a30 word_wrapped
column line# format 99999
column pct format 9999.9
column unit_owner format a11
spool profsum.out
--Clean out rollup results, and recreate --
update plsql_profiler_units set total_time = 0;
execute prof_report_utilities.rollup_all_runs;
prompt =
prompt =
prompt ====================
prompt total time
select grand_total/1000000000 as grand_total
from plsql_profiler_grand_total;
prompt =
prompt =
prompt ====================
prompt total time spent on each run
select runid,
       substr(run_comment,1, 30) as run_comment,
       run_total_time/1000000000 as secs
from (select a.runid, sum(a.total_time) run_total_time, b.run_comment
          from plsql_profiler_units a, plsql_profiler_runs b
         where a.runid = b.runid group by a.runid, b.run_comment )
where run_total_time > 0
order by runid asc;
 
prompt =
prompt =
prompt ====================
prompt percentage of time in each module, for each run separately
select p1.runid,
       substr(p2.run_comment, 1, 20) as run_comment,
       p1.unit_owner,
       decode(p1.unit_name, '', '<anonymous>',
                    substr(p1.unit_name,1, 20)) as unit_name,
       p1.total_time/1000000000 as secs,
       TO_CHAR(100*p1.total_time/p2.run_total_time, '999.9') as percentage
from plsql_profiler_units p1,
       (select a.runid, sum(a.total_time) run_total_time, b.run_comment
          from plsql_profiler_units a, plsql_profiler_runs b
         where a.runid = b.runid group by a.runid, b.run_comment ) p2
where p1.runid=p2.runid
   and p1.total_time > 0
   and p2.run_total_time > 0
   and (p1.total_time/p2.run_total_time) >= .01
order by p1.runid asc, p1.total_time desc;
column secs form 99999.99
prompt =
prompt =
prompt ====================
prompt percentage of time in each module, summarized across runs
select p1.unit_owner,
       decode(p1.unit_name, '', '<anonymous>', substr(p1.unit_name,1, 25)) as 
unit_name,
       p1.total_time/1000000000 as secs,
       TO_CHAR(100*p1.total_time/p2.grand_total, '99999.99') as percentage
from plsql_profiler_units_cross_run p1,
       plsql_profiler_grand_total p2
order by p1.total_time DESC;
 
prompt =
prompt =
prompt ====================
prompt lines taking more than 1% of the total time, each run separate
select p1.runid as runid,
       p1.total_time/10000000 as hsecs,
        p1.total_time/p4.grand_total*100 as pct,
       substr(p2.unit_owner, 1, 20) as owner,
       decode(p2.unit_name, '', '<anonymous>', substr(p2.unit_name,1, 20)) as 
unit_name,
       p1.line#,
       ( select p3.text
           from all_source p3
          where p3.owner = p2.unit_owner and
                p3.line = p1.line# and
                p3.name=p2.unit_name and
                p3.type not in ( 'PACKAGE', 'TYPE' )) text
from plsql_profiler_data p1,
       plsql_profiler_units p2,
       plsql_profiler_grand_total p4
where (p1.total_time >= p4.grand_total/100)
   AND p1.runid = p2.runid
   and p2.unit_number=p1.unit_number
order by p1.total_time desc;
prompt =
prompt =
prompt ====================
prompt most popular lines (more than 1%), summarize across all runs
select p1.total_time/10000000 as hsecs,
        p1.total_time/p4.grand_total*100 as pct,
       substr(p1.unit_owner, 1, 20) as unit_owner,
       decode(p1.unit_name, '', '<anonymous>',
                 substr(p1.unit_name,1, 20)) as unit_name,
       p1.line#,
       ( select p3.text from all_source p3
          where (p3.line = p1.line#) and
                (p3.owner = p1.unit_owner) AND
                (p3.name = p1.unit_name) and
                (p3.type not in ( 'PACKAGE', 'TYPE' ) ) ) text
from plsql_profiler_lines_cross_run p1,
        plsql_profiler_grand_total p4
where (p1.total_time >= p4.grand_total/100)
order by p1.total_time desc;
execute prof_report_utilities.rollup_all_runs;
prompt =
prompt =
prompt ====================
prompt Number of lines actually executed in different units (by unit_name)
select p1.unit_owner,
       p1.unit_name,
       count( decode( p1.total_occur, 0, null, 0)) as lines_executed ,
       count(p1.line#) as lines_present,
       count( decode( p1.total_occur, 0, null, 0))/count(p1.line#) *100
                                       as pct
from plsql_profiler_lines_cross_run p1
where (p1.unit_type in ( 'PACKAGE BODY', 'TYPE BODY',
                          'PROCEDURE', 'FUNCTION' ) )
group by p1.unit_owner, p1.unit_name;
 
prompt =
prompt =
prompt ====================
prompt Number of lines actually executed for all units
select count(p1.line#) as lines_executed
from plsql_profiler_lines_cross_run p1
where (p1.unit_type in ( 'PACKAGE BODY', 'TYPE BODY',
                          'PROCEDURE', 'FUNCTION' ) )
    AND p1.total_occur > 0;
 
prompt =
prompt =
prompt ====================
prompt total number of lines in all units
select count(p1.line#) as lines_present
from plsql_profiler_lines_cross_run p1
where (p1.unit_type in ( 'PACKAGE BODY', 'TYPE BODY',
                          'PROCEDURE', 'FUNCTION' ) );
spool off
set termout on
edit profsum.out
set linesize 131