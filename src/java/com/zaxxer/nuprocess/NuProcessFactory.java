/*
 * Copyright (C) 2013 Brett Wooldridge
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

package com.zaxxer.nuprocess;

import java.nio.file.Path;
import java.util.List;

/**
 * <b>This is an internal class.</b> Instances of this interface create and
 * start processes in a platform-specific fashion.
 *
 * @author Brett Wooldridge
 */
public interface NuProcessFactory
{
   NuProcess createProcess(List<String> commands, String[] env, NuProcessHandler processListener, Path cwd);

   /**
    * Runs the process synchronously.
    *
    * Pumping is done on the calling thread, and this method will not return until the process has exited.
    *
    * @since 1.3
    */
   void runProcess(List<String> commands, String[] env, NuProcessHandler processListener, Path cwd);
}
