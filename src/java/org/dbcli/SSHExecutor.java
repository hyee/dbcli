package org.dbcli;

import com.jcraft.jsch.*;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.CompletionHandler;
import java.util.HashMap;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

/**
 * Created by Will on 2015/9/1.
 */
public class SSHExecutor {
    public static String TERMTYPE;
    public static int COLS = 800;
    public static int ROWS = 60;
    static HashMap<Integer, Object[]> forwards = new HashMap<>();
    public Session session;
    public String linePrefix = "";
    public String host;
    public String user;
    public int port;
    public String password;
    public String prompt;
    public ChannelShell shell;
    PrintWriter writer;
    JSch ssh;
    PipedOutputStream shellWriter;
    PipedInputStream pipeIn;
    Printer pr;
    HashMap<String, Channel> channels;
    String lastLine;
    volatile boolean isStart = false;
    volatile boolean isEnd = true;
    volatile boolean isWaiting = false;
    volatile boolean isBreak = false;
    CompletionHandler completer = new CompletionHandler() {
        @Override
        public void completed(Object o, Object o2) {

        }

        @Override
        public void failed(Throwable throwable, Object o) {

        }
    };

    public SSHExecutor() {
    }

    public SSHExecutor(String host, int port, String user, String password, String linePrefix) throws Exception {
        connect(host, port, user, password, linePrefix);
    }

    public void connect(String host, int port, String user, final String password, String linePrefix) throws Exception {
        try {
            ssh = new JSch();
            session = ssh.getSession(user, host, port);
            session.setPassword(password);
            session.setConfig("StrictHostKeyChecking", "no");
            session.setConfig("PreferredAuthentications", "password,publickey,keyboard-interactive");
            session.setConfig("compression.s2c", "zlib@openssh.com,zlib,none");
            session.setConfig("compression.c2s", "zlib@openssh.com,zlib,none");
            session.setConfig("compression_level", "9");
            session.setConfig("ServerAliveInterval", "10");
            //session.set
            session.setDaemonThread(true);
            session.setServerAliveInterval((int) TimeUnit.SECONDS.toMillis(10));
            session.setServerAliveCountMax(10);
            session.setTimeout(0);
            session.connect();
            session.setUserInfo(new SSHUserInfo("jsch"));
            this.host = host;
            this.port = port;
            this.user = user;
            this.password = password;
            channels = new HashMap<>();
            setLinePrefix(linePrefix);
            shell = (ChannelShell) session.openChannel("shell");
            pipeIn = new PipedInputStream();
            shellWriter = new PipedOutputStream(pipeIn);
            pr = new Printer();
            pr.reset(true);
            writer = Console.writer;
            Interrupter.listen("SSHExecutor", new EventCallback() {
                @Override
                public void interrupt(Object... e) throws Exception {
                    isBreak = true;
                }
            });
            shell.setInputStream(pipeIn);
            shell.setOutputStream(pr);
            shell.setPty(true);
            shell.setPtyType(TERMTYPE == "none" ? "ansi" : TERMTYPE, COLS, ROWS, 0, 0);
            shell.connect();
            waitCompletion();
        } catch (Exception e) {
            throw e;
        }
    }

    public void setEnv(String name, String value) {

    }

    public void setTermType(String termType, int cols, int rows) throws Exception {
        TERMTYPE = termType.intern();
        COLS = cols;
        ROWS = rows;
        if (isConnect()) {
            shell.setPtySize(COLS, ROWS, 0, 0);
            exec("export TERM=" + (TERMTYPE == "none" ? "ansi" : TERMTYPE));
        }
    }

    public boolean isConnect() {
        if (shell == null) return false;
        if (!shell.isConnected()) {
            close();
            return false;
        }
        return true;
    }

    public void close() {
        try {
            prompt = null;
            isWaiting = false;
            if (pr != null) pr.close();
            if (shellWriter != null) shellWriter.close();
            if (shell != null) shell.disconnect();
            if (session != null) session.disconnect();
        } catch (Exception e) {
            //Loader.getRootCause(e).printStackTrace();
        }
    }

    public void setLinePrefix(String linePrefix) {
        this.linePrefix = linePrefix == null ? "" : linePrefix;
    }

