/*[[  This file is part of demos for "Latch Mutex and beyond blog". Usage: @@NAME <address>
     Andrey S. Nikolaev (Andrey.Nikolaev@rdtex.ru)
 
     http://AndreyNikolaev.wordpress.com
 
     Compute the latch statistics
     --[[
        @check_version: 11.0={}
     --]]
]]*/
set feed off
DECLARE
    i          NUMBER;
    Samples    NUMBER := 300;
    SampleFreq NUMBER := 1 / 10; -- Hz;
    Nw         NUMBER;
    laddr      RAW(8);
    CURSOR lstat(laddr_ RAW) IS /* latch statistics */
        SELECT kslltnum LATCH#, kslltwgt GETS, kslltwff MISSES, kslltwsl SLEEPS, ksllthst0 SPIN_GETS,
               kslltwtt latch_wait_time, kslltcnm child#
        FROM   sys.x$kslltr_children
        WHERE  kslltaddr = hextoraw(laddr_)
        UNION ALL
        SELECT kslltnum LATCH#, kslltwgt GETS, kslltwff MISSES, kslltwsl SLEEPS, ksllthst0 SPIN_GETS,
               kslltwtt latch_wait_time, 0 child#
        FROM   sys.x$kslltr_parent
        WHERE  kslltaddr = hextoraw(laddr_);
    Lstat1  lstat%ROWTYPE;
    Lstat2  lstat%ROWTYPE;
    dgets   NUMBER;
    dmisses NUMBER;
    rho     NUMBER;
    eta     NUMBER;
    lambda  NUMBER;
    kappa   NUMBER;
    W       NUMBER;
    sigma   NUMBER;
    error_  VARCHAR2(100) := '';
    lname   VARCHAR2(100);
    level_  NUMBER;
    dtime   NUMBER;
    U       NUMBER := 0;
    ssleeps NUMBER;
    S       NUMBER;
    params  VARCHAR2(2000) := '';
