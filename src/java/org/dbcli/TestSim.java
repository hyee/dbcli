package org.dbcli;

import oracle.jdbc.pool.OracleDataSource;

import javax.sql.DataSource;
import javax.xml.transform.Result;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public class TestSim {
    public static String user;
    public static String pwd;
    public static String url;
    public static CountDownLatch latch1;
    public static CountDownLatch latch2;
    public static OracleDataSource ds;

    /*
    java -cp d:\dbcli\oracle\ojdbc8.jar;. TestSim admin welcome1 127.0.0.1:9999/gaowei 2 60 100 "begin run_sim; end;"
    */
    public static void main(String[] args) throws Exception {
        if (args.length < 7) {
            System.out.println("parameters: <user> <password> <url> <threads> <run secs> <think ms> <SQL command>");
        }
        user = args[0];
        pwd = args[1];
        url = args[2];
        final int threads = Integer.valueOf(args[3]);
        final int secs = Integer.valueOf(args[4]);
        final int think=Integer.valueOf(args[5]);
        String cmd = args[6];
        latch1 = new CountDownLatch(threads);
        latch2 = new CountDownLatch(threads);
        ds = new OracleDataSource();
        ds.setUser(user);
        ds.setPassword(pwd);
        ds.setURL("jdbc:oracle:thin:@" + url);
        final CountDownLatch exitLatch=new CountDownLatch(1);
        try(Connection conn = ds.getConnection()) {
            AtomicInteger counter = new AtomicInteger();
            ExecutorService service = Executors.newFixedThreadPool(threads);
            for (int i = 0; i < threads; i++) {
                final int thread_id = i;
                service.submit(() -> {
                    boolean counted = false;
                    try (final Connection con = ds.getConnection()) {
                        con.setAutoCommit(true);
                        latch1.countDown();
                        counted = true;
                        latch1.await();
                        long ms = System.currentTimeMillis() + secs * 1000;
                        String sql = cmd.replace(":threads", String.valueOf(threads)).replace(":thread_id", String.valueOf(thread_id));
                        while (System.currentTimeMillis() < ms) {
                            try (PreparedStatement prep = con.prepareStatement(sql)) {
                                prep.setFetchSize(1024);
                                boolean isQuery = prep.execute();
                                if(isQuery) {
                                    ResultSet rs=prep.getResultSet();
                                    while(rs.next()) ;
                                }
                                counter.incrementAndGet();
                            } catch (Exception e1) {
                                throw e1;
                            }
                            if(exitLatch.await(5,TimeUnit.MICROSECONDS)) {
                                return;
                            }
                            Thread.sleep(Math.max(1, think / 3 + ((Double) (Math.random() * think * 2 / 3)).intValue()));
                        }
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    } finally {
                        if (!counted) latch1.countDown();
                        latch2.countDown();
                    }
                });
            }
            DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
            System.out.println(LocalDateTime.now().format(formatter) + ": Creating " + threads + " connections...");
            latch1.await();
            int begin_snap;
            try (PreparedStatement prep = conn.prepareStatement("select dbms_workload_repository.create_snapshot() from dual")) {
                ResultSet rs = prep.executeQuery();
                rs.next();
                begin_snap = rs.getInt(1);
            }

            System.out.println(LocalDateTime.now().format(formatter) + ": All " + threads + " connections are ready, starting workloads...");
            int curr = 0;
            while (!latch2.await(5, TimeUnit.SECONDS)) {
                final int curr1 = counter.get();
                System.out.println(LocalDateTime.now().format(formatter) + ": Current QPS: " + (curr1 - curr) / 5);
                curr = curr1;
            }
            System.out.println(LocalDateTime.now().format(formatter) + ": All workloads are done, total queries : " + counter.get());
            int end_snap;
            try (PreparedStatement prep = conn.prepareStatement("select dbms_workload_repository.create_snapshot() from dual")) {
                ResultSet rs = prep.executeQuery();
                rs.next();
                end_snap = rs.getInt(1);
            }
            service.shutdown();
            System.out.println(LocalDateTime.now().format(formatter) + ": Snapshot:" + begin_snap + " - " + end_snap);
        } finally {
            exitLatch.countDown();
        }
    }

    public class Config {
        public DataSource ds;
        public Integer threads;
        public Integer duration;
        public Integer thinkTime;
        public String[] SQLs;
    }
}
