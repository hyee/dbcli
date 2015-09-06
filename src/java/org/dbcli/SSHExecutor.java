package org.dbcli;


import com.jcraft.jsch.*;
import jline.console.completer.Completer;
import jline.internal.Ansi;

import java.io.*;
import java.nio.channels.CompletionHandler;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

/**
 * Created by Will on 2015/9/1.
 */
public class SSHExecutor {
    public static String TERMTYPE;
    public static int COLS = 800;
    public static int ROWS = 60;
    public Session session;
    public String linePrefix = "";
    public String host;
    public String user;
    public int port;
    public String password;
    public String prompt;
    public ChannelShell shell;
    JSch ssh;
    PipedOutputStream shellWriter;
    PipedInputStream pipeIn;
    Printer pr;
    HashMap<Integer, Object[]> forwards;
    HashMap<String, Channel> channels;
    boolean isLogin = false;
    String lastLine;
    boolean isStart = false;
    boolean isEnd = true;
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

    public void output(String message, boolean newLine) {
        StringBuilder sb = new StringBuilder((linePrefix + message).length());
        if (newLine) sb.append(linePrefix);
        for (int i = 0; i < message.length(); i++) {
            char c = message.charAt(i);
            if (c == '\r') continue;
            sb.append(c);
            if (c == '\n') sb.append(linePrefix);
        }
        if (!newLine) System.out.print(sb.toString());
        else System.out.println(sb.toString());
        System.out.flush();
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
            session.setDaemonThread(true);
            session.setServerAliveInterval((int) TimeUnit.SECONDS.toMillis(10));
            session.setServerAliveCountMax(10);
            session.setTimeout(0);
            session.setInputStream(System.in);
            session.setOutputStream(System.out);
            session.connect();
            session.setUserInfo((UserInfo) new SSHUserInfo("jsch"));
            this.host = host;
            this.port = port;
            this.user = user;
            this.password = password;
            forwards = new HashMap<>();
            channels = new HashMap<>();
            isLogin = true;
            setLinePrefix(linePrefix);
            shell = (ChannelShell) session.openChannel("shell");
            pipeIn = new PipedInputStream();
            shellWriter = new PipedOutputStream(pipeIn);
            pr = new Printer();
            pr.reset(true);
            //FileOutputStream fileOut = new FileOutputStream( outputFileName );
            shell.setInputStream(pipeIn);
            shell.setOutputStream(pr);
            shell.setEnv("TERM", TERMTYPE = TERMTYPE == "none" ? "ansi" : TERMTYPE);
            shell.setPty(true);
            shell.setPtyType(TERMTYPE = TERMTYPE == "none" ? "ansi" : TERMTYPE, COLS, ROWS, 1400, 900);
            shell.connect();
            waitCompletion();
        } catch (Exception e) {
            throw e;
        }
    }

    public void setTermType(String termType, int cols, int rows) {
        TERMTYPE = termType.intern();
        COLS = cols;
        ROWS = rows;
    }

    public boolean isConnect() {
        return shell == null ? false : session.isConnected();
    }

    private void closeShell() {
        try {
            prompt=null;
            pr.close();
            shellWriter.close();
            shell.getInputStream().close();
            shell.disconnect();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public void testConnect() throws Exception {
        if (isConnect() || !isLogin) return;
        {
            output("Connection is lost, try to re-connect ...", true);
            closeShell();
        }
        connect(this.host, this.port, this.user, this.password, this.linePrefix);
    }

    public void close() throws Exception {
        closeShell();
        session.disconnect();
        isLogin = false;
    }

    public void setLinePrefix(String linePrefix) {
        this.linePrefix = linePrefix == null ? "" : linePrefix;
    }

    public int setForward(int localPort, Integer remotePort, String remoteHost) throws Exception {
        testConnect();
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

    public void enterShell(boolean isEnter) {

    }

    public void waitCompletion() throws Exception {
        long wait = 50L;
        //shell.setInputStream(System.in);
        while (!isEnd && !shell.isClosed()) {
            int ch = Console.in.read(wait);
            while (ch >= 0) {
                shellWriter.write(ch);
                --wait;
                ch = Console.in.read(1L);
            }
            if(wait<50L) {
                shellWriter.flush();
                wait=50L;
            }
        }
        if (shell.isClosed()) {
            this.close();
        } else prompt = pr.getPrompt();

        //shell.setInputStream(pipeIn);
    }

    public String getLastLine(String command, boolean isWait) throws Exception {
        pr.reset(true);
        shellWriter.write(command.getBytes());
        shellWriter.flush();
        if (isWait) waitCompletion();
        return lastLine == null ? null : lastLine.replaceAll("[\r\n]+$", "");
    }

    public void exec(String command) throws Exception {
        pr.reset(false);
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
            output(m, true);
        }
    }

    class Printer extends OutputStream {
        StringBuilder sb;
        char lastChar;
        Pattern p = Pattern.compile("[\27\33]\\[[\\d;]+[mK]");

        boolean ignoreMessage;

        public Printer() {
            reset(false);
        }

        @Override
        public void write(int i) throws IOException {
            char c = (char) i;
            //if (i == 0 || c=='\r') c=' ';
            sb.append(c);
            if (c == '\n') {
                flush();
                isStart = false;
                sb.setLength(0);
            } else isEnd = (lastChar == '$' || lastChar == '>' || lastChar == '#') && c == ' ';
            lastChar = c;
        }

        public String getPrompt() {
            return sb.toString() == "" ? null : sb.toString();
        }

        public void reset(boolean ignoreMessage) {
            sb = new StringBuilder(128);
            lastChar = '\0';
            isEnd = false;
            isStart = true;
            this.ignoreMessage = ignoreMessage;
            lastLine = null;
        }

        @Override
        public synchronized void flush() throws IOException{
            if (isStart || isEnd || sb.length() == 0) return;
            lastLine = sb.toString();
            if (!ignoreMessage) {
                if (TERMTYPE == "none") {
                    Console.writer.write(Ansi.stripAnsi(lastLine));
                    Console.writer.flush();
                } else {
                    System.out.print(lastLine);
                    System.out.flush();
                }
            }
            isStart = false;
            sb.setLength(0);
        }

        @Override
        public void close() {
            reset(false);
            sb = null;
            //printer.close();
        }
    }
}
