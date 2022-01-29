package org.dbcli;

import org.jline.terminal.Terminal;

import java.awt.event.ActionEvent;
import java.util.HashMap;
import java.util.Map;

public class Interrupter implements Terminal.SignalHandler {
    public static Terminal.SignalHandler handler;
    static HashMap<Object, EventCallback> map = new HashMap<>();

    public static void listen(Object name, EventCallback c) {
        //System.out.println(name.toString()+(c==null?"null":c.toString()));
        map.remove(name);
        if (c != null && !map.containsValue(c)) map.put(name, c);
    }

    public static void reset() {
        map.clear();
    }

    @Override
    public void handle(Terminal.Signal signal) {
        if (!map.isEmpty()) {
            for (Map.Entry<Object, EventCallback> entry : map.entrySet()) {
                ActionEvent e = new ActionEvent(entry.getKey(), ActionEvent.ACTION_PERFORMED, "\3");
                try {
                    entry.getValue().call(e, "CTRL+C");
                } catch (StackOverflowError e1) {
                    continue;
                } catch (Throwable ex) {
                    ex.printStackTrace();
                }
            }
        }
    }
}