package org.dbcli;

import com.sun.jna.Native;
import com.zaxxer.nuprocess.NuAbstractProcessHandler;
import com.zaxxer.nuprocess.NuProcess;
import com.zaxxer.nuprocess.NuProcessBuilder;

import java.io.Closeable;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.Charset;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.*;
import java.util.concurrent.locks.ReentrantLock;
import java.util.regex.Pattern;

public class SubSystem {
    NuProcessBuilder pb;
    volatile NuProcess process;
    ByteBuffer writer;
    Pattern p;
    Thread monitorThread;
    volatile String lastLine;
    volatile Boolean isWaiting = false;
    volatile Boolean isBreak = false;
    volatile Boolean isEOF = false;
    volatile Boolean isPrint = false;
    volatile String lastPrompt = "";
    volatile String prevPrompt;
    volatile Boolean isCache = false;
    volatile int determinPromptCount = 12;
    //return null means the process is terminated
    CountDownLatch lock = new CountDownLatch(1);
    CountDownLatch responseLock = null;
    ArrayBlockingQueue<byte[]> queue = new ArrayBlockingQueue(1);

    public SubSystem() {
        Native.setProtected(true);
    }

    public SubSystem(String promptPattern, String cwd, String[] command, Map env) {
        try {
            Map e = new TreeMap(System.getenv());
            e.putAll(env);
            //if (e.get("PATH") == null && e.get("Path") != null) e.put("PATH", e.get("Path"));
            pb = new NuProcessBuilder(Arrays.asList(command), e);
            pb.setCwd(new File(cwd).toPath());
            p = Pattern.compile(promptPattern, Pattern.CASE_INSENSITIVE + Pattern.DOTALL);
            ProcessHandler handler = new ProcessHandler();
            pb.setProcessListener(handler);
            process = pb.start();

            writer = ByteBuffer.allocateDirect(1048576);
            writer.order(ByteOrder.nativeOrder());
            monitorThread = new Thread(() -> {
                try {
                    process.waitFor(0, TimeUnit.SECONDS);
                } catch (InterruptedException e1) {
                } finally {
                    try {
                        process.destroy(true);
                    } catch (Exception e1) {
                    }
                    process = null;
                }
            });
            monitorThread.setDaemon(true);
            monitorThread.start();
            //Respond to the ctrl+c event

            Interrupter.listen(this, new EventCallback() {
                @Override
                public void call(Object... o) {
                    isBreak = true;
                    if (lock != null) lock.countDown();
                    if (responseLock != null) responseLock.countDown();
                    if (lastPrompt == null) lastPrompt = prevPrompt;
                    queue.clear();
                }
            });
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
            throw e;
        }
    }

    public static boolean setEnv(String name, String value) {
        return false;// NuKernel32.SetEnvironmentVariable(name, value);
    }

    public static SubSystem create(String pattern, String cwd, String[] command, Map env) {
        return new SubSystem(pattern, cwd, command, env);
    }

    public Boolean isClosed() {
        return process == null;
    }

    public Boolean isPending() {
        return process.hasPendingWrites();
    }

    StringBuffer buff = new StringBuffer(1024);

    void print(String buff) {
        if (isCache) {
            this.buff.append(buff);
        } else if (isPrint && !isBreak) {
            Console.writer.add(buff);
            Console.writer.flush();
        }
    }

