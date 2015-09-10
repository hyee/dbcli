package org.dbcli;


import com.jcraft.jsch.*;
import jline.console.completer.Completer;
import jline.internal.Ansi;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.CompletionHandler;
import java.nio.charset.Charset;
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
    PrintWriter writer;
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
            writer=new PrintWriter((TERMTYPE!="none")?new OutputStreamWriter(System.out,Console.charset):Console.writer);
            shell.setInputStream(pipeIn);
            shell.setOutputStream(pr);
            shell.setEnv("TERM", TERMTYPE == "none" ? "ansi" : TERMTYPE);
            shell.setPty(true);
            shell.setPtyType(TERMTYPE == "none" ? "ansi" : TERMTYPE, COLS, ROWS, 1400, 900);
            shell.connect();
            waitCompletion();
            session.sendKeepAliveMsg();
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
        if(shell==null) return false;
        if(!shell.isConnected()) {
            close();
            return false;
        }
        return true;
    }

    private void closeShell() {
        try {
            prompt=null;
            if(pr!=null) pr.close();
            if(shellWriter!=null) shellWriter.close();
            if(shell!=null) {
                shell.getInputStream().close();
                shell.disconnect();
                shell=null;
            }
        } catch (Exception e) {
            //e.printStackTrace();
        }
    }


    public void close() {
        closeShell();
        session.disconnect();
        isLogin = false;
    }

    public void setLinePrefix(String linePrefix) {
        this.linePrefix = linePrefix == null ? "" : linePrefix;
    }

    public int setForward(int localPort, Integer remotePort, String remoteHost) throws Exception {
        if(!isConnect()) return -1;
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
            System.out.println("Message from UserInfo: "+m);
        }
    }

    class Printer extends OutputStream {
        ByteBuffer buf=ByteBuffer.allocateDirect(1000000);
        StringBuilder sb1= new StringBuilder(128);
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
            buf.put((byte)i);
            sb1.append(c);
            if (c == '\n') {
                lastLine=sb1.toString();
                flush();
                isStart = false;
                buf.clear();
                sb1.setLength(0);
            } isEnd = (lastChar == '$' || lastChar == '>' || lastChar == '#') && c == ' ';
            lastChar = c;
        }

        public String getPrompt() {
            return sb1.length() == 0 ? null : p.matcher(sb1.toString()).replaceAll("");
        }

        public void reset(boolean ignoreMessage) {
            buf.clear();
            sb1.setLength(0);
            lastChar = '\0';
            isEnd = false;
            isStart = true;
            this.ignoreMessage = ignoreMessage;
            lastLine = null;
        }

        @Override
        public synchronized void flush()  {
                if (isStart || isEnd || buf.position() == 0) return;
                int pos=buf.position();
                buf.flip();
                byte[] b=new byte[pos];
                buf.get(b);
                String line = new String(b);
                isStart = false;
                buf.clear();
                if (!ignoreMessage) {
                    if (TERMTYPE == "none") line=p.matcher(line).replaceAll("");
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