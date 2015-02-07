package org.dbcli;

import java.sql.CallableStatement;
import java.sql.SQLException;
import java.util.concurrent.Callable;

/**
 * Created by Will on 2015/2/5.
 */
public class Caller implements Callable<String> {
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