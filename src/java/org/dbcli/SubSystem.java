package org.dbcli;

import com.zaxxer.nuprocess.NuAbstractProcessHandler;
import com.zaxxer.nuprocess.NuProcess;
import com.zaxxer.nuprocess.NuProcessBuilder;
import com.zaxxer.nuprocess.windows.NuKernel32;

import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.regex.Pattern;

public class SubSystem {
    NuProcessBuilder pb;
    volatile NuProcess process;
    ByteBuffer writer;
    Pattern p;
    volatile String lastLine;
    volatile Boolean isWaiting = false;
    volatile Boolean isBreak = false;
    volatile Boolean isEOF = false;
    volatile Boolean isPrint = false;
    volatile String lastPrompt = "";
    volatile String prevPrompt;
    //return null means the process is terminated
    CountDownLatch lock = new CountDownLatch(1);

    public SubSystem() {
    }

    public SubSystem(String promptPattern, String cwd, String[] command, Map env) {
        try {
            pb = new NuProcessBuilder(Arrays.asList(command), env);
            pb.setCwd(new File(cwd).toPath());
            p = Pattern.compile(promptPattern, Pattern.CASE_INSENSITIVE + Pattern.DOTALL);
            ProcessHandler handler = new ProcessHandler();
            pb.setProcessListener(handler);
            process = pb.start();
            writer = ByteBuffer.allocateDirect(32767);
            writer.order(ByteOrder.nativeOrder());
            //Respond to the ctrl+c event
            Interrupter.listen(this, new EventCallback() {
                @Override
                public void call(Object... o) {
                    isBreak = true;
                    if (lock != null) lock.countDown();
                }
            });
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
            throw e;
        }
    }

    public static boolean setEnv(String name, String value) {
        return NuKernel32.SetEnvironmentVariable(name, value);
    }

    public static SubSystem create(String pattern, String cwd, String[] command, Map env) {
        return new SubSystem(pattern, cwd, command, env);
    }

    public Boolean isPending() {
        return process.hasPendingWrites();
    }

    void print(String buff) {
        if (isPrint && !isBreak) {
            Console.writer.print(buff);
            Console.writer.flush();
        }
    }

    synchronized void write(byte[] b) {
        writer.clear();
        writer.put(b);
        writer.flip();
        process.writeStdin(writer);
    }

    public void waitCompletion() throws Exception {
        //System.out.println(process.GetConsoleMode());
        StringBuilder buff = new StringBuilder();
        long wait = 150L;
        int prev = 0;
        //process.setConsoleMode(NuKernel32.ENABLE_ECHO_INPUT | NuKernel32.ENABLE_LINE_INPUT);
        while (isWaiting && process != null) {
            if (isBreak) {
                //isBreak = false;
                //lastPrompt = prevPrompt;

                //process.sendCtrlEvent(NuWinNT.HANDLER_ROUTINE.CTRL_C_EVENT);
                close();
                break;
            }
            if (wait > 50) {//Waits 0.5 sec for the prompt and then enters into interactive mode
                --wait;
                Thread.sleep(5);
            } else {
                int ch = Console.input.read(10L);
                while (ch > 0) {
                    if (!(ch == 10 && prev == 13) && !(ch == 13 && prev == 10)) {
                        prev = ch;
                        //if (ch == 13) ch = 10; //Convert '\r' as '\n'
                        buff.append((char) ch);
                        --wait;
                    }
                    ch = Console.input.read(10L);
                }
                if (wait < 50L) {
                    write(buff.toString().getBytes());
                    print(buff.toString());
                    buff.setLength(0);
                    wait = 60L; //Waits 0.05 sec
                }
            }
        }
        //process.setConsoleMode(process.GetConsoleMode() & NuKernel32.ENABLE_ECHO_INPUT);
    }

    public String execute(String command, Boolean isPrint, Boolean isBlockInput) throws Exception {
        try {
            this.isPrint = isPrint;
            this.lastPrompt = null;
            isWaiting = true;
            isBreak = false;
            if (isBlockInput) lock = new CountDownLatch(1);
            if (command != null) {
                lastLine = null;
                write((command.replaceAll("[\r\n]+$", "") + "\n").getBytes());
            }
            if (!isBlockInput)
                waitCompletion();
            else {
                lock.await();
                if (isBreak) close();
            }
            if (this.prevPrompt == null) this.prevPrompt = this.lastPrompt;
            return lastPrompt;
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
            throw e;
        } finally {
            isWaiting = false;
        }
    }

    public String execute(String command, Boolean isPrint) throws Exception {
        return execute(command, isPrint, false);
    }

    public String getLastLine(String command) throws Exception {
        execute(command, false);
        return lastLine == null ? null : lastLine.replaceAll("[\r\n]+$", "");
    }

    public void close() {
        Interrupter.listen(this, null);
        isWaiting = false;
        isBreak = false;
        if (process == null) return;
        process.destroy(true);
        process = null;
        lastPrompt = null;
        lock.countDown();
    }

    class ProcessHandler extends NuAbstractProcessHandler {
        private NuProcess nuProcess;
        private char lastChar;
        private StringBuilder sb = new StringBuilder();

        @Override
        public void onStart(NuProcess nuProcess) {
            this.nuProcess = nuProcess;
        }

        @Override
        public void onStderr(ByteBuffer buffer, boolean closed) {
            onStdout(buffer, closed);
            isWaiting = false;
            lock.countDown();
        }

        @Override
        public void onStdout(ByteBuffer buffer, boolean closed) {
            byte[] bytes = new byte[buffer.remaining()];
            buffer.get(bytes);

            lastChar = '\n';
            isEOF = closed;
            isWaiting = true;

            for (byte c : bytes) {
                lastChar = (char) c;
                sb.append(lastChar);
                if (lastChar == '\n') {
                    lastLine = sb.toString();
                    print(lastLine);
                    sb.setLength(0);
                }
            }

            if (lastChar != '\n' && !isEOF) {
                String line = sb.toString();
                sb.setLength(0);
                if (p.matcher(line).find()) {
                    lock.countDown();
                    isWaiting = false;
                    lastPrompt = line;
                } else {
                    print(line);
                }
            }
        }

        @Override
        public void onExit(int statusCode) {
            close();
        }
    }
}
