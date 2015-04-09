package org.dbcli;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.util.Scanner;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

final public class CommandWrapper {
    BufferedWriter stdin;
    InputStream stdout;
    private Future stdinThread;
    private Future stdoutThread;
    private PrintWriter writer;
    private StringBuilder input;
    ProcessBuilder pb;
    StringBuilder buffer;

    public CommandWrapper(PrintWriter writer) {
        this.writer = writer;
    }

    public void create(String cmd) throws Exception {
        pb = new ProcessBuilder(cmd).redirectErrorStream(true);
        final Process p = pb.start();
        stdout = p.getInputStream();
        stdin = new BufferedWriter(new OutputStreamWriter(p.getOutputStream()),1024);
        buffer = new StringBuilder(1024);
        input = new StringBuilder(1024);
        stdinThread = Console.threadPool.scheduleWithFixedDelay(new Sender(), 300L, 200L, TimeUnit.MILLISECONDS);
        stdoutThread = Console.threadPool.schedule(new Receiver(stdout), 300, TimeUnit.MILLISECONDS);
    }

    public void Terminate() {
        pb.directory();
    }

    public void execute(String cmd) {

    }

    private class KeyListner implements ActionListener {
        @Override
        public void actionPerformed(ActionEvent e) {
            try {
                int ch=Character.codePointAt(e.getActionCommand(),0);
                //Ctrl+E to abort
                if(ch==5) {
                } else synchronized (input) {
                    input.appendCodePoint(ch);
                };
            } catch (Exception err) {
                //err.printStackTrace();
            }
        }
    }

    class Sender implements Runnable {
        public void run() {
            try {
                if(input.length()>0) {
                    synchronized (input) {
                        for (int i = 0; i < input.length(); i++) {
                            stdin.write(input.codePointAt(i));
                            stdin.flush();
                            //Thread.currentThread().sleep(200L);
                        }
                        input.setLength(0);
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    class Receiver implements Runnable {
        private final Scanner in;

        Receiver(InputStream in) {
            this.in = new Scanner(in);
        }

        public void run() {
            try {
                while (in.hasNextLine()) buffer.append(in.nextLine()).append('\n');
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
}