    synchronized void write(byte[] b) throws IOException {
        if (process == null) throw new IOException("The process is broken!");
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
            if (isBreak) return;
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
            queue.clear();
            determinPromptCount = 12;
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

    public String executeInterval(String command, long interval, int count, Boolean isPrint, PreparedStatement prep) throws Exception {
        try {
            queue.clear();
            this.isPrint = isPrint;
            this.lastPrompt = null;
            isWaiting = true;
            isBreak = false;
            long current;
            command = command.replaceAll("[\r\n]+$", "") + "\n";
            final byte[] c;
            if (interval <= 0) {
                determinPromptCount = Math.min(Math.max(100, count), 1000);
                lastLine = null;
                if (!isBreak) System.out.println("    Start to execute, please wait...");
                StringBuilder builder = new StringBuilder();
                for (int i = 0; i < count; i++) {
                    builder.append(command);
                }
                c = builder.toString().getBytes();
                write(c);
                if (!isBreak) {
                    lock = new CountDownLatch(1);
                    System.out.println("    Fetching output, please wait...");
                    lock.await();
                }
            } else {
                c = command.getBytes();
                int cols = 0;
                String[] result = null;
                for (int i = 1; i <= count; i++) {
                    current = System.currentTimeMillis() + interval;
                    lastLine = null;
                    if (isBreak) break;

                    if (i % 10 == 0)
                        System.out.println("    Executing " + command.substring(0, c.length - 1) + ": round #" + i);
                    responseLock = new CountDownLatch(1);
                    write(c);
                    if (prep != null) try (ResultSet rs = prep.executeQuery()) {
                        if (rs.next()) {
                            if (result == null) {
                                prep.setFetchSize(1);
                                cols = rs.getMetaData().getColumnCount();
                                result = new String[cols];
                            }
                            for (int j = 1; j <= cols; j++) result[j - 1] = rs.getString(j);
                        }
                    }
                    responseLock.await();
                    if (result != null) print(String.join("/", result) + '\n');
                    responseLock = null;
                    current -= System.currentTimeMillis();
                    if (current > 0 && i < count) Thread.sleep(current);
                }
            }
            if (this.prevPrompt == null) this.prevPrompt = this.lastPrompt;
            return lastPrompt;
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
            throw e;
        } finally {
            if (prep != null) prep.close();
            responseLock = null;
            determinPromptCount = 12;
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

    public String getLines(String command) throws Exception {
        isCache = true;
        try {
            buff.setLength(0);
            execute(command, false, true);
            return buff.toString();
        } finally {
            isCache = false;
        }
    }

    public String getLinesInterval(String command, long interval, int count, PreparedStatement prep) throws Exception {
        isCache = true;
        try {
            buff.setLength(0);
            executeInterval(command, interval, count, false, prep);
            return buff.toString();
        } finally {
            isCache = false;
        }
    }

    public void close() {
        Interrupter.listen(this, null);
        isEOF = true;
        isWaiting = false;
        isBreak = true;
        if (process == null) return;
        process.destroy(true);
        process = null;
        lastPrompt = null;
        if (responseLock != null) responseLock.countDown();
        lock.countDown();
        threadPool.shutdownNow();
    }

    ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(1);

    class ProcessHandler extends NuAbstractProcessHandler {
        private final ReentrantLock writeLock = new ReentrantLock();
        private volatile char lastChar;
        private final StringBuffer sb = new StringBuffer();
        private volatile int counter = 0;
        private volatile String currLine = null;
        Runnable checker = new Runnable() {
            @Override
            public void run() {
                String line;
                boolean isPrompt;
                while (!isEOF) try {
                    Thread.sleep(counter == 1 ? 1L : 8L);
                    if (lastChar != '\n' && sb.length() > 0) {
                        if (process.hasPendingWrites() || !writeLock.tryLock()) continue;
                        try (Closeable clo = writeLock::unlock) {
                            if (currLine != null) line = currLine;
                            else {
                                line = sb.toString();
                                currLine = line;
                            }
                            isPrompt = !process.hasPendingWrites() && p.matcher(line).find();
                            if (counter > 0) {
                                if (isPrompt) {
                                    counter = counter + 1;
                                    if (counter >= determinPromptCount || responseLock != null) {
                                        sb.setLength(0);
                                        lastPrompt = line;
                                        isWaiting = false;
                                        counter = 0;
                                        currLine = null;
                                        (responseLock != null ? responseLock : lock).countDown();
                                    }
                                } else counter = 0;
                            } else if (isPrompt) {
                                counter = 1;
                            } else {
                                sb.setLength(0);
                                currLine = null;
                                print(line);
                            }
                        } catch (Exception e1) {
                        }
                    }
                } catch (InterruptedException e2) {
                    break;
                }
            }
        };
        Thread t = new Thread(checker);

        @Override
        public boolean onStdinReady(ByteBuffer buffer) {
            byte[] c = queue.poll();
            if (c == null || isBreak) {
                buffer.flip();
                return false;
            }
            buffer.put(c);
            buffer.flip();
            return true;
        }

        @Override
        public void onPreStart(NuProcess nuProcess) {
            t.setDaemon(true);
            t.start();
        }

        @Override
        public void onStderr(ByteBuffer buffer, boolean closed) {
            if (process != null) onStdout(buffer, closed);
            else {
                byte[] bytes = new byte[buffer.remaining()];
                buffer.get(bytes);
                System.out.println(new String(bytes, Charset.defaultCharset()));
            }
            isWaiting = false;
            lock.countDown();
        }


        @Override
        public void onStdout(ByteBuffer buffer, boolean closed) {
            byte[] bytes = new byte[buffer.remaining()];
            buffer.get(bytes);
            writeLock.lock();
            try (Closeable clo = writeLock::unlock) {
                currLine = null;
                counter = 0;
                isEOF = closed;
                isWaiting = true;

                if (isBreak) {
                    sb.setLength(0);
                    return;
                }
                for (byte c : bytes) {
                    lastChar = (char) c;
                    sb.append(lastChar);
                    if (lastChar == '\n') {
                        lastLine = sb.toString();
                        print(lastLine);
                        sb.setLength(0);
                    }
                }
                if (closed && sb.length() > 0) {
                    String line = sb.toString();
                    sb.setLength(0);
                    print(line);
                }
            } catch (Exception e1) {
                e1.printStackTrace();
            }
        }

        @Override
        public void onExit(int statusCode) {
            isEOF = true;
            close();
            t = null;
        }
    }
}
