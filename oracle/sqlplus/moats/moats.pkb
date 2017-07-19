create or replace package body moats as

   -- Internal types and global arrays for caching collections of
   -- SYSSTAT/ASH data for querying within MOATS...
   -- ------------------------------------------------------------------
   type moats_stat_ntt_aat is table of moats_stat_ntt
      index by pls_integer;
   g_stats moats_stat_ntt_aat;

   type moats_ash_ntt_aat is table of moats_ash_ntt
      index by pls_integer;
   g_ash moats_ash_ntt_aat;

   -- Internal type and variable for storing simple MOATS parameters...
   -- -----------------------------------------------------------------
   type parameter_aat is table of integer
      index by pls_integer;
   g_params parameter_aat;

   -- Variables for maintaining ASH/SYSSTAT collections...
   -- ----------------------------------------------------
   g_ash_size  pls_integer := 0;
   g_stat_size pls_integer := 0;

   -- global variable for screen size
   -- ----------------------------------------------------
   g_screen_size       pls_integer;

   -- General constants...
   -- --------------------
   gc_space       constant moats_output_ot := moats_output_ot(null);
   gc_mb          constant pls_integer     := 1048576;
   gc_gb          constant pls_integer     := 1048576*1024;
   gc_newline     constant varchar2(1)     := chr(10);

   gc_cpu         constant varchar2(1)     := '+';
   gc_io          constant varchar2(1)     := '*';
   gc_others      constant varchar2(1)     := '@';

   gc_cpu_color_prefix        constant varchar2(50)    := chr(27) || '[38;5;46m';
   gc_io_color_prefix         constant varchar2(50)    := chr(27) || '[38;5;21m';
   gc_others_color_prefix     constant varchar2(50)    := chr(27) || '[38;5;124m';
   gc_color_postfix           constant varchar2(50)    := chr(27) || '[0m';

   gc_max_screen_size      constant pls_integer     := 100;
   gc_default_screen_size  constant pls_integer     := 40;
   gc_default_ash_height   constant pls_integer     := 13;
   gc_default_sql_height   constant pls_integer     := 8;
   gc_ash_graph_length     constant pls_integer     := 86;
   gc_screen_width         constant pls_integer     := 175;

   -- variables for dealing with Active Session Graph
   -- ----------------------------------------------------
   g_ash_aas      ash_aas_ntt    := ash_aas_ntt();
   g_ash_graph    ash_graph_ntt  := ash_graph_ntt();
   g_ash_idx      pls_integer;
   g_ash_height   pls_integer;
   g_sql_height   pls_integer;

   g_ash_spaces        varchar2(100);
   g_ash_scales_height pls_integer;

   type ash_lines_aat is table of varchar2(4000);
   g_ash_lines ash_lines_aat := ash_lines_aat();
   g_ash_lines_color ash_lines_aat := ash_lines_aat();

   type ash_scales_aat is table of integer;
   g_ash_scales ash_scales_aat := ash_scales_aat();

   g_max_aas_current   pls_integer;

   ----------------------------------------------------------------------------
   procedure p( p_str in varchar2 ) is
   begin
      dbms_output.put_line(p_str);
   end p;

   ----------------------------------------------------------------------------
   procedure po( p_str in moats_output_ot ) is
   begin
      p(p_str.output);
   end po;

