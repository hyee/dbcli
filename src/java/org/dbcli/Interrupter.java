package org.dbcli;

import java.awt.event.ActionEvent;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.HashMap;

/**
 * Created by Will on 2015/9/15.
 */
public class Interrupter {
    static HashMap<String, InterruptCallback> map = new HashMap<>();
    static Object signalHandler;

    static {
        try {
            final Class<?> signalClass = Class.forName("sun.misc.Signal");
            final Class<?> signalHandlerClass = Class.forName("sun.misc.SignalHandler");
            final Object signal = signalClass.getConstructor(String.class).newInstance("INT");
            signalHandler = Proxy.newProxyInstance(Interrupter.class.getClassLoader(), new Class<?>[]{signalHandlerClass}, new InvocationHandler() {
                public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
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
                    return null;
                }});
            signalClass.getMethod("handle", signalClass, signalHandlerClass).invoke(null, signal, signalHandler);
        } catch (Exception e) {}
    }

    public static void listen(String name, InterruptCallback c) {
        if (signalHandler == null) return;
        if (map.containsKey(name)) map.remove(name);
        if (c != null) map.put(name, c);
    }
}