package org.dbcli;

import com.zaxxer.nuprocess.NuAbstractProcessHandler;
import com.zaxxer.nuprocess.NuProcess;
import com.zaxxer.nuprocess.NuProcessBuilder;

import java.awt.event.ActionEvent;
import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Created by 1506428 on 11/18/2015.
 */
public class SubSystem {
    NuProcessBuilder pb;
    NuProcess process;
    StringBuilder sb;
    ByteBuffer writer;
    Pattern p;
    volatile Boolean isWaiting = false;
    volatile Boolean isEOF = false;
    String lastPrompt = "";

    public SubSystem() {
    }

    public SubSystem(String pattern, String cwd, String[] command, Map env) {
        sb = new StringBuilder();
        pb = new NuProcessBuilder(Arrays.asList(command), env);
        pb.setCwd(new File(cwd).toPath());
        p = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE + Pattern.DOTALL);
        ProcessHandler handler = new ProcessHandler();
        pb.setProcessListener(handler);
        process = pb.start();
        writer = ByteBuffer.allocateDirect(32767);
        writer.order(ByteOrder.nativeOrder());
        //Respond to the ctrl+c event
        Interrupter.listen(process, new InterruptCallback() {
            @Override
            public void interrupt(ActionEvent e) throws Exception {
                if (isWaiting) SendKey((byte) 3);
                synchronized (sb) {
                    isWaiting = false;
                    sb.setLength(0);
                }
            }
        });
    }

    public static SubSystem create(String pattern, String cwd, String[] command, Map env) {
        return new SubSystem(pattern, cwd, command, env);
    }

    public void SendKey(byte c) {
        writer.clear();
        writer.put(c);
        writer.flip();
        process.writeStdin(writer);
    }

    public Boolean isPending() {
        return process.hasPendingWrites();
    }

    void print(String buff, Boolean isPrint) {
        if (isPrint) {
            Console.writer.print(buff);
            Console.writer.flush();
        }
    }

    //return null means the process is terminated
    public String write(String command, Boolean isPrint) throws Exception {
        try {
            String remain = null;
            int counter = 0;
            if (process == null) return null;
            isWaiting = true;
            isEOF = false;
            if (command != null) {
                writer.clear();
                writer.put(command.getBytes());
                writer.flip();
                process.writeStdin(writer);
            }
            while (true) {
                if (process == null) return null;
                if (!isWaiting) {
                    print("\n",true);
                    sb.setLength(0);
                    return lastPrompt;
                }
                if (sb.length() > 0) {
                    counter = 0;
                    String buff;
                    synchronized (sb) {
                        buff = sb.toString();
                        sb.setLength(0);
                    }
                    if (buff.endsWith("\n")) {
                        print(buff, isPrint);
                        remain = null;
                    } else {
                        int index = buff.lastIndexOf("\n");
                        if (index != -1) print(buff.substring(0, index+1), isPrint);
                        remain = buff.substring(index + 1);
                        Matcher m = p.matcher(remain);
                        if (m.find()) {
                            Thread.currentThread().sleep(5);
                            if(sb.length()==0) {
                                lastPrompt = remain;
                                return remain;
                            }
                        }
                        print(remain, isPrint);
                    }
                } else if ((remain != null && ++counter > 200)) {
                    return "";
                }
                Thread.currentThread().sleep(10);
            }
        } catch (Exception e) {
            e.printStackTrace();
            throw e;
        } finally {
            isWaiting = false;
        }
    }

    public void close() {
        isWaiting = false;
        if (process == null) return;
        process.destroy(true);
        process = null;
    }

    class ProcessHandler extends NuAbstractProcessHandler {
        private NuProcess nuProcess;

        @Override
        public void onStart(NuProcess nuProcess) {
            this.nuProcess = nuProcess;
        }

        @Override
        public void onStderr(ByteBuffer buffer, boolean closed) {
            onStdout(buffer,closed);
        }

        @Override
        public void onStdout(ByteBuffer buffer, boolean closed) {
            isEOF = closed;
            if (!isWaiting) {
                buffer.flip();
                return;
            }
            byte[] bytes = new byte[buffer.remaining()];
            // You must update buffer.position() before returning (either implicitly,
            // like this, or explicitly) to indicate how many bytes your handler has consumed.
            buffer.get(bytes);

            synchronized (sb) {
                sb.append(new String(bytes));
            }
        }

        @Override
        public void onExit(int statusCode) {
            close();
        }
    }
}
