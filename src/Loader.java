
import java.net.URLClassLoader;
import java.net.URL;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.Writer;

import java.io.PrintWriter;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import com.naef.jnlua.*;
import java.io.IOException;



public class Loader {
	
	
	public static LuaState lua; 
	public static PrintWriter printer;
	public static Object reader;
	public static Boolean ReloadNextTime=true;

	public Loader() {
		try {
			reader=Class.forName("jline.console.ConsoleReader").newInstance();
			Class clz=reader.getClass();
			printer = new PrintWriter((Writer) clz.getMethod("getOutput").invoke(reader));			
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
	
	public static void loadLua(Loader l,String args[]) throws Exception {
		lua= new LuaState();
		lua.openLibs();
		lua.pushJavaObject(l);
		lua.setGlobal("loader");
		if(printer!=null) { 						
			lua.pushJavaObject(reader);
			lua.setGlobal("reader");
			lua.pushJavaObject(printer);
			lua.setGlobal("writer");
		} 
		String separator=System.getProperty("file.separator");
		File f = new File(Loader.class.getProtectionDomain().getCodeSource()
				.getLocation().toURI());
		String input = f.getParent() + separator+"lua"+separator+"input.lua";
		FileInputStream inputStream = new FileInputStream(input);
		// System.out.println(input);
		lua.load(inputStream, input);
		for (int i = 0; i < args.length; i++)
			lua.pushString(args[i]);
		ReloadNextTime=false;
		lua.call(args.length, 0);
		inputStream.close();
		lua.close();
		lua=null;
		inputStream=null;
		System.gc();
	}
		
	public static void main(String args[]) throws Exception {
		System.loadLibrary("lua5.1");
		Loader l = new Loader();		
		while(ReloadNextTime) loadLua(l,args);  
	}
}