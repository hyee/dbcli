package org.dbcli;

import sun.misc.Signal;
import sun.misc.SignalHandler;

import java.awt.event.ActionEvent;
import java.util.HashMap;

/**
 * Created by Will on 2015/9/15.
 */
public class Interrupter {
    static HashMap<String, InterruptCallback> map = new HashMap<>();
    static {
        Signal.handle(new Signal("INT"), new SignalHandler() {
            @Override
            public void handle(Signal signal) {
                if (!map.isEmpty()) {
                    ActionEvent e = new ActionEvent(this, ActionEvent.ACTION_PERFORMED, Character.toChars(3).toString());
                    for (InterruptCallback c : map.values()) {
                        try {
                            c.interrupt(e);
                        } catch (Exception ex) {
                            ex.printStackTrace();
                        }
                    }
                }
                this.handle(signal);
            }
        });
    }

    public static void listen(String name, InterruptCallback c) {
        if (map.containsKey(name)) map.remove(name);
        if (c != null) map.put(name, c);
    }
}
