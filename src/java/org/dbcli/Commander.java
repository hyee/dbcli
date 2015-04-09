package org.dbcli;


import com.zaxxer.nuprocess.NuAbstractProcessHandler;
import com.zaxxer.nuprocess.NuProcess;
import com.zaxxer.nuprocess.NuProcessBuilder;
import jline.console.KeyMap;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.PrintWriter;
import java.nio.ByteBuffer;
import java.util.LinkedList;
import java.util.concurrent.Future;

/**
 * Created by Will on 2015/4/3.
 */
public class Commander {
    PrintWriter writer;
    NuProcessBuilder pb;
    NuProcess nu;
    ProcessHandler handler;
    Runnable waiter;
    Console console;

    public Commander(PrintWriter writer, String cmd, Console console) {
        this.writer = writer;
        this.console = console;
        waiter = new pendingListner();
        pb = new NuProcessBuilder(cmd);
        handler = new ProcessHandler();
        pb.setProcessListener(handler);
        nu=pb.start();
        System.out.println(cmd);
    }

    public void exec(String cmd) {
        try {
            ByteBuffer buffer = ByteBuffer.wrap((cmd+"\n").getBytes());
            buffer.flip();
            nu.writeStdin(buffer);

            //Future task = console.threadPool.submit(waiter);
            //console.setEvents(new KeyListner(),new char[]{ '*'});
            //task.get();
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            console.setEvents(null,null);
        }
    }

    public void close() {
        handler.close();
    }

    private class pendingListner implements Runnable {
        public void run() {
            try {
                for (; ; ) {
                    if (handler.isPending()) Thread.sleep(300L);
                    else break;}
            } catch (InterruptedException e) {
            }
        }
    }

    class KeyListner implements ActionListener {
        @Override
        public void actionPerformed(ActionEvent e) {
            try {
                handler.clear();
                handler.sendKey(e.getActionCommand());
            } catch (Exception err) {
                err.printStackTrace();
            }
        }
    }

    class ProcessHandler extends NuAbstractProcessHandler {
        private NuProcess nuProcess;
        private ByteBuffer keyBuffer = ByteBuffer.allocate(10);
        private LinkedList<String> cmdList = new LinkedList<String>();

        @Override
        public void onStart(NuProcess nuProcess) {
            this.nuProcess = nuProcess;
        }



        public void clear() {
            cmdList.clear();
        }

        public void close() {
            nuProcess.destroy();
        }

        //Send key event
        public void sendKey(String ch) {
            clear();
            keyBuffer.put(ch.getBytes());
            keyBuffer.flip();
            nuProcess.writeStdin(keyBuffer);
        }

        //Send command
        public void write(String stack) {
            cmdList.add(stack + "\n");
            //nuProcess.hasPendingWrites();
            nuProcess.wantWrite();
        }

        public synchronized Boolean isPending() {
            return nuProcess.hasPendingWrites();
        }

        @Override
        public boolean onStdinReady(ByteBuffer buffer) {
            if (!cmdList.isEmpty()) {
                String cmd = cmdList.poll();
                buffer.put(cmd.getBytes());
                buffer.flip();
            }
            return !cmdList.isEmpty();
        }

        @Override
        public void onStdout(ByteBuffer buffer) {
            if (buffer == null) {
                nuProcess.wantWrite();
                return;
            };
            int remaining=buffer.remaining();
            byte[] bytes = new byte[buffer.remaining()];
            buffer.get(bytes);
            System.out.print(new String(bytes));
            nuProcess.wantWrite();
            // We're done, so closing STDIN will cause the "cat" process to exit
            //nuProcess.closeStdin();
        }

        @Override
        public void onStderr(ByteBuffer buffer) {
            if (buffer != null) {
                this.onStdout(buffer);
            } else nuProcess.wantWrite();
        }
    }
}