BEGIN
    SELECT MAX(addr)
    INTO   laddr
    FROM   (SELECT addr, NAME FROM v$latch UNION ALL SELECT addr, NAME FROM v$latch_children)
    WHERE  addr = HEXTORAW(:V1);

    IF laddr IS NULL THEN
        dbms_output.put_line('Cannot find target latch, usage: latchstats <address|latch_name>');
        RETURN;
    END IF;
    /*     CPU count */
    SELECT VALUE INTO Nw FROM v$parameter WHERE NAME = 'cpu_count';
    IF Nw != 1 THEN
        eta := Nw / (Nw - 1);
    ELSE
        eta    := 1;
        Error_ := Error_ || ' Single CPU configuration ';
    END IF;
    Nw := 0;
    /*     Beginning latch statistics */
    dtime := DBMS_UTILITY.GET_TIME();
    OPEN Lstat(laddr);
    FETCH Lstat
        INTO Lstat1;
    IF Lstat%NOTFOUND THEN
        raise_application_error(-20001, 'No latch at 0x' || laddr);
    END IF;
    CLOSE Lstat;
    /*     Sampling */
    FOR i IN 1 .. Samples LOOP
        /*   number of pocesses waiting for the latch */
        FOR SAMPLE IN (SELECT COUNT(decode(ksllawat, '00', NULL, 1)) wat
                       FROM   sys.x$ksupr
                       WHERE  ksllawat = laddr) LOOP
            Nw := Nw + Sample.wat;
        END LOOP;
        /*    Is latch busy  */
        FOR Hold IN (SELECT 1 hold FROM sys.x$ksuprlat WHERE ksuprlat = laddr) LOOP
            U := U + 1;
            EXIT;
        END LOOP;
    
        DBMS_LOCK.sleep(SampleFreq);
    END LOOP;
    /*     End latch statistics */
    OPEN Lstat(laddr);
    FETCH Lstat
        INTO Lstat2;
    CLOSE Lstat;
    dtime := (DBMS_UTILITY.GET_TIME() - dtime) * 0.01; /* delta time in seconds */
    /*     Compute derived statistics */
    dgets   := (lstat2.gets - lstat1.gets);
    dmisses := (lstat2.misses - lstat1.misses);
    IF (dgets > 0) THEN
        rho := dmisses / dgets;
    ELSE
        dbms_output.put_line('No gets activity for this latch');
        return;
    END IF;
    Nw     := Nw / Samples;
    U      := U / Samples;
    lambda := dgets / dtime;
    W      := (lstat2.latch_wait_time - lstat1.latch_wait_time) / dtime * 1.E-6; /* wait time in seconds */
    SELECT kslldnam, kslldlvl INTO lname, level_ FROM sys.x$kslld WHERE indx = lstat2.latch#;
    /* S:=eta*rho/lambda; */
    S := U / lambda;
    IF (dmisses > 0) THEN
        kappa := (lstat2.sleeps - lstat1.sleeps) / dmisses;
        sigma := (lstat2.spin_gets - lstat1.spin_gets) / dmisses;
    ELSE
        error_ := Error_ || ' Delta MISSES=' || dmisses;
        kappa  := NULL;
        sigma  := NULL;
    END IF;
    IF (kappa > 0) THEN
        ssleeps := (kappa + sigma - 1) / kappa;
    ELSE
        error_  := Error_ || '  Sigma=' || sigma;
        ssleeps := NULL;
    END IF;

    IF (length(Error_) > 0) THEN
        DBMS_OUTPUT.put_LINE(' Error: ' || error_);
    END IF;
    DBMS_OUTPUT.put_LINE(chr(10) || 'Latch statistics  for  0x' || laddr || '   "' || lname ||'"  level#=' || level_ || '   child#=' || lstat2.child#);
    DBMS_OUTPUT.put_LINE('Requests rate:       lambda=' || to_char(lambda, '999999.9') || ' Hz');
    DBMS_OUTPUT.put_LINE('Miss /get:              rho=' || to_char(rho, '9.999999'));
    DBMS_OUTPUT.put_LINE('Est. Utilization:   eta*rho=' || to_char(eta * rho, '9.999999'));
    DBMS_OUTPUT.put_LINE('Sampled   Utilization:    U=' || to_char(U, '9.999999'));
    DBMS_OUTPUT.put_LINE('Slps /Miss:      kappa=' || to_char(kappa, '9.999999'));
    DBMS_OUTPUT.put_LINE('Wait_time/sec:       W=' || to_char(W, '999.999999'));
    DBMS_OUTPUT.put_LINE('Sampled queue length L=' || to_char(Nw, '999.999999'));
    DBMS_OUTPUT.put_LINE('Spin_gets/miss:  sigma=' || to_char(sigma, '9.999999'));
    DBMS_OUTPUT.put_LINE(chr(10) || 'Derived statistics:');
    DBMS_OUTPUT.put_LINE('Secondary sleeps ratio =' || to_char(ssleeps, '9.99EEEE'));
    DBMS_OUTPUT.put_LINE('Avg latch holding time =' || to_char(S * 1000000, '999999.9') || ' us');
    DBMS_OUTPUT.put_LINE('.        sleeping time =' || to_char(W / lambda * 1000000, '999999.9') ||' us');
    DBMS_OUTPUT.put_LINE('.  avg latch free wait =' || to_char(W / (kappa * rho * lambda) * 1000000, '999999.9') || ' us');
    DBMS_OUTPUT.put_LINE('.             miss rate=' || to_char(rho * lambda, '999999.9') || ' Hz');
    DBMS_OUTPUT.put_LINE('.           waits rate =' || to_char(kappa * rho * lambda, '999999.9') ||' Hz');
    DBMS_OUTPUT.put_LINE('.   spin inefficiency k=' || to_char(kappa / (1 + kappa * rho), '9.999999'));
    /* latch parameters */
    FOR Param IN (SELECT ksppinm, ksppstvl
                  FROM   sys.x$ksppi x
                  JOIN   sys.x$ksppcv
                  USING  (indx)
                  WHERE  ksppinm LIKE '\_latch\_class%' ESCAPE '\'
                  OR     ksppinm IN ('_spin_count',
                                     '_enable_reliable_latch_waits',
                                     '_latch_miss_stat_sid',
                                     '_ultrafast_latch_statistics')
                  ORDER  BY ksppinm) LOOP
        params := params || Param.ksppinm || '=' || Param.ksppstvl || ' ';
    END LOOP;
    DBMS_OUTPUT.put_LINE(chr(10) || 'Latch related parameters:' || chr(10) || params);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.put_LINE(chr(10) || 'Error raised:' || SQLERRM);
        DBMS_OUTPUT.put_LINE(DBMS_UTILITY.FORMAT_CALL_STACK);
        DBMS_OUTPUT.put_LINE('----- ' || chr(10) || 'LADDR= 0x' || rawtohex(laddr) || ' dtime=' || dtime || ' Nw= ' || Nw || ' U=' || U);
        DBMS_OUTPUT.put_LINE('gets=' || lstat2.gets || '-' || lstat1.gets || '=' || dgets || ' misses=' || lstat2.misses || '-' || lstat1.misses || '=' || dmisses);
        DBMS_OUTPUT.put_LINE('sleeps=' || lstat2.sleeps || '-' || lstat1.sleeps || '=' || (lstat2.sleeps - lstat1.sleeps) || ' spin_gets=' || lstat2.spin_gets || '-' || lstat1.spin_gets || '=' || (lstat2.spin_gets - lstat1.spin_gets));
        DBMS_OUTPUT.put_LINE('rho=' || rho || ' lambda=' || lambda || ' kappa= ' || kappa || ' sigma=' || sigma);
END;
/