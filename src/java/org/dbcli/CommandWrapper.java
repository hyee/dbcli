package org.dbcli;

import com.naef.jnlua.LuaState;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.util.Scanner;

import static java.lang.System.*;

/**
 * Program to demostrate use of communicating with a child process using three threads and ProcessBuilder.
 *
 * @author Roedy Green, Canadian Mind Products
 * @version 1.0 2009-04-07 initial version
 * @since 2009-04-07
 */
final public class CommandWrapper {
    private final LuaState lua;

    public CommandWrapper(LuaState lua) {
        this.lua=lua;
    }



    public void create(String cmd) throws Exception{
        // Boomerang exchoes input to output.
        final ProcessBuilder pb = new ProcessBuilder(cmd).redirectErrorStream(true);
        final Process p = pb.start();
        final Scanner in = new Scanner(p.getInputStream());
        OutputStream os = p.getOutputStream();

        // spawn two threads to handle I/O with child while we wait for it to complete.


        new Thread(new Sender(os)).start();
        new Thread(new Receiver(lua,p.getInputStream())).start();
        out.println("Child done");
        // at this point the child is complete.  All of its output may or may not have been processed however.
        // The Receiver thread will continue until it has finished processing it.
        // You must close the streams even if you never use them!  In this case the threads close is and os.
        p.getErrorStream().close();
    }
}

/**
 * thread to send output to the child.
 */
final class Sender implements Runnable {
    /**
     * e.g. \n \r\n or \r, whatever system uses to separate lines in a text file. Only used inside multiline fields. The
     * file itself should use Windows format \r \n, though \n by itself will alsolineSeparator work.
     */
    private static final String lineSeparator = System.getProperty("line.separator");

    /**
     * stream to send output to child on
     */
    private final OutputStream os;

    /**
     * constructor
     *
     * @param os stream to use to send data to child.
     */
    Sender(OutputStream os) {
        this.os = os;
    }

    /**
     * method invoked when Sender thread started.  Feeds dummy data to child.
     */
    public void run() {
        try {
            final BufferedWriter bw = new BufferedWriter(new OutputStreamWriter(os), 50 /* keep small for tests */);
            for (int i = 99; i >= 0; i--) {
                bw.write("There are " + i + " bottles of beer on the wall, " + i + " bottles of beer.");
                bw.write(lineSeparator);
            }
            bw.close();
        } catch (IOException e) {
            throw new IllegalArgumentException("IOException sending data to child process.");
        }
    }
}

final class Receiver implements Runnable {
    private final Scanner in;
    private final LuaState lua;

    Receiver(LuaState lua,InputStream in){
        this.lua=lua;
        this.in= new Scanner(in);
    };

    private void print(String message) {
        lua.getGlobal("print");
        lua.pushString(message);
        lua.call(1,0);
    }

    public void run() {
        try {
            while (in.hasNextLine()) print(in.nextLine());
        } catch (Exception e) {
            print(e.getMessage());
        }
    }
}


/**
 * thread to read output from child
 */