--   ----------------------------------------------------------------------------
--   procedure dump_ash is
--      pragma autonomous_transaction;
--   begin
--      insert into moats_ash_dump select * from table(moats.get_ash);
--      commit;
--   end dump_ash;

   ----------------------------------------------------------------------------
   function to_color( p_str in varchar2 ) return varchar2 is
   v_str varchar2(4000);
   begin
      v_str := regexp_replace(p_str, '(\' || gc_cpu    || '[\' || gc_cpu    || ' ]*)', gc_cpu_color_prefix    || '\1' || gc_color_postfix);
      v_str := regexp_replace(v_str, '(\' || gc_io     || '[\' || gc_io     || ' ]*)', gc_io_color_prefix     || '\1' || gc_color_postfix);
      v_str := regexp_replace(v_str, '(\' || gc_others || '[\' || gc_others || ' ]*)', gc_others_color_prefix || '\1' || gc_color_postfix);
      return v_str;
   end to_color;

   ----------------------------------------------------------------------------
   function to_color_ash( p_str in varchar2 ) return varchar2 is
   v_str varchar2(4000);
   begin
      v_str := regexp_replace(p_str, '(\' || gc_cpu    || '[\' || gc_cpu    || ' ]*)', gc_cpu_color_prefix    || '\1');
      v_str := regexp_replace(v_str, '(\' || gc_io     || '[\' || gc_io     || ' ]*)', gc_io_color_prefix     || '\1');
      v_str := regexp_replace(v_str, '(\' || gc_others || '[\' || gc_others || ' ]*)', gc_others_color_prefix || '\1');
      return v_str || gc_color_postfix;
   end to_color_ash;

   ----------------------------------------------------------------------------
   procedure show_snaps is
      v_indx pls_integer;
   begin
      p('ASH snaps...');
      p('------------------------------------');
      v_indx := g_ash.first;
      while v_indx is not null loop
         p(utl_lms.format_message('Index=[%d] Count=[%d]', v_indx, g_ash(v_indx).count));
         v_indx := g_ash.next(v_indx);
      end loop;
      p('STAT snaps...');
      p('------------------------------------');
      v_indx := g_stats.first;
      while v_indx is not null loop
         p(utl_lms.format_message('Index=[%d] Count=[%d]', v_indx, g_stats(v_indx).count));
         v_indx := g_stats.next(v_indx);
      end loop;
   end show_snaps;

   ----------------------------------------------------------------------------
   function banner return moats_output_ntt is
   begin
      return moats_output_ntt(
                moats_output_ot('MOATS: The Mother Of All Tuning Scripts v1.0 by Adrian Billington & Tanel Poder'),
                moats_output_ot('       http://www.oracle-developer.net & http://www.e2sn.com'),
                moats_output_ot(''),
                moats_output_ot('MOATS RAC Dashboard: V2.0.7.2 ASH & STATS Monitoring For RAC by Sidney Chen'),
                moats_output_ot('       sidney.chen@oracle.com(http://dbsid.com)')
                );
   end banner;

   ----------------------------------------------------------------------------
   function to_string ( p_collection in moats_v2_ntt,
                        p_delimiter  in varchar2 default ',',
                        p_elements   in pls_integer default null ) return varchar2 is
      v_str varchar2(4000);
   begin
      for i in 1 .. least(nvl(p_elements, p_collection.count), p_collection.count) loop
         v_str := v_str || p_delimiter || p_collection(i);
      end loop;
      return ltrim(v_str, p_delimiter);
   end to_string;

   ----------------------------------------------------------------------------
   procedure format_window is
      v_banner   moats_output_ntt := banner();
      c_boundary varchar2(110)    := rpad('-',110,'-');
      procedure spaces( p_spaces in pls_integer ) is
      begin
         for i in 1 .. p_spaces loop
            po(gc_space);
         end loop;
      end spaces;
   begin
      p(c_boundary);
      spaces(2);
      for i in 1 .. v_banner.count loop
         p(v_banner(i).output);
      end loop;
      spaces(3);
      p('       MOATS.FORMAT_WINDOW');
      p('       -------------------');
      p('       Align sqlplus window size to dotted lines for optimal output');
      spaces(g_screen_size-10);
      p(c_boundary);
   end format_window;

   ----------------------------------------------------------------------------
   procedure set_parameter( p_parameter_code  in pls_integer,
                            p_parameter_value in integer ) is
   begin
      g_params(p_parameter_code) := p_parameter_value;
   end set_parameter;

   ----------------------------------------------------------------------------
   function get_parameter ( p_parameter_code in pls_integer ) return integer is
   begin
      return g_params(p_parameter_code);
   end get_parameter;

   ----------------------------------------------------------------------------
   procedure restore_default_parameters is
   begin
      set_parameter(moats.gc_ash_polling_rate, 1);
      set_parameter(moats.gc_ash_threshold, 20000);
      set_parameter(moats.gc_top_refresh_rate, 10);
      -- By default don't use a trailing ASH window
      set_parameter(moats.gc_ash_window_size, NULL);
   end restore_default_parameters;

   ----------------------------------------------------------------------------
   procedure init_screen_variables( p_screen_size  in pls_integer,
                                    p_ash_height   in pls_integer,
                                    p_sql_height   in pls_integer) is
      v_max_height pls_integer;
   begin

      -- Initial the screen size variable and some sanity check ...
      -- -----------------------------------------------------------
      if ( p_screen_size is null or p_screen_size <= gc_default_screen_size or p_screen_size > gc_max_screen_size) then
         g_screen_size := gc_default_screen_size;
      else
         g_screen_size := p_screen_size;
      end if;

      v_max_height := (2/3) * g_screen_size;

      if ( p_ash_height is null or p_ash_height <= gc_default_ash_height or p_ash_height > v_max_height ) then
         g_ash_height := gc_default_ash_height;
      else
         g_ash_height := p_ash_height;
      end if;

      if ( p_sql_height is null or p_sql_height <= gc_default_sql_height or p_sql_height > v_max_height ) then
         g_sql_height := gc_default_sql_height;
      else
         g_sql_height := p_sql_height;
      end if;
   end init_screen_variables;

   ----------------------------------------------------------------------------
   procedure init_ash_graph_variables is
   begin

      g_ash_spaces         := lpad(' ', g_ash_height, ' ');
      g_ash_scales_height  := g_ash_height + 1;
      g_ash_idx            := 1;
      g_max_aas_current    := g_ash_height;
      g_ash_aas.extend(gc_ash_graph_length);
      g_ash_graph.extend(gc_ash_graph_length);
      g_ash_lines.extend(g_ash_height);
      g_ash_lines_color.extend(g_ash_height);
      g_ash_scales.extend(g_ash_scales_height);

      for i in 1 .. g_ash_aas.count loop
         g_ash_aas(i) := ash_aas_ot(0, 0, 0);
      end loop;

      for i in 1 .. g_ash_graph.count loop
         g_ash_graph(i) := ash_graph_ot(g_ash_spaces);
      end loop;

      for i in 1 .. g_ash_lines.count loop
         g_ash_lines(i) := lpad(' ', gc_ash_graph_length);
      end loop;
      for i in 1 .. g_ash_scales.count loop
         g_ash_scales(i) := g_ash_scales_height - i + 1;
      end loop;
   end init_ash_graph_variables;

   ----------------------------------------------------------------------------
   function get_sql( p_select   in varchar2,
                     p_from     in varchar2,
                     p_where    in varchar2,
                     p_group_by in varchar2,
                     p_order_by in varchar2 ) return varchar2 is
      v_sql varchar2(32767);
   begin
      v_sql := 'select ' || nvl(p_select, '*') || ' from ' || p_from;
      if p_where is not null then
         v_sql := v_sql || ' where ' || p_where;
      end if;
      if p_group_by is not null then
         v_sql := v_sql || ' group by ' || p_group_by;
      end if;
      if p_order_by is not null then
         v_sql := v_sql || ' order by ' || p_order_by;
      end if;
      return v_sql;
   end get_sql;

   ----------------------------------------------------------------------------
   function ash_history return interval day to second is
   begin
      return g_ash(g_ash.last)(1).snaptime - g_ash(g_ash.first)(1).snaptime;
   end ash_history;

   ----------------------------------------------------------------------------
   function ash_snap_count( p_lower_snap in pls_integer,
                              p_upper_snap in pls_integer ) return pls_integer is
      v_snap_cnt  pls_integer := 0;
      v_snap      pls_integer;
      v_exit      boolean := false;
   begin
      v_snap := p_lower_snap;
      while v_snap is not null and not v_exit loop
         v_snap_cnt := v_snap_cnt + 1;
         v_exit := (v_snap = p_upper_snap);
         v_snap := g_ash.next(v_snap);
      end loop;
      return greatest(v_snap_cnt,1);
   end ash_snap_count;

   ----------------------------------------------------------------------------
   function ash_sample_count( p_lower_snap in pls_integer,
                              p_upper_snap in pls_integer ) return pls_integer is
      v_samples pls_integer := 0;
      v_snap    pls_integer;
      v_exit    boolean := false;
   begin
      v_snap := p_lower_snap;
      while v_snap is not null and not v_exit loop
         -- Ignore dummy record and the record which is deleted by maintain_ash_collection
         if not ( (not g_ash.exists(v_snap)) or (g_ash(v_snap).count = 1 and g_ash(v_snap)(1).sid is null)) then
            v_samples := v_samples + g_ash(v_snap).count;
         end if;
         v_exit := (v_snap = p_upper_snap);
         v_snap := g_ash.next(v_snap);
      end loop;
      return greatest(v_samples,1);
   end ash_sample_count;

   ----------------------------------------------------------------------------
   procedure maintain_ash_collection( p_index in pls_integer ) is
   begin
      if g_ash(p_index).count = 0 then
         g_ash.delete(p_index);
      else
         g_ash_size := g_ash_size + g_ash(p_index).count;
         while g_ash_size > g_params(moats.gc_ash_threshold) loop
            g_ash_size := g_ash_size - g_ash(g_ash.first).count;
            g_ash.delete(g_ash.first);
         end loop;
      end if;
   end maintain_ash_collection;

   ----------------------------------------------------------------------------
   procedure snap_ash( p_index in pls_integer ) is
      v_sql_template varchar2(32767);
      v_sql          varchar2(32767);
   begin

      -- TODO: conditional compilation to get correct column list for version or
      -- select a small bunch of useful columns

      -- Use dynamic SQL to avoid explicit grants on V$SESSION. Prepare the start
      -- of the SQL as it will be used twice...
      -- ------------------------------------------------------------------------
      v_sql_template := q'[select moats_ash_ot( 
                                     inst_id, systimestamp, saddr, %sid%, serial#, audsid, paddr,
                                     user#, username, command, ownerid, taddr, lockwait,
                                     status, server, schema#, schemaname, osuser,
                                     process, machine, terminal, program, type,
                                     sql_address, sql_hash_value, sql_id, sql_child_number,
                                     prev_sql_addr, prev_hash_value, prev_sql_id,
                                     prev_child_number, module, module_hash, action,
                                     action_hash, client_info, fixed_table_sequence,
                                     row_wait_obj#, row_wait_file#, row_wait_block#,
                                     row_wait_row#, logon_time, last_call_et, pdml_enabled,
                                     failover_type, failover_method, failed_over,
                                     resource_consumer_group, pdml_status, pddl_status,
                                     pq_status, current_queue_duration, client_identifier,
                                     blocking_session_status, blocking_instance,
                                     blocking_session, seq#, event#, case when state = 'WAITING' then event else 'ON CPU' end, p1text, p1,
                                     p1raw, p2text, p2, p2raw, p3text, p3, p3raw,
                                     wait_class_id, wait_class#, case when state = 'WAITING' then wait_class else 'ON CPU' end, wait_time,
                                     seconds_in_wait, state, service_name, sql_trace,
                                     sql_trace_waits, sql_trace_binds
                                     )
                           from   gv$session
                           where  %preds%]';

      v_sql := replace( v_sql_template, '%sid%', 'sid');
      v_sql := replace( v_sql, '%preds%',  q'[    status = 'ACTIVE'
                                              and (wait_class != 'Idle' or state != 'WAITING')
                                              and (sql_id is null or (sql_id not in (select sql_id from v$session where sid=sys_context('userenv', 'sid')))) ]' );
                           
      execute immediate v_sql bulk collect into g_ash(p_index);

      -- If we have nothing to snap, add a dummy record that will be ignored
      -- in GET_ASH and GET_ASH_SAMPLE_COUNT...
      -- -------------------------------------------------------------------
      if g_ash(p_index).count = 0 then
         v_sql := replace( v_sql_template, '%sid%', 'null');
         v_sql := replace( v_sql, '%preds%', q'[(inst_id, sid) in (select sys_context('userenv', 'instance'), sys_context('userenv', 'sid') from dual)]' );
         execute immediate v_sql bulk collect into g_ash(p_index);
      end if;

      maintain_ash_collection(p_index);

   end snap_ash;

   ----------------------------------------------------------------------------
   procedure reset_stats_collection is
   begin
      g_stats.delete;
   end reset_stats_collection;

   ----------------------------------------------------------------------------
   procedure snap_stats( p_index in pls_integer,
                         p_reset in boolean default false ) is
   begin

      if p_reset then
         reset_stats_collection();
      end if;

      -- Use dynamic SQL to avoid explicit grants on V$ views...
      -- -------------------------------------------------------
      execute immediate
         q'[select moats_stat_ot(inst_id, type, name, value)
             from (
                   select ss.inst_id, 'STAT' as type
                   ,      sn.name
                   ,      ss.value
                   from   v$statname sn
                   ,      gv$sysstat  ss
                   where  sn.statistic# = ss.statistic#
                   and    sn.name in ( 'cell flash cache read hits', 
                                       'cell physical IO bytes eligible for predicate offload', 
                                       'cell physical IO bytes saved by storage index',
                                       'cell physical IO interconnect bytes returned by smart scan', 
                                       'execute count', 'logons cumulative', 'moats timer', 
                                       'parse count (hard)', 'parse count (total)', 
                                       'physical read total IO requests', 'physical read total bytes', 
                                       'physical write total IO requests', 'physical write total bytes', 
                                       'redo size', 'session cursor cache hits', 
                                       'session logical reads', 'user calls', 'user commits')
                  union all
                  select inst_id, 'osstat' as type
                  ,      STAT_NAME
                  ,      VALUE
                  from gv$osstat
                  union all
                  select inst_id, 'TIMER'
                   ,      'moats timer'
                   ,      hsecs
                   from   gv$timer
                  )]'
      bulk collect into g_stats(p_index);

   end snap_stats;

   ----------------------------------------------------------------------------
   function instance_summary ( p_lower_snap in pls_integer,
                               p_upper_snap in pls_integer,
                               p_refresh_rate in pls_integer ) return moats_output_ntt is

      type metric is record
      ( inst_id          number
      , value            number);
      type metric_total is record
      ( value            number);

      type metric_aat is table of metric
         index by pls_integer;
      type metric_total_aat is table of metric_total
         index by pls_integer;
      v_rows    moats_output_ntt := moats_output_ntt();
      v_metrics metric_aat;
      v_metrics_total metric_total_aat;
      v_secs    number;                 --<-- seconds between 2 stats snaps
      v_hivl    interval day to second; --<-- interval of ASH history saved
      v_hstr    varchar2(30);           --<-- formatted hh:mi:ss string of history

      type heading is table of varchar2(50);
      v_head heading := heading('Inst','CPU: idle%--usr%--sys%','Logons','Execs','Calls','Commits','sParse','hParse','ccHits','LIOs(K)','PhyRD','PhyWR','READ MB','Write MB','Redo MB','Offload%','ExSI MB','ExFCHits');
      v_headstr  varchar2(200);  
      v_metric_str  varchar2(200);  
      v_idx_base  number;
      v_dbname    varchar2(32);
      v_header    varchar2(200);

      v_total_cpu  number;
      v_idle_cpu   varchar2(10);
      v_usr_cpu    varchar2(10);
      v_sys_cpu    varchar2(10);

      v_offload  number;
      
      c_metrics  constant number := 23;
   begin

      -- Get long and short v_metrics for range of stats. Order for fixed array offset...
      -- ------------------------------------------------------------------------------
      select lwr.inst_id, upr.value - lwr.value
      bulk collect into v_metrics
      from   table(g_stats(p_lower_snap)) lwr
      ,      table(g_stats(p_upper_snap)) upr
      where  lwr.name = upr.name
      and    lwr.inst_id = upr.inst_id
      and    lwr.name in (
                        'BUSY_TIME', 'IDLE_TIME', 'IOWAIT_TIME', 'SYS_TIME', 
                        'USER_TIME', 'cell flash cache read hits', 
                        'cell physical IO bytes eligible for predicate offload', 
                        'cell physical IO bytes saved by storage index',
                        'cell physical IO interconnect bytes returned by smart scan', 
                        'execute count', 'logons cumulative', 'moats timer', 
                        'parse count (hard)', 'parse count (total)', 
                        'physical read total IO requests', 'physical read total bytes', 
                        'physical write total IO requests', 'physical write total bytes', 
                        'redo size', 'session cursor cache hits', 
                        'session logical reads', 'user calls', 'user commits')
      order  by
             lwr.inst_id,
             lwr.name;

      select sum(upr.value - lwr.value)
      bulk collect into v_metrics_total
      from   table(g_stats(p_lower_snap)) lwr
      ,      table(g_stats(p_upper_snap)) upr
      where  lwr.name = upr.name
      and    lwr.inst_id = upr.inst_id
      and    lwr.name in (
                        'BUSY_TIME', 'IDLE_TIME', 'IOWAIT_TIME', 'SYS_TIME', 
                        'USER_TIME', 'cell flash cache read hits', 
                        'cell physical IO bytes eligible for predicate offload', 
                        'cell physical IO bytes saved by storage index',
                        'cell physical IO interconnect bytes returned by smart scan', 
                        'execute count', 'logons cumulative', 'moats timer', 
                        'parse count (hard)', 'parse count (total)', 
                        'physical read total IO requests', 'physical read total bytes', 
                        'physical write total IO requests', 'physical write total bytes', 
                        'redo size', 'session cursor cache hits', 
                        'session logical reads', 'user calls', 'user commits')
      group by lwr.name
      order  by
             lwr.name;

      -- 1   BUSY_TIME
      -- 2   IDLE_TIME
      -- 3   IOWAIT_TIME
      -- 4   SYS_TIME
      -- 5   USER_TIME
      -- 6   cell flash cache read hits
      -- 7   cell physical IO bytes eligible for predicate offload
      -- 8   cell physical IO bytes saved by storage index
      -- 9   cell physical IO interconnect bytes returned by smart scan
      -- 10  execute count
      -- 11  logons cumulative
      -- 12  moats timer
      -- 13  parse count (hard)
      -- 14  parse count (total)
      -- 15  physical read total IO requests
      -- 16  physical read total bytes
      -- 17  physical write total IO requests
      -- 18  physical write total bytes
      -- 19  redo size
      -- 20  session cursor cache hits
      -- 21  session logical reads
      -- 22  user calls
      -- 23  user commits

      -- Logons/s:    logon count
      -- Execs/s:     execute count
      -- sParse/s:    parse count (total)
      -- LIOs/s:      session logical reads
      -- Read MB/s:   physical read total bytes / 1048576
      -- Calls/s:     user calls
      -- hParse/s:    parse count (hard)
      -- PhyRD/s:     physical read total IO requests
      -- PhyWR/s:     physical write total IO requests
      -- Write MB/s:  physical write total bytes / 1048576
      -- History:
      -- Commits/s:   user commits
      -- ccHits/s:    session cursor cache hits
      -- Redo MB/s:   redo size
      -- Offload%:    1 - (cell physical IO interconnect bytes returned by smart scan)/(cell physical IO bytes eligible for predicate offload)
      -- ExSIMB/s:    (cell physical IO bytes saved by storage index) / 1048576
      -- ExFCHits/s:  cell flash cache read hits 

      -- Calculate number of seconds...
      -- ------------------------------
      v_secs := v_metrics(12).value/100;

      -- Calculate ASH history...
      -- ------------------------
      v_hivl := ash_history();
      v_hstr := to_char(extract(hour from v_hivl))   || 'h ' ||
                to_char(extract(minute from v_hivl)) || 'm ' ||
                to_char(trunc(extract(second from v_hivl))) || 's';
      select name into v_dbname from v$database;
      v_header := '+ Database: ' || rpad(v_dbname, 8) || rpad('| Current Time: ' ||
                  to_char(sysdate, 'DD-Mon hh24:mi:ss'), 36) ||
                  rpad('| ASH History:  ' || v_hstr, 27) || '|';
      -- Set the instance summary output...
      -- ----------------------------------

      v_rows.extend(2);
      --v_rows(1) := moats_output_ot(v_header);
      v_rows(1) := moats_output_ot(rpad('+ Database: ' || rpad(v_dbname, 8) || ' |' || rpad(' Activity Statistics Per Second',33) || '|' ||
                                       rpad(' Interval: ' || nvl(p_refresh_rate, g_params(moats.gc_top_refresh_rate)) || 's ',17) ||  '|' ||
                                       rpad(' Screen Window = ' || g_screen_size || ' * ' || gc_screen_width, 26) || '|' ||
                                       rpad(' Ash Height = ' || g_ash_height, 17) || '|' ||
                                       rpad(' SQL Height = ' || g_sql_height, 17) || '|' || 
                                       rpad(' Arraysize should be ' || 2 * g_screen_size, 26) || '+', 172,'-') || '+');
      v_headstr := '|Inst|CPU: idle%--usr%--sys%|';
      for i in 3 .. v_head.count
      loop
         v_headstr := v_headstr || lpad(v_head(i),8) || '|';
      end loop;
      v_rows(2) := moats_output_ot(v_headstr);

      for i in 1 .. v_metrics.count/c_metrics loop
         v_idx_base := (i-1)*c_metrics;
         v_metric_str := '|';
         v_metric_str := v_metric_str || lpad(v_metrics(v_idx_base+1).inst_id, '4') || '|'; -- instance number
         v_total_cpu  := v_metrics(v_idx_base+1).value + v_metrics(v_idx_base+2).value;
         v_idle_cpu   := to_char(100*v_metrics(v_idx_base+2).value/v_total_cpu,'fm999.0');
         v_usr_cpu    := to_char(100*v_metrics(v_idx_base+5).value/v_total_cpu,'fm999.0');
         v_sys_cpu    := to_char(100*v_metrics(v_idx_base+4).value/v_total_cpu,'fm999.0');
         v_metric_str := v_metric_str || '    ' || lpad(v_idle_cpu,6) || lpad(v_usr_cpu,6) || lpad(v_sys_cpu,6) || '|'; -- CPU
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+11).value/v_secs,'fm99999999'), '8') || '|'; -- Logons
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+10).value/v_secs,'fm99999999'), '8') || '|'; -- Execs
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+22).value/v_secs,'fm99999999'), '8') || '|'; -- Calls
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+23).value/v_secs,'fm99999999'), '8') || '|'; -- Commit
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+14).value/v_secs,'fm99999999'), '8') || '|'; -- sParse
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+13).value/v_secs,'fm99999999'), '8') || '|'; -- hParse
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+20).value/v_secs,'fm99999999'), '8') || '|'; -- ccHits
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+21).value/v_secs/1000,'fm99999999'), '8') || '|'; -- LIOs(K)
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+15).value/v_secs,'fm99999999'), '8') || '|'; -- PhyRD
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+17).value/v_secs,'fm99999999'), '8') || '|'; -- PhyWR
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+16).value/v_secs/gc_mb,'fm99999999'), '8') || '|'; -- READ MB
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+18).value/v_secs/gc_mb,'fm99999999'), '8') || '|'; -- Write MB
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+19).value/v_secs/gc_mb,'fm99999999'), '8') || '|'; -- Redo MB
         v_offload    := case when v_metrics(v_idx_base+9).value=0 or v_metrics(v_idx_base+7).value=0 then
                           0
                         else 
                           100*(1-v_metrics(v_idx_base+9).value/v_metrics(v_idx_base+7).value)
                         end;
         v_metric_str := v_metric_str || lpad(to_char(v_offload,'fm999.0'), '8') || '|'; -- offload percent
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+8).value/v_secs/gc_mb,'fm99999999'), '8') || '|'; -- IO Save by Storage index MB
         v_metric_str := v_metric_str || lpad(to_char(v_metrics(v_idx_base+6).value/v_secs,'fm99999999'), '8') || '|'; -- Smart Flash Cache hit
         v_rows.extend(1);
         v_rows(v_rows.last) := moats_output_ot(v_metric_str);
      end loop;
      v_rows.extend(1);
      v_rows(v_rows.last) := moats_output_ot(rpad('+', 172, '-') || '+');

      v_metric_str := '                      Total :';
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(11).value/v_secs,'fm99999999'), '8') || ';'; -- Logons
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(10).value/v_secs,'fm99999999'), '8') || ';'; -- Execs
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(22).value/v_secs,'fm99999999'), '8') || ';'; -- Calls
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(23).value/v_secs,'fm99999999'), '8') || ';'; -- Commit
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(14).value/v_secs,'fm99999999'), '8') || ';'; -- sParse
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(13).value/v_secs,'fm99999999'), '8') || ';'; -- hParse
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(20).value/v_secs,'fm99999999'), '8') || ';'; -- ccHits
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(21).value/v_secs/1000,'fm99999999'), '8') || ';'; -- LIOs(K)
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(15).value/v_secs,'fm99999999'), '8') || ';'; -- PhyRD
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(17).value/v_secs,'fm99999999'), '8') || ';'; -- PhyWR
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(16).value/v_secs/gc_mb,'fm99999999'), '8') || ';'; -- READ MB
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(18).value/v_secs/gc_mb,'fm99999999'), '8') || ';'; -- Write MB
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(19).value/v_secs/gc_mb,'fm99999999'), '8') || ';'; -- Redo MB
      v_metric_str := v_metric_str || lpad(' ', '8') || ';'; -- Offload
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(8).value/v_secs/gc_mb,'fm99999999'), '8') || ';'; -- IO Save by Storage index MB
      v_metric_str := v_metric_str || lpad(to_char(v_metrics_total(6).value/v_secs,'fm99999999'), '8') || ';'; -- Smart Flash Cache hit

      v_rows.extend(1);
      v_rows(v_rows.last) := moats_output_ot(v_metric_str);

      return v_rows;

   end instance_summary;

   ----------------------------------------------------------------------------
   procedure draw_active_session_graph ( p_lower_snap in pls_integer,
                          p_upper_snap in pls_integer) is

      v_snaps     pls_integer;

      -- Variables to draw active session graph...
      -- --------------------------------------------------
      v_max_aas pls_integer;
      v_line varchar2(200);
      v_idx  integer;
   begin

      -- Calculate number of ASH snapshot for this output...
      -- --------------------------------------------------
      v_snaps := ash_snap_count( p_lower_snap => p_lower_snap,
                                     p_upper_snap => p_upper_snap );

      -- Fetch aas, cpu_aas , io_aas...
      -- -------------------------------
      select count(*)/v_snaps aas,
             sum(case when wait_class='ON CPU' then 1 else 0 end)/v_snaps cpu_aas,
             sum(case when wait_class='User I/O' then 1 else 0 end)/v_snaps io_aas
      into g_ash_aas(g_ash_idx).aas, g_ash_aas(g_ash_idx).cpu_aas, g_ash_aas(g_ash_idx).io_aas
      from   table(
                moats.get_ash(
                   p_lower_snap, p_upper_snap, moats.gc_all_rows));
      
      select case when max(aas) <= g_ash_height then g_ash_height else ceil(max(aas)) end
      into v_max_aas
      from  table(g_ash_aas);

      if v_max_aas = g_max_aas_current then

      -- Only draw the lastest sample
      -- -------------------------------
         g_ash_graph(g_ash_idx) :=  ash_graph_ot(rpad(nvl(
                                    rpad(gc_cpu, round((g_ash_aas(g_ash_idx).cpu_aas/g_max_aas_current) * g_ash_height), gc_cpu) ||
                                    rpad(gc_io, round((g_ash_aas(g_ash_idx).io_aas/g_max_aas_current) * g_ash_height), gc_io) || 
                                    rpad(gc_others, round(((g_ash_aas(g_ash_idx).aas - g_ash_aas(g_ash_idx).cpu_aas - g_ash_aas(g_ash_idx).io_aas)/g_max_aas_current) * g_ash_height), gc_others), ' '), 
                                    g_ash_height, ' '));
         for i in 1 .. g_ash_height loop
            g_ash_lines(i) := substr(g_ash_lines(i), 2, gc_ash_graph_length-1) || substr(g_ash_graph(g_ash_idx).graph, g_ash_height-i+1, 1);
         end loop;
      else

      -- Re-draw al the samples
      -- -------------------------------
         g_max_aas_current := v_max_aas;
         for i in 1 .. gc_ash_graph_length loop
            if round((g_ash_aas(i).aas/g_max_aas_current) * g_ash_height) < 1 then
               g_ash_graph(i) := ash_graph_ot(g_ash_spaces);
            else
               g_ash_graph(i) :=  ash_graph_ot(rpad(nvl(
                                          rpad(gc_cpu, round((g_ash_aas(i).cpu_aas/g_max_aas_current) * g_ash_height), gc_cpu) ||
                                          rpad(gc_io, round((g_ash_aas(i).io_aas/g_max_aas_current) * g_ash_height), gc_io) || 
                                          rpad(gc_others, round(((g_ash_aas(i).aas - g_ash_aas(i).cpu_aas - g_ash_aas(i).io_aas)/g_max_aas_current) * g_ash_height), gc_others), ' '), 
                                          g_ash_height, ' '));
            end if;
         end loop;
         for i in 1 .. g_ash_height loop
            v_line := '';
            for j in 1 .. gc_ash_graph_length loop
              v_line := v_line || substr(g_ash_graph(mod(g_ash_idx+j-1, gc_ash_graph_length)+1).graph, g_ash_height-i+1, 1);
            end loop;
            g_ash_lines(i) := v_line;
         end loop;

      -- Re-draw the scales
      -- -------------------------------
      for i in 1 .. g_ash_scales.count loop
         g_ash_scales(i) := round(g_max_aas_current * (g_ash_scales_height-i+1)/g_ash_height);
      end loop;
      end if;

      -- trun the g_ash_lines into colourfull
      -- ------------------------------------
      for i in 1 .. g_ash_height loop
         g_ash_lines_color(i) := to_color_ash(g_ash_lines(i));
      end loop;
   
      g_ash_idx := g_ash_idx + 1;
      if g_ash_idx > gc_ash_graph_length then
         g_ash_idx := 1;
      end if;

   end draw_active_session_graph;

   ----------------------------------------------------------------------------
   function top_summary ( p_lower_snap in pls_integer,
                          p_upper_snap in pls_integer,
                          p_refresh_rate in pls_integer) return moats_output_ntt is

      type top_sql_rt is record
      ( sql_id           varchar2(64)
      , occurrences      number
      , inst_cnt         number
      , top_sids         moats_v2_ntt
      , first_top_event  varchar2(40)
      , second_top_event varchar2(40));

      type top_waits_rt is record
      ( inst_id     number
      , wait_name   varchar2(64)
      , wait_class  varchar2(64)
      , occurrences number );

      type top_sql_aat is table of top_sql_rt
         index by pls_integer;

      type top_waits_aat is table of top_waits_rt
         index by pls_integer;

      v_row       varchar2(4000);
      v_rows      moats_output_ntt := moats_output_ntt();
      v_top_sqls  top_sql_aat;
      v_top_waits top_waits_aat;
      v_samples   pls_integer;
      v_snaps     pls_integer;

   begin

      -- Calculate number of ASH snapshot for this output...
      -- --------------------------------------------------
      v_snaps := ash_snap_count( p_lower_snap => p_lower_snap,
                                     p_upper_snap => p_upper_snap );

      -- Calculate number of ASH samples for this output...
      -- --------------------------------------------------
      v_samples := ash_sample_count( p_lower_snap => p_lower_snap,
                                     p_upper_snap => p_upper_snap );

      -- Top SQL_IDs...
      -- --------------
      with ash_data as (
              select inst_id, sid, sql_id, event
              from   table(
                        moats.get_ash(
                           p_lower_snap, p_upper_snap, moats.gc_all_rows))
            ),
            ash_sql_event as (
              select sql_id, top_event, row_number
              from
              (
                 select sql_id,
                        substr(event, 1, 28) ||  ' (' || round(100*ratio_to_report(count(*)) over ( partition by sql_id)) || '%)' top_event,
                        row_number() over (partition by sql_id order by count(*) desc) as row_number
                 from   table(
                           moats.get_ash(
                              p_lower_snap, p_upper_snap, moats.gc_all_rows))
                 group by sql_id, event
                 order by count(*) desc
              )
              where row_number <=2
            )
      select o_ash.sql_id
      ,      o_ash.occurrences
      ,      o_ash.inst_cnt
      ,      cast(
                multiset(
                   select i_ash.sid || '@' || i_ash.inst_id
                   from   ash_data i_ash
                   where   nvl(i_ash.sql_id,'X') = nvl(o_ash.sql_id,'X')
                   group  by
                          i_ash.sid, i_ash.inst_id
                   order  by
                          count(*) desc
                   ) as moats_v2_ntt) as top_sids
      ,      (
                   select  top_event
                   from    ash_sql_event i_ash
                   where   nvl(i_ash.sql_id,'X') = nvl(o_ash.sql_id,'X')
                   and     i_ash.row_number = 1
                   ) as first_top_event
      ,      (
                   select  top_event
                   from    ash_sql_event i_ash
                   where   nvl(i_ash.sql_id,'X') = nvl(o_ash.sql_id,'X')
                   and     i_ash.row_number = 2 
                   ) as second_top_event
      bulk collect into v_top_sqls
      from  (
             select sql_id
             ,      count(*) as occurrences
             ,      count(distinct inst_id) as inst_cnt
             from   ash_data
             group  by
                    sql_id
             order  by
                    count(*) desc
            ) o_ash
      where  rownum <= g_sql_height;

      -- Top waits...
      -- ------------
      select inst_id
      ,      substr(event,1,28)
      ,      wait_class
      ,      occurrences
      bulk collect into v_top_waits
      from  (
             select inst_id
             ,      event
             ,      wait_class
             ,      count(*) as occurrences
             from   table(
                       moats.get_ash(
                          p_lower_snap, p_upper_snap, moats.gc_all_rows))
             group  by
                    inst_id       
             ,      event
             ,      wait_class
             order  by
                    count(*) desc
            )
      where  rownum <= g_ash_height;

      -- Begin TOP Event summary...
      -- --------------------
      v_rows.extend(2);
      v_rows(1) := moats_output_ot(lpad('_______                                Active Session Graph                                    _______', 173,' '));
      v_rows(2) := moats_output_ot(
                      rpad('+   AAS| TOP|Instance| Top Events',51,'-') || '+ WAIT CLASS -+'  || lpad(g_ash_scales(1),10) ||
                      to_color(rpad(' | CPU:' || gc_cpu || ' IO:' || gc_io || ' Others:' || gc_others, 90, ' ')) ||
                           '| ' || g_ash_scales(1)
                      );

      -- Top Event Summary and Active Session Graph output...
      -- -----------------
      for i in 1 .. g_ash_height loop
         v_rows.extend;
         v_row := case
                     when v_top_waits.exists(i)
                     then '|' || lpad(to_char((v_top_waits(i).occurrences/v_snaps), 'fm99990.0'),6)  ||
                          '|' || lpad(to_char((v_top_waits(i).occurrences/v_samples)*100, 'fm9999'),3) || '%' ||
                          '|' || lpad('inst(' || v_top_waits(i).inst_id || ')',8) || 
                          rpad('| ' || substr(v_top_waits(i).wait_name,1,35), 29) ||
                          rpad(' | ' || v_top_waits(i).wait_class, 15) || '|'
                     when i = v_top_waits.count + 1
                     then rpad('+',65,'-') || '+'
                     else rpad(' ', 66)
                  end;
         v_row := v_row ||  lpad(g_ash_scales(i+1), 10) || ' | ' || g_ash_lines_color(i) || ' | ' || rpad(g_ash_scales(i+1), 6);

         v_rows(v_rows.last) := moats_output_ot(v_row);
      end loop;
         
      if v_top_waits.count >= g_ash_height then
         v_row := rpad('+',65,'-') || '+         0 +'  || lpad('-', 88, '-') || '+ 0';
      else
         v_row := lpad('0 +',78,' ') || lpad('-', 88, '-') || '+ 0';
      end if; 
      v_rows.extend(1);
      v_rows(v_rows.last) := moats_output_ot(v_row);

      v_row := lpad('^ '||to_char(sysdate-(nvl(p_refresh_rate, g_params(moats.gc_top_refresh_rate)) * gc_ash_graph_length)/86400, 'hh24:mi:ss'), 89, ' ') ||
               lpad(to_char(sysdate-(nvl(p_refresh_rate, g_params(moats.gc_top_refresh_rate)) * gc_ash_graph_length)/86400/2, 'hh24:mi:ss') || ' ^', 33) || 
               lpad(to_char(sysdate, 'hh24:mi:ss') || ' ^', 43); 

      v_rows.extend(1);
      v_rows(v_rows.last) := moats_output_ot(v_row);
      --v_rows.extend(1);
      --v_rows(v_rows.last) := gc_space;


      -- Top SQL Summary output 
      -- --------------------------------------------------------------------------
      v_rows.extend;
      v_rows(v_rows.last) := moats_output_ot(
                      rpad('+   AAS| TOP| SQL_ID ',28,'-') ||
                      rpad('+ 1st TOP Event(%) ',37,'-') ||
                      rpad('+ 2nd TOP Event(%) ',37,'-') ||
                      rpad('+ Inst_Cnt ', 11,'-') ||
                      rpad('+ TOP SESSIONS (sid@inst_id) ',59,'-') || '+'
                      );
      for i in 1 .. v_top_sqls.count loop
         v_rows.extend;
         v_row := '|' || lpad(to_char((v_top_sqls(i).occurrences/v_snaps), 'fm99990.0'),6)  ||
                  '|' || lpad(to_char((v_top_sqls(i).occurrences/v_samples)*100, 'fm9999'),3) || '%' ||
                  rpad('| ' || v_top_sqls(i).sql_id , 16) ||
                  rpad('| ' || v_top_sqls(i).first_top_event, 37) ||
                  rpad('| ' || v_top_sqls(i).second_top_event, 37) ||
                  '| ' || lpad(v_top_sqls(i).inst_cnt || ' ', 9) ||
                  rpad('| ' || to_string(v_top_sqls(i).top_sids, p_elements => 8), 59) || '|';

         v_rows(v_rows.last) := moats_output_ot(v_row);
      end loop;

      v_rows.extend;
      v_rows(v_rows.last) := moats_output_ot(
                                rpad('+',172,'-') || '+'
                                );


      -- Top SQL output - we're going to deliberately loop r-b-r for the sql_ids...
      -- --------------------------------------------------------------------------
      v_rows.extend;
      v_rows(v_rows.last) := moats_output_ot(
                                rpad('+ TOP SQL_ID ----+ PLAN_HASH_VALUE + SQL TEXT ', 172, '-') || '+'
                                );
      for i in 1 .. v_top_sqls.count loop
         for r_sql in (select distinct sql_id, regexp_replace(sql_text, '( ){2,}','\1' ) sql_text, plan_hash_value
                       from   gv$sql
                       where  sql_id = v_top_sqls(i).sql_id
                       and    rownum = 1)
         loop
            v_rows.extend;
            v_rows(v_rows.last) := moats_output_ot(
                                      rpad('| ' || r_sql.sql_id, 17) ||
                                      rpad('| ' || r_sql.plan_hash_value, 18) ||
                                      rpad('| ' || substr(r_sql.sql_text, 1, 135), 136) || ' |'
                                      );
            v_rows.extend;
            v_rows(v_rows.last) := moats_output_ot(
                                      rpad('+', 17, '-') ||
                                      rpad('-', 18, '-') ||
                                      rpad('-', 137, '-') || '+'
                                      );
         end loop;
      end loop;

      return v_rows;

   end top_summary;

   ----------------------------------------------------------------------------
   procedure poll( p_refresh_rate in  integer,
                   p_include_ash  in  boolean,
                   p_include_stat in  boolean,
                   p_lower_snap   out pls_integer,
                   p_upper_snap   out pls_integer ) is

      v_index        pls_integer;
      v_refresh_rate integer := nvl(p_refresh_rate, g_params(moats.gc_top_refresh_rate));

      function snap_index return pls_integer is
      begin
         return dbms_utility.get_time();
      end snap_index;

   begin

      -- Set starting snap index...
      -- --------------------------
      v_index := snap_index();
      p_lower_snap := v_index;

      -- Snap SYSSTAT if required...
      -- ---------------------------
      if p_include_stat then
         snap_stats(v_index, true);
      end if;

      -- Snap ASH if required...
      -- -----------------------
      if p_include_ash then
         for i in 1 .. ceil(v_refresh_rate/g_params(moats.gc_ash_polling_rate)) loop
            if i > 1 then
              v_index := snap_index;
            end if;
            snap_ash(v_index);
            dbms_lock.sleep(g_params(moats.gc_ash_polling_rate));
         end loop;
      end if;

      -- If no ASH samples taken, sleep for refresh rate instead...
      -- ----------------------------------------------------------
      if p_include_stat and not p_include_ash then
         dbms_lock.sleep(v_refresh_rate);
         v_index := snap_index;
      end if;

      -- Snap SYSSTAT again if required...
      -- ---------------------------------
      if p_include_stat then
         snap_stats(v_index);
      end if;

      -- Set end snap index...
      -- ---------------------
      p_upper_snap := v_index;

   end poll;

   ----------------------------------------------------------------------------
   -- Determine ASH trailing window size
   ----------------------------------------------------------------------------
   function get_ash_window_lower_snap (
        p_lower_snap      in pls_integer,
        p_upper_snap      in pls_integer,
        p_refresh_rate    in pls_integer,
        p_ash_window_size in pls_integer
        ) return pls_integer is

      v_snap_count      pls_integer;
      v_snap            pls_integer;
      v_ash_window_size pls_integer;
   begin
      v_ash_window_size := nvl(p_ash_window_size, get_parameter(moats.gc_ash_window_size));
      -- By default no ASH trailing window or if refresh rate greater than window size
      -- -----------------------------------------------------------------------------
      if v_ash_window_size is null or p_refresh_rate >= v_ash_window_size then
         v_snap := p_lower_snap;
      else
         v_snap_count := 1;
         v_snap := p_upper_snap;
         while v_snap_count < v_ash_window_size and g_ash.prior(v_snap) is not null loop
           v_snap_count := v_snap_count + 1;
           v_snap := g_ash.prior(v_snap);
         end loop;
      end if;

      return v_snap;
   end get_ash_window_lower_snap;

   ----------------------------------------------------------------------------
   function top (
            p_refresh_rate    in integer default null,
            p_screen_size     in integer default null,
            p_ash_height      in integer default null,
            p_sql_height      in integer default null,
            p_ash_window_size in integer default null
            ) return moats_output_ntt pipelined is

      v_lower_snap pls_integer;
      v_upper_snap pls_integer;
      v_row        varchar2(4000);
      v_rows       moats_output_ntt := moats_output_ntt();
      v_cnt        pls_integer := 0;

   begin

      -- Init the screen size variable and some sanity check ...
      -- -----------------------------------------------------------
      init_screen_variables( p_screen_size, p_ash_height, p_sql_height);

      -- Initial clear screen and stabiliser...
      -- --------------------------------------
      v_rows := banner();
      -- fill the initial "blank screen" (this is needed for arraysize = 2*g_screen_size to work)
      for i in 1 .. g_screen_size loop
         pipe row (gc_space);
      end loop;
      -- print banner onto the top of the screen
      for i in 1 .. v_rows.count loop
         pipe row (v_rows(i));
      end loop;
      -- fill the rest of the visible screen
      for i in 1 .. g_screen_size-(v_rows.count+1) loop
         pipe row (gc_space);
      end loop;
      pipe row (moats_output_ot('Please wait : fetching data for first refresh...'));
      -- singce the first sqlplus fetech size is 1, output an additional space row) 
      pipe row (gc_space);

      -- Init Active Session Graph variables
      -- ---------------------------------------
      init_ash_graph_variables();

      -- Begin TOP refreshes...
      -- ----------------------
      loop

         -- Take some ASH/STAT samples...
         -- -----------------------------
         poll( p_refresh_rate => p_refresh_rate,
               p_include_ash  => true,
               p_include_stat => true,
               p_lower_snap   => v_lower_snap,
               p_upper_snap   => v_upper_snap );

         -- Banner...
         -- ---------
         -- v_rows := banner();
         -- for i in 1 .. v_rows.count loop
         --    pipe row (v_rows(i));
         -- end loop;
         -- pipe row (gc_space);
         -- v_cnt := v_rows.count + 1;
         v_cnt := 0;

         v_lower_snap := get_ash_window_lower_snap( p_lower_snap => v_lower_snap,
                                                    p_upper_snap => v_upper_snap,
                                                    p_refresh_rate => p_refresh_rate,
                                                    p_ash_window_size => p_ash_window_size );

         -- Draw the colorfull Active Session Graph...
         -- ------------------------------------------
         draw_active_session_graph( p_lower_snap => v_lower_snap,
                                    p_upper_snap => v_upper_snap);

         -- Clear screen...
         -- ---------------
         for i in 1 .. g_screen_size loop
            pipe row (gc_space);
         end loop;

         -- Instance summary...
         -- -------------------
         v_rows := instance_summary( p_lower_snap => v_lower_snap,
                                     p_upper_snap => v_upper_snap,
                                     p_refresh_rate => p_refresh_rate );
         for i in 1 .. v_rows.count loop
            pipe row (v_rows(i));
         end loop;
         --pipe row (gc_space);
         v_cnt := v_cnt + v_rows.count;

         -- Top SQL and waits section...
         -- ----------------------------
         v_rows := top_summary( p_lower_snap => v_lower_snap,
                                p_upper_snap => v_upper_snap,
                                p_refresh_rate => p_refresh_rate);

         -- In case the arraysize is overflow 
         -- ---------------------------------
         for i in 1 .. least(v_rows.count, (g_screen_size-v_cnt)) loop
            pipe row (v_rows(i));
         end loop;
         v_cnt := v_cnt + v_rows.count;

         -- Some blank output...
         -- --------------------
         if v_cnt < (g_screen_size) then
            for i in 1 .. (g_screen_size)-v_cnt loop
               pipe row (gc_space);
            end loop;
         end if;

      end loop;
      return;

   exception
      when no_data_found then
         raise_application_error(-20000, 'Error: '||sqlerrm||' at:'||chr(10)||dbms_utility.format_error_backtrace);
   end top;

   ----------------------------------------------------------------------------
   function ash (
            p_refresh_rate in integer  default null,
            p_select       in varchar2 default null,
            p_where        in varchar2 default null,
            p_group_by     in varchar2 default null,
            p_order_by     in varchar2 default null
            ) return moats_output_ntt pipelined is

      v_lower_snap pls_integer;
      v_upper_snap pls_integer;
      v_row        varchar2(4000);
      v_cnt        pls_integer := 0;

      -- DBMS_SQL variables...
      -- ---------------------
      v_sql        varchar2(32767);
      v_cursor     binary_integer;
      v_execute    integer;
      v_desc       dbms_sql.desc_tab2;
      v_cols       integer;
      v_value      varchar2(4000);

   begin

      -- Build up the dynamic SQL...
      -- ---------------------------
      v_sql := get_sql( p_select   => p_select,
                        p_from     => 'TABLE(moats.get_ash(:b1, :b2))',
                        p_where    => p_where,
                        p_group_by => p_group_by,
                        p_order_by => p_order_by );

      -- Open a cursor for the ASH queries, parse and describe it...
      -- -----------------------------------------------------------
      v_cursor := dbms_sql.open_cursor;
      dbms_sql.parse(v_cursor, v_sql, dbms_sql.native);
      dbms_sql.describe_columns2(v_cursor, v_cols, v_desc);

      -- Take some ASH samples...
      -- ------------------------
      poll( p_refresh_rate => p_refresh_rate,
            p_include_ash  => true,
            p_include_stat => false,
            p_lower_snap   => v_lower_snap,
            p_upper_snap   => v_upper_snap );

      -- Bind the ASH snapshots...
      -- -------------------------
      dbms_sql.bind_variable(v_cursor, 'b1', v_lower_snap);
      dbms_sql.bind_variable(v_cursor, 'b2', v_upper_snap);

      -- Define the columns and variable we are fetching into...
      -- -------------------------------------------------------
      for i in 1 .. v_cols loop
         dbms_sql.define_column(v_cursor, i, v_value, 4000);
      end loop;

      -- Output the heading...
      -- ---------------------
      for i in 1 .. v_cols loop
         v_row := v_row || '|' || v_desc(i).col_name;
      end loop;
      pipe row (moats_output_ot(v_row));
      v_row := null;

      -- Start fetching...
      -- -----------------
      v_execute := dbms_sql.execute(v_cursor);

      while dbms_sql.fetch_rows(v_cursor) > 0 loop
         for i in 1 .. v_cols loop
            dbms_sql.column_value(v_cursor, i, v_value);
            v_row := v_row || '|' || v_value;
         end loop;
         pipe row (moats_output_ot(v_row));
         v_row := null;
      end loop;
      dbms_sql.close_cursor(v_cursor); --<-- will never be reached on an infinite loop with ctrl-c

      return;

   exception
      when others then
         dbms_sql.close_cursor(v_cursor);
         raise_application_error (-20000, 'Error: ' || sqlerrm || ' at:' || chr(10) || dbms_utility.format_error_backtrace, true);
   end ash;

   ----------------------------------------------------------------------------
   function get_ash (
            p_lower_snap in pls_integer default null,
            p_upper_snap in pls_integer default null,
            p_return_set in pls_integer default moats.gc_all_rows
            ) return moats_ash_ntt pipelined is
      v_lower_snap pls_integer := nvl(p_lower_snap, g_ash.first);
      v_upper_snap pls_integer := nvl(p_upper_snap, g_ash.last);
      v_snap       pls_integer;
      v_exit       boolean := false;
   begin
      v_snap := v_lower_snap;
      while v_snap is not null and not v_exit loop
         for i in 1 .. g_ash(v_snap).count loop
            -- Ignore dummy records
            if g_ash(v_snap)(i).sid is not null then
               pipe row (g_ash(v_snap)(i));
            end if;
         end loop;
         v_exit := (v_snap = v_upper_snap);
         v_snap := case p_return_set
                      when moats.gc_all_rows
                      then g_ash.next(v_snap)
                      else v_upper_snap
                   end;
      end loop;
      return;
   end get_ash;

begin
   restore_default_parameters();
end moats;
/
