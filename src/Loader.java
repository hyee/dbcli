import java.net.MalformedURLException;
import java.net.URLClassLoader;
import java.net.URL;
import java.security.CodeSource;
import java.security.ProtectionDomain;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Set;
import java.util.Vector;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import com.naef.jnlua.*;
import java.io.IOException;


public class Loader {
	public static LuaState lua; 

	public Loader() {
		lua = new LuaState();
		lua.openLibs();
		lua.pushJavaObject(this);
		lua.setGlobal("loader");
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
		File f = new File(Loader.class.getProtectionDomain().getCodeSource()
				.getLocation().toURI());
		String input = f.getParent() + "\\lua\\input.lua";
		FileInputStream inputStream = new FileInputStream(input);
		// System.out.println(input);
		lua.load(inputStream, input);
		for (int i = 0; i < args.length; i++)
			lua.pushString(args[i]);
		lua.call(args.length, 0);
	}
}