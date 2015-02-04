package org.dbcli;

import java.sql.CallableStatement;
import java.sql.SQLException;
import java.util.concurrent.Callable;

/**
 * Created by Will on 2015/2/1.
 */
class Caller implements Callable<String> {
    private final CallableStatement stmt;

    public Caller(CallableStatement p) {
        this.stmt = p;
    }

    public String call() {
        try {
            return this.stmt.execute() ? "true" : "false";
        } catch (SQLException e) {
            try {
                this.stmt.close();
            } catch (SQLException e1) {
            }
            return e.toString();
        }
    }
}

public class DbExecutor implements Runnable {
    private final Callable task;
    private final DbCallback callback;

    public DbExecutor(CallableStatement p, DbCallback c) {
        this.callback=c;
        this.task=new Caller(p);
    }

    @Override
    public void run() {
        String result = null;
        try {
            result = (String)this.task.call();
        } catch (Exception e) {
            result = e.getMessage();
        }
        this.callback.complete(result);
    }
}
