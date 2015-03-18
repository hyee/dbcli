package org.dbcli;

import javax.swing.plaf.TableHeaderUI;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Command line run executor
 * Executed command line and return the final result
 */
class CommandExecutor {
    // TAG
    private static final String TAG = CommandExecutor.class.getSimpleName();
    // Final
    private static final String BREAK_LINE = "\n";
    private static final int BUFFER_LENGTH = 128;
    private static final byte[] BUFFER = new byte[BUFFER_LENGTH];
    private static final Lock LOCK = new ReentrantLock();
    // ProcessBuilder
    private static final ProcessBuilder PRC = new ProcessBuilder();

    // Class value
    private final Process mProcess;
    private final int mTimeout;
    private final long mStartTime;

    // Result
    private final StringBuilder mResult;

    // Stream
    private InputStream mInStream;
    private InputStream mErrStream;
    private OutputStream mOutStream;
    private InputStreamReader mInStreamReader = null;
    private BufferedReader mInStreamBuffer = null;
    private Thread processThread;

    private boolean isRunning;

    private boolean isDone;

    protected synchronized void stopThread()
    {
        isRunning=false;
    }

    protected synchronized boolean isRun()
    {
        return isRunning;
    }

    private CommandExecutor(Process process, int timeout) {
        // Init
        this.mTimeout = timeout;
        this.mStartTime = System.currentTimeMillis();
        this.mProcess = process;
        // Get
        mOutStream = process.getOutputStream();
        mInStream = process.getInputStream();
        mErrStream = process.getErrorStream();

        // In
        if (mInStream != null) {
            mInStreamReader = new InputStreamReader(mInStream);
            mInStreamBuffer = new BufferedReader(mInStreamReader, BUFFER_LENGTH);
        }

        mResult = new StringBuilder();

        if (mInStream != null) {
            // Start read thread
            processThread = new Thread(TAG) {


                @Override
                public void run() {
                    startRead();
                }
            };
            processThread.setDaemon(true);
            processThread.start();
        }
    }

    private void read() {
        String str;

        // Read data
        try {
            while (this.isRunning && (str = mInStreamBuffer.readLine()) != null) {
                mResult.append(str);
                mResult.append(BREAK_LINE);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void startRead() {
        // While to end
        while (isRun()) {
            try {
                mProcess.exitValue();
                //read last
                read();
                break;
            } catch (IllegalThreadStateException e) {
                read();
            }
            sleepIgnoreInterrupt(50);
        }

        // Read end
        int len;
        if (isRunning && mInStream != null) {
            try {
                while (isRunning && true) {
                    len = mInStream.read(BUFFER);
                    if (len <= 0) break;
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }

        isDone = true;
        isRunning = false;

    }

    private void close() {
        // Out
        if (mOutStream != null) {
            try {
                mOutStream.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
            mOutStream = null;
        }
        // Err
        if (mErrStream != null) {
            try {
                mErrStream.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
            mErrStream = null;
        }
        // In
        if (mInStream != null) {
            try {
                mInStream.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
            mInStream = null;
        }
        if (mInStreamReader != null) {
            try {
                mInStreamReader.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
            mInStreamReader = null;
        }
        if (mInStreamBuffer != null) {
            try {
                mInStreamBuffer.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
            mInStreamBuffer = null;
        }
    }

    protected static void sleepIgnoreInterrupt(long time) {
        try {
            Thread.sleep(time);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    protected static CommandExecutor create(int timeout, String param) {
        String[] params = param.split(" ");
        CommandExecutor processModel = null;
        try {
            LOCK.lock();
            Process process = PRC.command(params).redirectErrorStream(true).start();
            processModel = new CommandExecutor(process, timeout);
        } catch (IOException e) {
            e.printStackTrace();
        } finally {
            // Sleep 10 to create next
            sleepIgnoreInterrupt(10);
            LOCK.unlock();
        }
        return processModel;
    }

    protected boolean isTimeOut() {
        return ((System.currentTimeMillis() - mStartTime) >= mTimeout);
    }


    protected String getResult() {
        // Until read end
        while (!isDone) {
            sleepIgnoreInterrupt(500);
        }

        // Get return value
        if (mResult.length() == 0) return null;
        else return mResult.toString();
    }

    protected void destroy() {
        String str = mProcess.toString();
        stopThread();
        try {
            int i = str.indexOf("=") + 1;
            int j = str.indexOf("]");
            str = str.substring(i, j);
            int pid = Integer.parseInt(str);
            mProcess.destroy();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}