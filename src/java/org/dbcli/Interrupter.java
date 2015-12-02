package org.dbcli;

import com.zaxxer.nuprocess.windows.HANDLER_ROUTINE;
import com.zaxxer.nuprocess.windows.NuKernel32;
import java.awt.event.ActionEvent;
import java.util.HashMap;

public class Interrupter {
    static HashMap<Object, InterruptCallback> map = new HashMap<>();
    static HANDLER_ROUTINE handler=new HANDLER_ROUTINE()
    {
        @Override
        public long callback(long dwCtrlType) {
            if ((int)dwCtrlType == CTRL_C_EVENT&&!map.isEmpty()) {
                ActionEvent e = new ActionEvent(this, ActionEvent.ACTION_PERFORMED, "\3");
                for (InterruptCallback c : map.values()) {
                    try {
                        c.interrupt(e);
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
                return 1;
            }
            return 0;
        }
    };
    static {
        NuKernel32.SetConsoleCtrlHandler(handler, true);
    }

    public static void listen(Object name, InterruptCallback c) {
        //System.out.println(name.toString()+(c==null?"null":c.toString()));
        if (map.containsKey(name)) map.remove(name);
        if (c != null) map.put(name, c);
    }
}