    public int setForward(int localPort, Integer remotePort, String remoteHost) throws Exception {
        if (forwards.containsKey(localPort)) {
            session.delPortForwardingL(localPort);
            forwards.remove(localPort);
        }
        if (remotePort == null) return -1;
        int assignPort = session.setPortForwardingL(localPort, remoteHost == null ? host : remoteHost, remotePort);
        forwards.put(assignPort, new Object[]{remotePort, remoteHost == null ? host : remoteHost});
        return assignPort;
    }

    protected Channel getChannel(String channelType) throws Exception {
        String type = channelType.intern();
        if (channels.containsKey(type) && channels.get(type).isConnected()) return channels.get(type);
        Channel channel = session.openChannel(type);
        channels.put(type, channel);
        return channel;
    }

    public void waitCompletion() throws Exception {
        long wait = 150L;
        isWaiting = true;
        int prev = 0;
        while (!isEnd && !shell.isClosed()) {
            if (isBreak) {
                isBreak = false;
                shellWriter.write(3);
                shellWriter.flush();
            }
            if (wait > 50) {
                --wait;
                Thread.sleep(5);
            } else {
                int ch = Console.in.read(10L);
                while (ch >= 0) {
                    if (!(ch == 10 && prev == 13) && !(ch == 13 && prev == 10)) {
                        prev = ch;
                        if (ch == 13) ch = 10; //Convert '\r' as '\n'
                        shellWriter.write(ch);
                        --wait;
                    }
                    ch = Console.in.read(10L);
                }
                if (wait < 50L) {
                    shellWriter.flush();
                    wait = 60L;
                }
            }
        }
        if (shell.isClosed()) close();
        else prompt = pr.getPrompt();
        isWaiting = false;
    }

    public String getLastLine(String command, boolean isWait) throws Exception {
        pr.reset(true);
        shellWriter.write(command.getBytes());
        shellWriter.flush();
        if (isWait) waitCompletion();
        return lastLine == null ? null : lastLine.replaceAll("[\r\n]+$", "");
    }

    public void exec(String command) throws Exception {
        isBreak = false;
        pr.reset(false);
        if (command.charAt(command.length() - 1) != '\n') command = command + "\n";
        shellWriter.write(command.getBytes());
        shellWriter.flush();
        waitCompletion();
    }

    class SSHUserInfo implements UserInfo {
        private String passphrase = null;

        public SSHUserInfo(String passphrase) {
            super();
            this.passphrase = passphrase;
        }

        public String getPassphrase() {
            return passphrase;
        }

        public String getPassword() {
            return null;
        }

        public boolean promptPassphrase(String pass) {
            return false;
        }

        public boolean promptPassword(String pass) {
            return true;
        }

        public boolean promptYesNo(String arg0) {
            return false;
        }

        public void showMessage(String m) {
            System.out.println(m);
        }
    }

    class Printer extends OutputStream {
        ByteBuffer buf = ByteBuffer.allocateDirect(1000000);
        StringBuilder sb = new StringBuilder(128);
        char lastChar;
        Pattern p = Pattern.compile("\33\\[[\\d\\;]+[mK]");
        boolean ignoreMessage;

        public Printer() {
            buf.order(ByteOrder.nativeOrder());
            reset(false);
        }

        @Override
        public void write(int i) throws IOException {
            char c = (char) i;
            buf.put((byte) i);
            sb.append(c);
            if (c == '\n') {
                lastLine = sb.toString();
                flush();
                isStart = false;
                buf.clear();
                sb.setLength(0);
            }
            isEnd = (lastChar == '$' || lastChar == '>' || lastChar == '#') && c == ' ';
            lastChar = c;
        }

        public String getPrompt() {
            return sb.length() == 0 ? null : p.matcher(sb.toString()).replaceAll("");
        }

        public void reset(boolean ignoreMessage) {
            buf.clear();
            sb.setLength(0);
            lastChar = '\0';
            isEnd = false;
            isStart = true;
            this.ignoreMessage = ignoreMessage;
            lastLine = null;
        }

        @Override
        public synchronized void flush() {
            if (isStart || isEnd || buf.position() == 0) return;
            int pos = buf.position();
            buf.flip();
            byte[] b = new byte[pos];
            buf.get(b);
            String line = new String(b);
            isStart = false;
            buf.clear();
            if (!ignoreMessage) {
                if (TERMTYPE == "none") line = p.matcher(line).replaceAll("");
                writer.print(line);
                writer.flush();
            }
        }

        @Override
        public void close() {
            reset(false);
        }
    }
}