/*
 * Copyright (C) 2015 Ben Hamilton
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.zaxxer.nuprocess.internal;

import com.sun.jna.LastErrorException;

/**
 * Encapsulates a file descriptor plus a reference count to ensure close requests
 * only close the file descriptor once the last reference to the file descriptor
 * is released.
 * <p>
 * If not explicitly closed, the file descriptor will be closed when
 * this object is finalized.
 */
public class ReferenceCountedFileDescriptor {
    private int fd;
    private int fdRefCount;
    private boolean closePending;

    public ReferenceCountedFileDescriptor(int fd) {
        this.fd = fd;
        this.fdRefCount = 0;
        this.closePending = false;
    }

    protected void finalize() {
        close();
    }

    public synchronized int acquire() {
        fdRefCount++;
        return fd;
    }

    public synchronized void release() {
        fdRefCount--;
        if (fdRefCount == 0 && closePending && fd != -1) {
            doClose();
        }
    }

    public synchronized void close() {
        if (fd == -1 || closePending) {
            return;
        }

        if (fdRefCount == 0) {
            doClose();
        } else {
            // Another thread has the FD. We'll close it when they release the reference.
            closePending = true;
        }
    }

    private void doClose() {
        try {
            LibC.close(fd);
            fd = -1;
        } catch (LastErrorException e) {
            throw new RuntimeException(e);
        }
    }
}
