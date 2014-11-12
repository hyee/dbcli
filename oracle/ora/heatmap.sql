--
-- OraLatencyMap_internal - This is the internal part of OraLatencyMap, a tool to visualize Oracle wait events latency with heatmaps
--                        - do not run this directly, use a launcher script instead: OraLatencyMap or OraLatencyMap_advanced
--
-- Luca.Canali@cern.ch, v1.2, March 2014. Original version, August 2013.
--
-- More info: see README
--

set lines 2000
set pages 100
set feedback off
set verify off
set heading off
set long 100000
set longchunksize 100000
var var_screen clob

define sleep_interval=3
define wait_event='db file sequential read'
define num_bins=11
define num_rows=90
define instance_filter_clause=''


--
-- OraLatencyMap_internal - This is the internal part of OraLatencyMap, a tool to visualize Oracle wait events latency with heatmaps
--                        - do not run this directly, use a launcher script instead: OraLatencyMap or OraLatencyMap_advanced
--
-- Luca.Canali@cern.ch, v1.2, March 2014. Original version, August 2013.
--
-- More info: see README
--

declare
  
 var_dump_wait_count  clob;
 var_dump_time_waited clob;


 var_dump_latest_wait_count varchar2(1000);
 var_dump_latest_time_waited varchar2(1000);
 var_dump_latest_time_sec number;

 var_number_iterations number;
  -- Main datatypes for data collections (1D and 2D arrays implemented with pl/sql associative arrays
 
  type t_numberarray is table of number index by pls_integer;
  type t_integerarray is table of pls_integer index by pls_integer;
  type t_integertable is table of t_integerarray index by pls_integer;      

  gc_num_bins pls_integer := &num_bins;   -- This gives the y-axis limits: gc_num_wait_bins+1 values
  -- Example: histogram data for 10 bins from 1ms to 1sec + 1 catch-all bin N. 11 for higher values

  gc_num_rows pls_integer := &num_rows;   -- This gives the x-axis limits: number of data points displayed

  g_previous_wait_count  t_numberarray; 
  g_latest_wait_count    t_numberarray;
  g_previous_time_waited t_numberarray;
  g_latest_time_waited   t_numberarray;
  g_previous_time_sec    number;
  g_latest_time_sec      number;
  g_delta_time           number;
  g_latest_iops          pls_integer;
  g_latest_wait          pls_integer;
  g_total_iops           pls_integer;
  g_total_wait           pls_integer;

  g_screen               clob;             -- screen output stored in a clob 

  g_table_wait_count  t_integertable;      -- 2D array, wait count data for the blue heat map
  g_table_time_waited t_integertable;      -- 2D array, time waited data for the yellow-red heat map
 
  -- This procedure reads from gv$event_histogram and writes new data points into revelant global variables
  ---------------------------------------
  procedure collect_latest_data_points is

      -- source of data is gv$event_histogram
      -- time waited per latency bin is estimated as wait_count*wait_time_milli*.75
      -- an additional filter is a parameter to limit data collection to one instance for example

      cursor c1_histogram_data is
          select wait_time_milli, wait_count, wait_count*wait_time_milli*.75 estimated_wait_time
          from gv$event_histogram                 
          where event='&wait_event' &instance_filter_clause
          ;   
        
      v_bin pls_integer;

  begin

      for y in 0..gc_num_bins loop        -- zero out arrays with latest data points before populating them
          g_latest_wait_count(y) := 0;    -- this allows to take care of the fact that gv$event_histogram will not 
          g_latest_time_waited(y):= 0;    -- return rows for bins that have not yet been populated
      end loop;

      -- note g_latest_time_sec restarts from 0 every hour, this is in seconds but contains decimals
      g_latest_time_sec := extract(second from systimestamp) + 60*extract(minute from systimestamp); 

      for c in c1_histogram_data loop
          v_bin := log(2,c.wait_time_milli);    -- wait_time_milli values are powers of 2 (i.e. = 1,2,4,8,..)
          if v_bin < gc_num_bins then
             g_latest_wait_count(v_bin)  := g_latest_wait_count(v_bin) + c.wait_count;   -- in RAC this sums over all instances
             g_latest_time_waited(v_bin) := g_latest_time_waited(v_bin) + c.estimated_wait_time;  
          else
             g_latest_wait_count(gc_num_bins) := g_latest_wait_count(gc_num_bins) + c.wait_count;     -- highest bin is catchall 
             g_latest_time_waited(gc_num_bins) := g_latest_time_waited(gc_num_bins) + c.estimated_wait_time;            
          end if;
      end loop;

  end collect_latest_data_points;

  -- This procedures updates the main table data structure with the new delta values
  ---------------------------------------
  procedure compute_new_state is
 
     v_delta_time number; 

  begin

      if (var_number_iterations = 0) then   -- special case, this is the first iteration
         g_delta_time := 0;                  -- g_delta_time needs to be populated as it is used to compute the sleep time
         return;                             -- nothing else to do
      end if;

      dbms_lock.sleep (&sleep_interval);     -- sleep before collecting new data, we assume this code runs under a wrapper                  
      if g_previous_time_sec <= g_latest_time_sec then
         v_delta_time := g_latest_time_sec - g_previous_time_sec;
      else
         v_delta_time := 3600 + g_latest_time_sec - g_previous_time_sec;  -- g_latest_time_sec restarts from 0 every hour
      end if;

      g_delta_time := round(v_delta_time,1);

      for y in 0..gc_num_bins loop
         g_table_wait_count(gc_num_rows)(y)  := ceil ((g_latest_wait_count(y)  - g_previous_wait_count(y)) / v_delta_time);  
         g_table_time_waited(gc_num_rows)(y) := round ((g_latest_time_waited(y) - g_previous_time_waited(y))/ v_delta_time); 
      end loop; 

  end compute_new_state;

  -- This procedures writes the main array data structures into sqlplus variables to preserve the state across executions
  ---------------------------------------
  procedure save_state is

      v_dump_wait_count clob :='';
      v_dump_time_waited clob :='';
      v_dump_latest_wait_count varchar2(1000) :='';
      v_dump_latest_time_waited varchar2(1000) :='';

  begin

      -- pack the values of the 2 state tables (wait counts and time waited) into csv lists in clob variables
      for x in 1..gc_num_rows loop         -- the oldest record (x=0) is not saved to make room for new data
          for y in 0..gc_num_bins loop
              v_dump_wait_count  := v_dump_wait_count||to_char(g_table_wait_count(x)(y))||',';
              v_dump_time_waited := v_dump_time_waited||to_char(g_table_time_waited(x)(y))||',';
          end loop;
      end loop;           

      -- pack the values of the arrays with the latest values for wait count and time waited into csv lists in varchar2 variables
      for y in 0..gc_num_bins loop
          v_dump_latest_wait_count  := v_dump_latest_wait_count  ||to_char(g_latest_wait_count(y))||',';
          v_dump_latest_time_waited := v_dump_latest_time_waited ||to_char(g_latest_time_waited(y))||',';
      end loop;

      --write the lobs in sqlplus variables to preserve them across executions of this anonymous block
      var_dump_wait_count  := v_dump_wait_count;
      var_dump_time_waited := v_dump_time_waited;
      var_dump_latest_wait_count  := v_dump_latest_wait_count;
      var_dump_latest_time_waited := v_dump_latest_time_waited;
      var_dump_latest_time_sec:= g_latest_time_sec;
      var_number_iterations := var_number_iterations +1;

  end save_state;

  -- This procedure loads data structures from sqlplus variables into the global pl/sql variables
  ---------------------------------------
  procedure load_state is

      v_dumpstring clob;
      v_pos1 pls_integer;
      v_pos2 pls_integer;

  begin

      if (var_number_iterations = 0) then   -- special case, this is the first iteration
          for x in 0..gc_num_rows loop    
               for y in 0..gc_num_bins loop  
                   g_table_wait_count(x)(y)  := 0;
                   g_table_time_waited(x)(y) := 0;
               end loop;
          end loop;
          return;                            -- nothing else to do
      end if;

      -- load wait count table (2D array)
      v_dumpstring  := var_dump_wait_count;
      v_pos1 :=1;
      for x in 0..gc_num_rows-1 loop    -- the last entry is kept empty, it will be populated later 
          for y in 0..gc_num_bins loop
              v_pos2 := instr(v_dumpstring,',',v_pos1,1);
              g_table_wait_count(x)(y) := to_number(substr(v_dumpstring,v_pos1,v_pos2-v_pos1));
              v_pos1 := v_pos2+1;
          end loop;
      end loop;           

      -- load time waited table (2D array)
      v_dumpstring  := var_dump_time_waited;
      v_pos1 :=1;
      for x in 0..gc_num_rows-1 loop    -- the last entry is kept empty, it will be populated later 
          for y in 0..gc_num_bins loop
              v_pos2 := instr(v_dumpstring,',',v_pos1,1);
              g_table_time_waited(x)(y) := to_number(substr(v_dumpstring,v_pos1,v_pos2-v_pos1));
              v_pos1 := v_pos2+1;
          end loop;
      end loop;           

     --load previous wait count measurements (1D array)
      v_dumpstring  := var_dump_latest_wait_count;
      v_pos1 :=1;
      for y in 0..gc_num_bins loop
          v_pos2 := instr(v_dumpstring,',',v_pos1,1);
          g_previous_wait_count(y) := to_number(substr(v_dumpstring,v_pos1,v_pos2-v_pos1));
          v_pos1 := v_pos2+1;
      end loop;

     --load previous time waited measurements (1D array)
      v_dumpstring  := var_dump_latest_time_waited;
      v_pos1 :=1;
      for y in 0..gc_num_bins loop
          v_pos2 := instr(v_dumpstring,',',v_pos1,1);
          g_previous_time_waited(y) := to_number(substr(v_dumpstring,v_pos1,v_pos2-v_pos1));
          v_pos1 := v_pos2+1;
      end loop;

     -- load previous timestamp
     g_previous_time_sec := var_dump_latest_time_sec;

  end load_state;

  -- use this instead of dbms_output
  -------------------------------------------------------
  procedure print_to_screen (p_string varchar2)
  is
  begin
     g_screen := g_screen || p_string ||chr(10);   -- adds the string to the buffer and a new line character
  end print_to_screen;
  
  -- print clear screen + header
  -------------------------------------------------------
  procedure print_header
  is
     v_line  varchar2(1000);
  begin
     g_screen :='';                                               -- inizialize the lob with the screen content
     v_line := chr(27)||'[0m'||chr(27)||'[2J'||chr(27)||'[H';     -- clear screen and move cursor to top line
     v_line := v_line||'OraLatencyMap v1.2 - Luca.Canali@cern.ch';   
     print_to_screen(v_line);
     print_to_screen('');       --empty line

     --print bold face and centered
     v_line := 'Heatmap representation of &wait_event wait event latency from gv$event_histogram';
     v_line := chr(27)||'[1m'||lpad(' ',(gc_num_rows+11-length(v_line))/2,' ')||v_line||chr(27)||'[0m';
     print_to_screen(v_line);

  end print_header;

  -- creates and displays a heat map for a numeric table
  -------------------------------------------------------
  procedure print_heat_map(p_table t_integertable, p_rows pls_integer, p_cols pls_integer, 
                           p_palette_type varchar2, p_graph_header varchar2, p_graph_unit varchar2, p_color_desc varchar2,
                           p_total_sum OUT NOCOPY pls_integer, p_latestcol_sum OUT NOCOPY pls_integer)
  is
     type t_scanline is table of varchar2(4000) index by pls_integer;
     v_graph_lines t_scanline;
     v_line varchar2(4000);
     v_color   pls_integer;
     v_max_val pls_integer;
     v_col_sum pls_integer;
     v_max_col_sum pls_integer;
     v_total_sum pls_integer;

    --returns the ascii escape sequence to reset the background color to normal
    function asciiescape_backtonormal return varchar2
    is
    begin
        return(chr(27)||'[0m');
    end asciiescape_backtonormal;

     --returns the ascii escape sequence to change the background color according to the token and palette values
     function asciiescape_color (p_token pls_integer, p_palette_type varchar2) return varchar2 
     is
        type t_palette is varray(7) of pls_integer;                       -- a palette of 7 colors
        v_palette_blue t_palette := t_palette(15,51,45,39,33,27,21);      -- shades of blue: white-light blue-dark blue
        v_palette_red t_palette := t_palette(15,226,220,214,208,202,196); -- white-yellow-red palette
        v_colornum pls_integer;

     begin
        if ((p_token < 0) or (p_token > 6)) then
            raise_application_error(-20001,'The color palette has 7 colors, 0<=p_token<=6, found instead:'||to_char(p_token));
        end if; 

        if (p_palette_type = 'blue') then
            v_colornum := v_palette_blue(p_token+1);                                 
        else
            v_colornum := v_palette_red(p_token+1);                                 
        end if;
        return(chr(27)||'[48;5;'||to_char(v_colornum)||'m');   --return the ascii escape sequence to change background color 
     end;
     

  -- main body of procedure print_heat_map
  begin
      
     -- compute max value of p_table(x)(y) used further on to compute the color coding scale
     -- also compute v_max_col_sum = maximum sum of values for a given column
     -- v_col_sum at the end of the loop will contain the sum of the latest values
     v_max_val := 0;
     v_max_col_sum := 0;
     p_total_sum := 0;
     for x in 0..p_rows loop    
         v_col_sum := 0;
         for y in 0..p_cols loop
             if (p_table(x)(y)) > v_max_val then
                 v_max_val := p_table(x)(y);
             end if;
             v_col_sum := v_col_sum + p_table(x)(y); 
             p_total_sum := p_total_sum + p_table(x)(y);
         end loop;
         if (v_col_sum > v_max_col_sum) then
             v_max_col_sum := v_col_sum;
         end if;
     end loop;
     p_latestcol_sum := v_col_sum;

     -- prepare the latency heat map as a sequence of raster lines v_graph_lines(y)
     for y in 0..p_cols loop
         v_graph_lines(y):='';
         for x in 0..p_rows loop
             if (p_table(x)(y) <= 0) then  --it should never be <0, but just in case we treat this case
                v_color := 0;
             elsif (p_table(x)(y) >= v_max_val) then  
                v_color := 6;
             else
                v_color := ceil((p_table(x)(y)*6 )/v_max_val);  -- normalize to range 1..6
             end if;
             v_graph_lines(y):=v_graph_lines(y) || asciiescape_color(v_color, p_palette_type) || ' ';
         end loop;
         v_graph_lines(y):=v_graph_lines(y)||asciiescape_backtonormal();
     end loop;

    -- print graph header
    print_to_screen('');    --empty line
    v_line := 'Latency bucket';
    v_line := v_line||lpad(' ',(p_rows-length(p_graph_header)-6)/2,' ')||p_graph_header;
    v_line := v_line||lpad(' ',(p_rows-length(v_line)),' ')||'Latest values';
    v_line := v_line||'    Legend';
    print_to_screen(v_line);
    v_line := asciiescape_backtonormal()||'(millisec)';
    v_line := v_line||lpad(' ',p_rows-1-length(p_graph_unit),' ')||p_graph_unit;
    print_to_screen(v_line);

    -- print body of the heatmap
    for y in 0..p_cols loop
        v_line := asciiescape_backtonormal();
        if (y = 0) then                     -- special case of the catch-all value for waits >= highest bucket 
            v_line := v_line||'>'||lpad(to_char(power(2,p_cols-1)),4,' ');
        else
            v_line := v_line||lpad(to_char(power(2,p_cols-y)),5,'.');
        end if;
        v_line := v_line||' '||v_graph_lines(p_cols-y)|| lpad(to_char(p_table(p_rows)(p_cols-y)),6,'.');
        if (y <= 6) then                                                   -- print the legend
            v_line:=v_line||asciiescape_backtonormal()||' '||asciiescape_backtonormal()||' ';
            v_line:=v_line||asciiescape_backtonormal()||' '||asciiescape_backtonormal()||' ';
            v_line:=v_line||asciiescape_color(y, p_palette_type) || ' ';
            v_line:=v_line||asciiescape_backtonormal()||' ';
            if (y = 0) then
                v_line:=v_line||to_char(ceil(v_max_val*y/6));
            else
                v_line:=v_line||'>'||to_char(ceil(v_max_val*(y-1)/6));
            end if;
        end if;
        if (y = 7) then 
            v_line:=v_line||asciiescape_backtonormal()||' '||asciiescape_backtonormal()||' ';
            v_line:=v_line||asciiescape_backtonormal()||' '||asciiescape_backtonormal()||' ';
            v_line:=v_line||'Max: '||to_char(v_max_val);           
        end if;
        if (y = p_cols) then 
            v_line:=v_line||asciiescape_backtonormal()||' '||asciiescape_backtonormal()||' ';
            v_line:=v_line||asciiescape_backtonormal()||' '||asciiescape_backtonormal()||' ';
            v_line:=v_line||'Max(Sum):';           
        end if;
        print_to_screen(v_line);
    end loop;
    
    -- print graph footer
    v_line := '      x=time, y=latency bucket, '||p_color_desc;
    v_line := v_line||lpad(' ',p_rows-length(v_line)+2,' ')||'Sum:'||lpad(to_char(v_col_sum),7,'.');
    v_line := v_line||'    '||to_char(v_max_col_sum);
    print_to_screen(v_line); 
 
  end print_heat_map;


  -- print page footer
  -------------------------------------------------------
  procedure print_footer
  is
     v_line varchar2(1000);
     v_iops pls_integer;
  begin
    print_to_screen('');
    if (g_total_iops > 0) then
        v_iops := round(g_total_wait/g_total_iops,0);
    else 
        v_iops := 0;
    end if;
    v_line := 'Average latency: '||to_char(v_iops)||' millisec. ';
    if (g_latest_iops > 0) then
        v_iops := round(g_latest_wait/g_latest_iops,0);
    else 
        v_iops := 0;
    end if;
    v_line := v_line||'Latest value of average latency: '||to_char(v_iops)||' millisec.';
    print_to_screen(v_line);
    v_line := 'Sample num: '||to_char(var_number_iterations)||', latest sampling interval: '||to_char(g_delta_time)||' sec.';
    v_line := v_line ||' Date: '|| to_char(sysdate, 'DD-MON-YYYY hh24:mi:ss');
    print_to_screen(v_line);
    v_line := 'Wait event: &wait_event'; 
    if ('&wait_event' = 'db file sequential read') then
        v_line := v_line || ' (e.g. use to analyze random read latency).'; 
    elsif ('&wait_event' = 'log file sync') then
        v_line := v_line || ' (e.g. use to analyze commit response time).'; 
    end if;
    print_to_screen(v_line);

  end print_footer;

-------------------------------------------------------
-- main body starts here below
-------------------------------------------------------
begin
    var_number_iterations :=0;
    var_dump_wait_count :='';
    var_dump_time_waited :='';
    -- read the status of system as stored in sqlplus variables
    load_state;             

    -- measure latest data point of quantity to be monitored: this reads from gv$event_histogram
    collect_latest_data_points; 

    -- updates data structures using the latest data points and previous status as input
    compute_new_state;      

    -- save status of system into sqlplus variables
    save_state;             

    -- print page header
    print_header;            

    -- print heat map of number of waits per latency bucket.
    -- darker shades of blue for higher values (color is 3rd dimension to the plot)
    print_heat_map (g_table_wait_count,gc_num_rows,gc_num_bins,'blue','Frequency Heatmap: events per sec','(N#/sec)', 
                    'color=wait frequency (IOPS)', g_total_iops, g_latest_iops); 

    -- print heat map of estimated time waited per latency bucket. 
    -- Yellow-red palette (color is 3rd dimension to the plot)
    print_heat_map (g_table_time_waited,gc_num_rows,gc_num_bins,'red','Intensity Heatmap: time waited per sec','(millisec/sec)', 
                    'color=time waited', g_total_wait, g_latest_wait); 

    -- print page footer
    print_footer;            

    -- g_screen is saved in a sqlplus variable for later printing
    :var_screen := g_screen;

end;
/
print var_screen


