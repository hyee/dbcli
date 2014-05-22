
import java.net.URLClassLoader;
import java.net.URL;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.File;
import java.io.FileInputStream;
import java.io.Writer;

import java.io.PrintWriter;

import java.lang.reflect.Method;
import com.naef.jnlua.*;
import java.io.IOException;



public class Loader {
	
	
	public static LuaState lua; 
	public static PrintWriter printer;
	
	class KbdListener implements ActionListener {
	    public KbdListener() {
	    }

	    public void actionPerformed(ActionEvent e) {
	    	printer.println("Event " + e);
	    }
	}

	public Loader() {
		lua = new LuaState();
		lua.openLibs();
		lua.pushJavaObject(this);
		lua.setGlobal("loader");
		try {
			Object reader=Class.forName("jline.console.ConsoleReader").newInstance();
			Class clz=reader.getClass();
			printer = new PrintWriter((Writer) clz.getMethod("getOutput").invoke(reader));
			clz.getMethod("addTriggeredAction",new Class[] {char.class,ActionListener.class}).invoke(reader,'q',new KbdListener());			
			lua.pushJavaObject(reader);
			lua.setGlobal("reader");
			lua.pushJavaObject(printer);
			lua.setGlobal("writer");
		} catch(Exception e) {
			//e.printStackTrace();
		}
	}	

	public void addPath(String file) throws Exception {
		URLClassLoader classLoader = (URLClassLoader) lua.getClassLoader();
		Class<URLClassLoader> clazz = URLClassLoader.class;
		URL url = new URL("file:" + file);
		// Use reflection
		Method method = clazz.getDeclaredMethod("addURL",
				new Class[] { URL.class });
		method.setAccessible(true);
		method.invoke(classLoader, new Object[] { url });
	}

	public static void main(String args[]) throws Exception {
		System.loadLibrary("lua5.1");
		new Loader();
		String separator=System.getProperty("file.separator");
		File f = new File(Loader.class.getProtectionDomain().getCodeSource()
				.getLocation().toURI());
		String input = f.getParent() + separator+"lua"+separator+"input.lua";
		FileInputStream inputStream = new FileInputStream(input);
		// System.out.println(input);
		lua.load(inputStream, input);
		for (int i = 0; i < args.length; i++)
			lua.pushString(args[i]);
		lua.call(args.length, 0);
	}
}