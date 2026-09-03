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
import java.util.concurrent.atomic.AtomicInteger;
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
    volatile CountDownLatch lock = new CountDownLatch(1);
    volatile CountDownLatch responseLock = null;
    volatile boolean running = false;
    volatile boolean killRequested = false;
    final AtomicInteger ctrlCCount = new AtomicInteger(0);

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
                    if (!running) {
                        //Idle or interactive relay: keep the original break-out behavior.
                        isBreak = true;
                        CountDownLatch lk = lock, rl = responseLock;
                        if (lk != null) lk.countDown();
                        if (rl != null) rl.countDown();
                        if (lastPrompt == null) lastPrompt = prevPrompt;
                        ctrlCCount.set(0);
                        return;
                    }
                    //Busy running a command: never fake completion, count strikes instead.
                    if (killRequested) return;
                    int n = ctrlCCount.incrementAndGet();
                    if (n >= 3) {
                        ctrlCCount.set(0);
                        killRequested = true;
                        Console.writer.add("Killing the subprocess...\n");
                        Console.writer.flush();
                        CountDownLatch lk = lock, rl = responseLock;
                        if (lk != null) lk.countDown();
                        if (rl != null) rl.countDown();
                    } else {
                        Console.writer.add("Command still running. Press CTRL+C again (" + n + "/3) to kill the subprocess.\n");
                        Console.writer.flush();
                    }
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
        return process != null && process.hasPendingWrites();
    }

    StringBuffer buff = new StringBuffer(1024);

    void print(String buff) {
        if (isCache) {
            synchronized (this.buff) {
                this.buff.append(buff);
            }
        } else if (isPrint && !isBreak) {
            Console.writer.add(buff);
            Console.writer.flush();
        }
    }

    String getBuff(boolean wait) throws Exception {
        if (wait) waitCompletion(false);
        synchronized (this.buff) {
            final String result = buff.toString();
            buff.setLength(0);
            return result;
        }
    }

    synchronized void write(byte[] b) throws IOException {
        if (process == null) throw new IOException("The process is broken!");
        writer.clear();
        writer.put(b);
        writer.flip();
        process.writeStdin(writer);
    }

    public void waitCompletion(boolean printBuff) throws Exception {
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
                    if (printBuff) {
                        final String buf = getBuff(false);
                        write(buf.getBytes());
                        print(buf);
                    }
                    wait = 60L; //Waits 0.05 sec
                }
            }
        }
        //process.setConsoleMode(process.GetConsoleMode() & NuKernel32.ENABLE_ECHO_INPUT);
    }

    public String execute(String command, Boolean isPrint, Boolean isBlockInput) throws Exception {
        try {
            determinPromptCount = 12;
            this.isPrint = isPrint;
            this.lastPrompt = null;
            isWaiting = true;
            isBreak = false;
            killRequested = false;
            ctrlCCount.set(0);
            if (isBlockInput == null) {
                responseLock = new CountDownLatch(1);
                isCache = true;
            } else if (isBlockInput != null && isBlockInput) {
                lock = new CountDownLatch(1);
                if (isPrint) isCache = false;
            } else if (!isCache) {
                isCache = true;
            }
            if (command != null) {
                lastLine = null;
                write((command.replaceAll("[\r\n]+$", "") + "\n").getBytes());
            }
            if (isBlockInput == null) {
                running = true;
                responseLock.await();
                running = false;
                if (killRequested) {
                    close();
                    return null;
                }
                responseLock = null;
                return null;
            } else if (isBlockInput) {
                running = true;
                lock.await();
                running = false;
                if (killRequested) close();
            } else {
                waitCompletion(true);
            }
            if (this.prevPrompt == null) this.prevPrompt = this.lastPrompt;
            return lastPrompt;
        } catch (Exception e) {
            Loader.getRootCause(e).printStackTrace();
            throw e;
        } finally {
            running = false;
            ctrlCCount.set(0);
            isWaiting = isBlockInput == null;
        }
    }

    public String executeInterval(String command, long interval, int count, Boolean isPrint, PreparedStatement prep) throws Exception {
        try {
            this.isPrint = isPrint;
            this.lastPrompt = null;
            isWaiting = true;
            isBreak = false;
            killRequested = false;
            ctrlCCount.set(0);
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
                    running = true;
                    lock.await();
                    running = false;
                    if (killRequested) close();
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

                    write(c);
                    responseLock = new CountDownLatch(1);
                    if (prep != null) {
                        try (ResultSet rs = prep.executeQuery()) {
                            if (rs.next()) {
                                if (result == null) {
                                    prep.setFetchSize(1);
                                    cols = rs.getMetaData().getColumnCount();
                                    result = new String[cols];
                                }
                                for (int j = 1; j <= cols; j++) result[j - 1] = rs.getString(j);
                            }
                        }
                    }
                    running = true;
                    responseLock.await();
                    running = false;
                    responseLock = null;
                    if (killRequested) {
                        close();
                        break;
                    }
                    if (result != null) print(String.join("/", result) + '\n');

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
            running = false;
            ctrlCCount.set(0);
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
            return getBuff(false);
        } finally {
            isCache = false;
        }
    }

    public String getLinesInterval(String command, long interval, int count, PreparedStatement prep) throws Exception {
        isCache = true;
        try {
            buff.setLength(0);
            executeInterval(command, interval, count, false, prep);
            return getBuff(false);
        } finally {
            isCache = false;
        }
    }

    public synchronized void close() {
        Interrupter.listen(this, null);
        isEOF = true;
        isWaiting = false;
        isBreak = true;
        running = false;
        if (process == null) return;
        process.destroy(true);
        process = null;
        lastPrompt = null;
        CountDownLatch rl = responseLock, lk = lock;
        if (rl != null) rl.countDown();
        if (lk != null) lk.countDown();
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
                        NuProcess pr = process;
                        if (pr == null) break;
                        if (pr.hasPendingWrites() || !writeLock.tryLock()) continue;
                        try (Closeable clo = writeLock::unlock) {
                            if (currLine != null) line = currLine;
                            else {
                                line = sb.toString();
                                currLine = line;
                            }
                            isPrompt = !pr.hasPendingWrites() && p.matcher(line).find();
                            if (counter > 0) {
                                if (isPrompt) {
                                    counter = counter + 1;
                                    CountDownLatch rl = responseLock;
                                    if (counter >= determinPromptCount || rl != null) {
                                        sb.setLength(0);
                                        lastPrompt = line;
                                        isWaiting = false;
                                        counter = 0;
                                        currLine = null;
                                        (rl != null ? rl : lock).countDown();
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
            buffer.flip();
            return false;
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
            //Only release the latch at stderr EOF, so a mid-command stderr write won't truncate captured output.
            if (closed) lock.countDown();
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
                    //Mask to unsigned byte; (char)c would sign-extend bytes>=0x80 and corrupt non-ASCII output.
                    lastChar = (char) (c & 0xFF);
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
