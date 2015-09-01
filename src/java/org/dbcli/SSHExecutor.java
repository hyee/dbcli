package org.dbcli;

import com.jcraft.jsch.Channel;
import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;

import java.io.InputStream;
import java.util.HashMap;

/**
 * Created by Will on 2015/9/1.
 */
public class SSHExecutor {
    JSch ssh;
    Session session;
    String linePrefix = "";
    String host;
    String user;
    int port;
    String password;
    HashMap<Integer, Object[]> forwards;
    HashMap<String, Channel> channels;
    boolean isLogin = false;

    public SSHExecutor() {
    }

    public SSHExecutor(String host, int port, String user, String password, String linePrefix) throws Exception {
        connect(host, port, user, password, linePrefix);
    }

    public void output(String message) {
        System.out.println(linePrefix + message.replaceAll("\n", linePrefix + "\n"));
        System.out.flush();
    }

    public void connect(String host, int port, String user, String password, String linePrefix) throws Exception {
        try {
            ssh = new JSch();
            session = ssh.getSession(user, host, port);
            session.setPassword(password);
            session.setConfig("StrictHostKeyChecking", "no");
            session.setConfig("compression.s2c", "zlib@openssh.com,zlib,none");
            session.setConfig("compression.c2s", "zlib@openssh.com,zlib,none");
            session.setConfig("compression_level", "9");
            session.setServerAliveInterval(60);
            session.connect();
            this.host = host;
            this.port = port;
            this.user = user;
            this.password = password;
            forwards = new HashMap<>();
            channels = new HashMap<>();
            isLogin = true;
            setLinePrefix(linePrefix);

        } catch (Exception e) {
            e.printStackTrace();
            throw e;
        }
    }

    public boolean isConnect() {
        return session.isConnected();
    }

    public void testConnect() throws Exception {
        if (isConnect() || !isLogin) return;
        output("Connection is lost, try to re-connect ...");
        connect(this.host, this.port, this.user, this.password, this.linePrefix);
    }

    public void close() {
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
            if (remotePort == null) return -1;
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

    public void exec(String command) throws Exception {
        ChannelExec channel = (ChannelExec) getChannel("exec");
        channel.setCommand(command);
        channel.setInputStream(null);
        channel.setErrStream(null);

        InputStream in = channel.getInputStream();
        channel.connect();
        byte[] tmp = new byte[1024];
        while (true) {
            while (in.available() > 0) {
                int i = in.read(tmp, 0, 1024);
                if (i < 0) break;
                output(new String(tmp, 0, i));
            }
            if (channel.isClosed()) {
                if (in.available() > 0) continue;
                break;
            }
            try {
                Thread.sleep(300);
            } catch (Exception ee) {
            }
        }
    }
}