/*
 * $Id: jnlua.c 155 2012-10-05 22:12:54Z andre@naef.com $
 * See LICENSE.txt for license terms.
 */

#include <stdlib.h>
#include <string.h>
#include <jni.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* Include uintptr_t */
#ifdef LUA_WIN
#include <stddef.h>
#if __STDC_VERSION__ >= 201112 && !defined __STDC_NO_THREADS__
#define JNLUA_THREADLOCAL _Thread_local
#elif defined _WIN32 && (defined _MSC_VER || \
						 defined __ICL ||    \
						 defined __DMC__ ||  \
						 defined __BORLANDC__)
#define JNLUA_THREADLOCAL __declspec(thread)
#else
#define JNLUA_THREADLOCAL __thread
#endif
#endif
#ifdef LUA_USE_POSIX
#include <stdint.h>
#define JNLUA_THREADLOCAL static __thread
#endif

/* ---- Definitions ---- */
#define JNLUA_APIVERSION 2
#define JNLUA_JNIVERSION JNI_VERSION_1_8
#define JNLUA_JAVASTATE "jnlua.JavaState"
#define JNLUA_OBJECT "jnlua.Object"
#define JNLUA_MINSTACK LUA_MINSTACK
static JavaVM *java_vm = NULL;
JNLUA_THREADLOCAL JNIEnv *thread_env;
#define JNLUA_ENV                                                                       \
	jint envStat = (*java_vm)->GetEnv(java_vm, (void **)&thread_env, JNLUA_JNIVERSION); \
	if (envStat == JNI_EDETACHED)                                                       \
	{                                                                                   \
		if ((*java_vm)->AttachCurrentThread(java_vm, (void **)&thread_env, NULL) != 0)  \
		{                                                                               \
			printf("%s", "Failed to AttachCurrentThread");                              \
		}                                                                               \
	}
#define JNLUA_ENV_L \
	JNLUA_ENV;      \
	lua_State *L = getluathread(obj);
#define JNLUA_DETACH                              \
	if (envStat == JNI_EDETACHED)                 \
	{                                             \
		envStat = 0;                              \
		(*java_vm)->DetachCurrentThread(java_vm); \
	}
#define JNLUA_DETACH_L                              \
	(*thread_env)->DeleteLocalRef(thread_env, obj); \
	JNLUA_DETACH;

#define JNLUA_PCALL(L, nargs, nresults)                    \
	{                                                      \
		int status = lua_pcall(L, (nargs), (nresults), 0); \
		if (status != 0)                                   \
		{                                                  \
			throw(L, status);                              \
			JNLUA_DETACH_L;                                \
		}                                                  \
	}
#define lua_absindex(L, index) (index > 0 || index <= LUA_REGISTRYINDEX) ? index : lua_gettop(L) + index + 1

#include <setjmp.h>
/* ---- Error handling ---- */
/*
 * JNI does not allow uncontrolled transitions such as jongjmp between Java
 * code and native code, but Lua uses longjmp for error handling. The follwing
 * section replicates logic from luaD_rawrunprotected that is internal to
 * Lua. Contact me if you know of a more elegant solution ;)
 */
/*
struct lua_longjmp {
	struct lua_longjmp *previous;
	jmp_buf b;
	volatile int status;
};

struct lua_State {
	void *next;
	unsigned char tt;
	unsigned char marked;
	unsigned char status;
	void *top;
	void *l_G;
	void *ci;
	void *oldpc;
	void *stack_last;
	void *stack;
	int stacksize;
	unsigned short nny;
	unsigned short nCcalls;  
	unsigned char hookmask;
	unsigned char allowhook;
	int basehookcount;
	int hookcount;
	lua_Hook hook;
	void *openupval;
	void *gclist;
	struct lua_longjmp *errorJmp;  
};

#define JNLUA_TRY {\
	unsigned short oldnCcalls = L->nCcalls;\
	struct lua_longjmp lj;\
	lj.status = 0;\
	lj.previous = L->errorJmp;\
	L->errorJmp = &lj;\
	if (setjmp(lj.b) == 0) {\
		checkstack(L, LUA_MINSTACK, NULL);\
		setJniEnv(L, env);
#define JNLUA_END }\
	L->errorJmp = lj.previous;\
	L->nCcalls = oldnCcalls;\
	if (lj.status != 0) {\
		throwException(env, L, lj.status);\
	}\
}
#define JNLUA_THROW(status) lj.status = status;\
	longjmp(lj.b, -1)
*/
/* ---- Types ---- */
/* Structure for reading and writing Java streams. */
typedef struct StreamStruct
{
	jobject stream;
	jbyteArray byte_array;
	jbyte *bytes;
	jboolean is_copy;
} Stream;

/* ---- JNI helpers ---- */
static jclass referenceclass(JNIEnv *env, const char *className);
static jbyteArray newbytearray(jsize length);
static const char *getstringchars(jstring string);
static void releasestringchars(jstring string, const char *chars);

/* ---- Java state operations ---- */
static lua_State *getluastate(jobject javastate);
static void setluastate(jobject javastate, lua_State *L);
static lua_State *getluathread(jobject javastate);
static void setluathread(jobject javastate, lua_State *L);
static int getyield(jobject javastate);
static void setyield(jobject javastate, int yield);
static lua_Debug *getluadebug(jobject javadebug);
static void setluadebug(jobject javadebug, lua_Debug *ar);

/* ---- Memory use control ---- */
static void getluamemory(jint *total, jint *used);
static void setluamemoryused(jint used);

/* ---- Checks ---- */
static int validindex(lua_State *L, int index);
static int checkstack(lua_State *L, int space);
static int checkindex(lua_State *L, int index);
static int checkrealindex(lua_State *L, int index);
static int checktype(lua_State *L, int index, int type);
static int checknelems(lua_State *L, int n);
static int checknotnull(void *object);
static int checkarg(int cond, const char *msg);
static int checkstate(int cond, const char *msg);
static int check(int cond, jthrowable throwable_class, const char *msg);

/* ---- Java objects and functions ---- */
static void pushjavaobject(lua_State *L, jobject object);
static jobject tojavaobject(lua_State *L, int index, jclass class);
static jstring tostring(lua_State *L, int index);
static int gcjavaobject(lua_State *L);
static int calljavafunction(lua_State *L);

/* ---- Error handling ---- */
static int messagehandler(lua_State *L);
static int isrelevant(lua_Debug *ar);
static void throw(lua_State * L, int status);

/* ---- Stream adapters ---- */
static const char *readhandler(lua_State *L, void *ud, size_t *size);
static int writehandler(lua_State *L, const void *data, size_t size, void *ud);

/* ---- Variables ---- */
static jclass luastate_class = NULL;
static jfieldID luastate_id = 0;
static jfieldID luathread_id = 0;
static jfieldID luamemorytotal_id = 0;
static jfieldID luamemoryused_id = 0;
static jfieldID yield_id = 0;
static jclass luadebug_class = NULL;
static jmethodID luadebug_init_id = 0;
static jfieldID luadebug_field_id = 0;
static jclass javafunction_interface = NULL;
static jmethodID invoke_id = 0;
static jclass luaruntimeexception_class = NULL;
static jmethodID luaruntimeexception_id = 0;
static jmethodID setluaerror_id = 0;
static jclass luasyntaxexception_class = NULL;
static jmethodID luasyntaxexception_id = 0;
static jclass luamemoryallocationexception_class = NULL;
static jmethodID luamemoryallocationexception_id = 0;
static jclass luagcmetamethodexception_class = NULL;
static jmethodID luagcmetamethodexception_id = 0;
static jclass luamessagehandlerexception_class = NULL;
static jmethodID luamessagehandlerexception_id = 0;
static jclass luastacktraceelement_class = NULL;
static jmethodID luastacktraceelement_id = 0;
static jclass luaerror_class = NULL;
static jmethodID luaerror_id = 0;
static jmethodID setluastacktrace_id = 0;
static jclass nullpointerexception_class = NULL;
static jclass illegalargumentexception_class = NULL;
static jclass illegalstateexception_class = NULL;
static jclass error_class = NULL;
static jclass integer_class = NULL;
static jmethodID valueof_integer_id = 0;
static jclass double_class = NULL;
static jmethodID valueof_double_id = 0;
static jclass inputstream_class = NULL;
static jmethodID read_id = 0;
static jclass outputstream_class = NULL;
static jmethodID write_id = 0;
static jclass ioexception_class = NULL;
static int initialized = 0;
static jmethodID print_id = 0;

JNLUA_THREADLOCAL jobject luastate_obj;

JNLUA_THREADLOCAL JNIEnv *env_;
JNIEnv *get_jni_env()
{
	if (!env_ && java_vm)
	{
		(*java_vm)->GetEnv(java_vm, (void **)&env_, JNLUA_JNIVERSION);
	}
	return env_;
}

static void println(char *message)
{
	jstring msg = (*thread_env)->NewStringUTF(thread_env, message);
	(*thread_env)->CallStaticVoidMethod(thread_env, luastate_class, print_id, msg);
	(*thread_env)->DeleteLocalRef(thread_env, msg);
}

static void println_(const char *format, ...)
{
	char *msg;
	va_list args;
	va_start(args, format);
	vsnprintf(msg, sizeof(msg), format, args);
	va_end(args);
	println(msg);
}

static int handlejavaexception(lua_State *L, int raise)
{
	jthrowable throwable;
	jstring where;
	jobject luaerror;
	if ((*thread_env)->ExceptionCheck(thread_env))
	{
		/* Push exception & clear */
		luaL_where(L, 1);
		(*thread_env)->PushLocalFrame(thread_env, 32);
		where = tostring(L, -1);
		/* Handle exception */
		throwable = (*thread_env)->ExceptionOccurred(thread_env);
		(*thread_env)->ExceptionClear(thread_env);
		if (throwable)
		{
			luaerror = (*thread_env)->NewObject(thread_env, luaerror_class, luaerror_id, where, throwable);
			if (luaerror)
			{
				pushjavaobject(L, luaerror);
			}
			else
			{
				lua_pushliteral(L, "JNI error: NewObject() failed creating Lua error");
				lua_concat(L, 2);
			}
		}
		else
		{
			lua_pushliteral(L, "Java exception occurred.");
			lua_concat(L, 2);
		}
		(*thread_env)->PopLocalFrame(thread_env, NULL);
		if (raise)
			return lua_error(L);
		return 1;
	}
	return 0;
}

/* ---- Fields ---- */
/* lua_registryindex() */
jint jcall_registryindex(JNIEnv *env, jobject obj)
{
	(*env)->DeleteLocalRef(env, obj);
	return (jint)LUA_REGISTRYINDEX;
}

/* lua_version() */
jstring jcall_version(JNIEnv *env, jobject obj)
{
	const char *luaVersion;

	luaVersion = LUA_VERSION;
	if (strncmp(luaVersion, "Lua ", 4) == 0)
	{
		luaVersion += 4;
	}
	(*env)->DeleteLocalRef(env, obj);
	return (*env)->NewStringUTF(env, luaVersion);
}

/* ---- Life cycle ---- */
/*
 * lua_newstate()
 */
JNLUA_THREADLOCAL jobject newstate_obj;
static int newstate_protected(lua_State *L)
{
	jobject *ref;

	/* Set the Java state in the Lua state. */
	/* Ansca: Original code stored this object as a "weak reference", which did not pin the object in memory
	 *        on the Java side and caused random crashes. Changed to a "global reference" to pin it in memory.
	 */
	ref = lua_newuserdata(L, sizeof(jobject));
	lua_createtable(L, 0, 1);
	lua_pushboolean(L, 0); /* non-weak global reference */
	lua_pushcclosure(L, gcjavaobject, 1);
	lua_setfield(L, -2, "__gc");
	*ref = (*thread_env)->NewGlobalRef(thread_env, newstate_obj);
	if (!*ref)
	{
		lua_pushliteral(L, "JNI error: NewWeakGlobalRef() failed setting up Lua state");
		return lua_error(L);
	}
	lua_setmetatable(L, -2);
	lua_setfield(L, LUA_REGISTRYINDEX, JNLUA_JAVASTATE);

	/*
	 * Create the meta table for Java objects and return it. Population will
	 * be finished on the Java side.
	 */
	luaL_newmetatable(L, JNLUA_OBJECT);
	lua_pushboolean(L, 0);
	lua_setfield(L, -2, "__metatable");
	lua_pushboolean(L, 0); /* non-weak global reference */
	lua_pushcclosure(L, gcjavaobject, 1);
	lua_setfield(L, -2, "__gc");
	return 1;
}
/* This custom allocator ensures a VM won't exceed its allowed memory use. */
static void *l_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	jint total, used;
	(void)ud; /* not used, always NULL */
	getluamemory(&total, &used);
	if (nsize == 0)
	{
		free(ptr);
		setluamemoryused(used - osize);
	}
	else
	{
		if (ptr == NULL)
		{
			if (total >= 0 && total - nsize >= used)
			{
				setluamemoryused(used + nsize);
				return malloc(nsize);
			}
		}
		else
		{
			/* Lua expects this to not fail if nsize <= osize, so we must allow
			   that even if it exceeds our current max memory. */
			if (nsize <= osize || (total - (nsize - osize) >= used))
			{
				setluamemoryused(used + (nsize - osize));
				return realloc(ptr, nsize);
			}
		}
	}
	return NULL;
}
static int panic(lua_State *L)
{
	(void)L; /* to avoid warnings */
	fprintf(stderr, "PANIC: unprotected error in call to Lua API (%s)\n",
			lua_tostring(L, -1));
	return 0;
}
static lua_State *controlled_newstate(void)
{
	jint total, used;
	getluamemory(&total, &used);
	if (total <= 0)
	{
		return luaL_newstate();
	}
	else
	{
		lua_State *L = lua_newstate(l_alloc, NULL);
		if (L)
			lua_atpanic(L, &panic);
		return L;
	}
}

/* lua_close() */
static int close_protected(lua_State *L)
{
	/* Unset the Java state in the Lua state. */
	lua_pushnil(L);
	lua_setfield(L, LUA_REGISTRYINDEX, JNLUA_JAVASTATE);

	return 0;
}
void jcall_close(JNIEnv *env, jobject obj, jboolean ownstate)
{
	JNLUA_ENV_L;
	lua_State *T;
	lua_Debug ar;

	if (ownstate)
	{
		/* Can close? */
		T = getluastate(obj);
		if (L != T || lua_getstack(L, 0, &ar))
		{
			goto END;
		}
		lua_pushcfunction(L, close_protected);
		JNLUA_PCALL(L, 0, 0);
		/* Unset the Lua state in the Java state. */
		setluastate(obj, NULL);
		setluathread(obj, NULL);

		/* Close Lua state. */
		lua_close(L);
	}
	else
	{
		/* Can close? */
		if (!lua_checkstack(L, JNLUA_MINSTACK))
		{
			goto END;
		}

		/* Cleanup Lua state. */
		lua_pushcfunction(L, close_protected);
		JNLUA_PCALL(L, 0, 0);
		if ((*thread_env)->ExceptionCheck(thread_env))
		{
			goto END;
		}

		/* Unset the Lua state in the Java state. */
		setluastate(obj, NULL);
		setluathread(obj, NULL);
	}
END:
	JNLUA_DETACH_L;
}

void jcall_newstate(JNIEnv *env, jobject obj, int apiversion, jlong existing)
{
	/* Initialized? */
	if (!initialized)
	{
		return;
	}
	JNLUA_ENV_L;
	(*thread_env)->EnsureLocalCapacity(thread_env, 512);
	/* API version? */
	if (apiversion != JNLUA_APIVERSION)
	{
		goto END;
	}

	/* Create or attach to Lua state. */

	luastate_obj = obj;
	L = !existing ? controlled_newstate() : (lua_State *)(uintptr_t)existing;
	if (!L)
	{
		goto END;
	}

	/* Setup Lua state. */
	if (checkstack(L, JNLUA_MINSTACK))
	{
		newstate_obj = obj;
		lua_pushcfunction(L, newstate_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	if ((*thread_env)->ExceptionCheck(thread_env))
	{
		if (!existing)
		{
			lua_pushcfunction(L, close_protected);
			JNLUA_PCALL(L, 0, 0);
			lua_close(L);
		}
		goto END;
	}

	/* Set the Lua state in the Java state. */
	setluathread(obj, L);
	setluastate(obj, L);
END:
	JNLUA_DETACH_L;
}

/* lua_gc() */
JNLUA_THREADLOCAL int gc_what;
JNLUA_THREADLOCAL int gc_data;
JNLUA_THREADLOCAL int gc_result;
static int gc_protected(lua_State *L)
{
	gc_result = lua_gc(L, gc_what, gc_data);
	return 0;
}
jint jcall_gc(JNIEnv *env, jobject obj, jint what, jint data)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		gc_what = what;
		gc_data = data;
		lua_pushcfunction(L, gc_protected);
		JNLUA_PCALL(L, 0, 0);
	}
	JNLUA_DETACH_L;
	return (jint)gc_result;
}

/* ---- Registration ---- */
JNLUA_THREADLOCAL int openlib_lib;
static int openlib_protected(lua_State *L)
{
	lua_CFunction openfunc;
	const char *libname;

	switch (openlib_lib)
	{
	case 0:
		openfunc = luaopen_base;
		libname = "_G";
		break;
	case 1:
		openfunc = luaopen_table;
		libname = LUA_TABLIBNAME;
		break;
	case 2:
		openfunc = luaopen_io;
		libname = LUA_IOLIBNAME;
		break;
	case 3:
		openfunc = luaopen_os;
		libname = LUA_OSLIBNAME;
		break;
	case 4:
		openfunc = luaopen_string;
		libname = LUA_STRLIBNAME;
		break;
	case 5:
		openfunc = luaopen_math;
		libname = LUA_MATHLIBNAME;
		break;
	case 6:
		openfunc = luaopen_debug;
		libname = LUA_DBLIBNAME;
		break;
	case 7:
		openfunc = luaopen_package;
		libname = LUA_LOADLIBNAME;
		break;
	case 8:
		openfunc = luaopen_bit;
		libname = LUA_LOADLIBNAME;
		break;
	case 9:
		openfunc = luaopen_jit;
		libname = LUA_LOADLIBNAME;
		break;
	case 10:
		openfunc = luaopen_ffi;
		libname = LUA_LOADLIBNAME;
		break;
	default:
		return 0;
	}
	lua_pushcfunction(L, openfunc);
	lua_pushstring(L, libname);
	lua_call(L, 1, 0);
	return 0;
}
void jcall_openlib(JNIEnv *env, jobject obj, jint lib)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkarg(lib >= 0 && lib <= 10, "illegal library"))
	{
		openlib_lib = lib;
		lua_pushcfunction(L, openlib_protected);
		JNLUA_PCALL(L, 0, 0);
	}
	JNLUA_DETACH_L;
}

void jcall_openlibs(JNIEnv *env, jobject obj)
{
	JNLUA_ENV_L;
	luaL_openlibs(L);
	JNLUA_DETACH_L;
}

/* ---- Load and dump ---- */
/* lua_load() */
void jcall_load(JNIEnv *env, jobject obj, jobject inputStream, jstring chunkname, jstring mode)
{
	JNLUA_ENV_L;
	const char *chunkname_utf = NULL;
	Stream stream = {inputStream, NULL, NULL, 0};
	int status;

	if (checkstack(L, JNLUA_MINSTACK) && (chunkname_utf = getstringchars(chunkname)) && (stream.byte_array = newbytearray(1024)))
	{
		status = lua_load(L, readhandler, &stream, chunkname_utf);
		if (status != 0)
		{
			throw(L, status);
		}
	}
	if (stream.bytes)
	{
		(*thread_env)->ReleaseByteArrayElements(thread_env, stream.byte_array, stream.bytes, JNI_ABORT);
	}
	if (stream.byte_array)
	{
		(*thread_env)->DeleteLocalRef(thread_env, stream.byte_array);
	}
	if (chunkname_utf)
	{
		releasestringchars(chunkname, chunkname_utf);
	}
	(*thread_env)->DeleteLocalRef(thread_env,inputStream);
	JNLUA_DETACH_L;
}

/* lua_dump() */
void jcall_dump(JNIEnv *env, jobject obj, jobject outputStream)
{
	JNLUA_ENV_L;
	Stream stream = {outputStream, NULL, NULL, 0};
	if (checkstack(L, JNLUA_MINSTACK) && checknelems(L, 1) && (stream.byte_array = newbytearray(1024)))
	{
		lua_dump(L, writehandler, &stream);
	}
	if (stream.bytes)
	{
		(*thread_env)->ReleaseByteArrayElements(thread_env, stream.byte_array, stream.bytes, JNI_ABORT);
	}
	if (stream.byte_array)
	{
		(*thread_env)->DeleteLocalRef(thread_env, stream.byte_array);
	}
	(*thread_env)->DeleteLocalRef(thread_env,outputStream);
	JNLUA_DETACH_L;
}

/* ---- Call ---- */
/* lua_pcall() */
void jcall_pcall(JNIEnv *env, jobject obj, jint nargs, jint nresults)
{
	JNLUA_ENV_L;
	int index, status;
	if (checkarg(nargs >= 0, "illegal argument count") && checknelems(L, nargs + 1) && checkarg(nresults >= 0 || nresults == LUA_MULTRET, "illegal return count") && (nresults == LUA_MULTRET || checkstack(L, nresults - (nargs + 1))))
	{
		index = lua_absindex(L, -nargs - 1);
		lua_pushcfunction(L, messagehandler);
		lua_insert(L, index);
		status = lua_pcall(L, nargs, nresults, index);
		lua_remove(L, index);
		if (status != 0)
		{
			throw(L, status);
		}
	}
	JNLUA_DETACH_L;
}

/* ---- Global ---- */
/* lua_getglobal() */
JNLUA_THREADLOCAL const char *getglobal_name;
static int getglobal_protected(lua_State *L)
{
	lua_getglobal(L, getglobal_name);
	return 1;
}
void jcall_getglobal(JNIEnv *env, jobject obj, jstring name)
{
	JNLUA_ENV_L;
	getglobal_name = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && (getglobal_name = getstringchars(name)))
	{
		lua_pushcfunction(L, getglobal_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	if (getglobal_name)
	{
		releasestringchars(name, getglobal_name);
	}
	JNLUA_DETACH_L;
}

/* lua_setglobal() */
JNLUA_THREADLOCAL const char *setglobal_name;
static int setglobal_protected(lua_State *L)
{
	lua_setglobal(L, setglobal_name);
	return 0;
}
void jcall_setglobal(JNIEnv *env, jobject obj, jstring name)
{
	JNLUA_ENV_L;
	setglobal_name = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checknelems(L, 1) && (setglobal_name = getstringchars(name)))
	{
		lua_pushcfunction(L, setglobal_protected);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 1, 0);
	}
	if (setglobal_name)
	{
		releasestringchars(name, setglobal_name);
	}
	JNLUA_DETACH_L;
}

/* ---- Stack push ---- */
/* lua_pushboolean() */
void jcall_pushboolean(JNIEnv *env, jobject obj, jint b)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushboolean(L, b);
	}
	JNLUA_DETACH_L;
}

/* lua_pushbytearray() */
JNLUA_THREADLOCAL jbyte *pushbytearray_b;
JNLUA_THREADLOCAL jsize pushbytearray_length;
static int pushbytearray_protected(lua_State *L)
{
	lua_pushlstring(L, pushbytearray_b, pushbytearray_length);
	return 1;
}
void jcall_pushbytearray(JNIEnv *env, jobject obj, jbyteArray ba)
{
	JNLUA_ENV_L;
	pushbytearray_b = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && (pushbytearray_b = (*thread_env)->GetByteArrayElements(thread_env, ba, NULL)))
	{
		pushbytearray_length = (*thread_env)->GetArrayLength(thread_env, ba);
		lua_pushcfunction(L, pushbytearray_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	if (pushbytearray_b)
	{
		(*thread_env)->ReleaseByteArrayElements(thread_env, ba, pushbytearray_b, JNI_ABORT);
	}
	(*thread_env)->DeleteLocalRef(thread_env, ba);
	JNLUA_DETACH_L;
}

/* lua_pushinteger() */
void jcall_pushinteger(JNIEnv *env, jobject obj, jint n)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushnumber(L, n);
	}
	JNLUA_DETACH_L;
}

/* lua_pushjavafunction() */
JNLUA_THREADLOCAL jobject pushjavafunction_f;
static int pushjavafunction_protected(lua_State *L)
{
	pushjavaobject(L, pushjavafunction_f);
	lua_pushcclosure(L, calljavafunction, 1);
	return 1;
}
void jcall_pushjavafunction(JNIEnv *env, jobject obj, jobject f)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checknotnull(f))
	{
		pushjavafunction_f = f;
		lua_pushcfunction(L, pushjavafunction_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	(*thread_env)->DeleteLocalRef(thread_env,f);
	JNLUA_DETACH_L;
}

/* lua_pushjavaobject() */
JNLUA_THREADLOCAL jobject pushjavaobject_object;
JNLUA_THREADLOCAL jstring pushjavaobject_class;
static int pushjavaobject_protected(lua_State *L)
{
	pushjavaobject(L, pushjavaobject_object);
	return 1;
}

static int pushjavaobject_protected_meta(lua_State *L)
{
	if (pushjavaobject_class == NULL)
		return pushjavaobject_protected(L);
	jobject *user_data;
	user_data = (jobject *)lua_newuserdata(L, sizeof(jobject));
	*user_data = (*thread_env)->NewGlobalRef(thread_env, pushjavaobject_object);
	if (!*user_data)
	{
		lua_pushliteral(L, "JNI error: NewGlobalRef() failed pushing Java object");
		lua_error(L);
	}

	const char *str = getstringchars(pushjavaobject_class);
	luaL_getmetatable(L, str);
	if (lua_type(L, -1) == 0)
	{
		lua_pop(L, 1);
		luaL_newmetatable(L, str);
		lua_pushstring(L, str);
		lua_setfield(L, -2, "__className");
		luaL_getmetatable(L, JNLUA_OBJECT);
		lua_setmetatable(L, -2);
	}
	lua_setmetatable(L, -2);
	lua_getmetatable(L, -1);

	lua_pop(L, 1);
	return 1;
}

void jcall_pushjavaobject(JNIEnv *env, jobject obj, jobject object)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checknotnull(object))
	{
		pushjavaobject_object = object;
		lua_pushcfunction(L, pushjavaobject_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	(*thread_env)->DeleteLocalRef(thread_env,object);
	JNLUA_DETACH_L;
}

void jcall_pushjavaobjectl(JNIEnv *env, jobject obj, jobject object, jstring class)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checknotnull(object))
	{
		pushjavaobject_object = object;
		pushjavaobject_class = class;
		lua_pushcfunction(L, pushjavaobject_protected_meta);
		JNLUA_PCALL(L, 0, 1);
	}
	(*thread_env)->DeleteLocalRef(thread_env,object);
	(*thread_env)->DeleteLocalRef(thread_env,class);
	JNLUA_DETACH_L;
}

/* lua_pushnil() */
void jcall_pushnil(JNIEnv *env, jobject obj)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushnil(L);
	}
	JNLUA_DETACH_L;
}

/* lua_pushnumber() */
void jcall_pushnumber(JNIEnv *env, jobject obj, jdouble n)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushnumber(L, n);
	}
	JNLUA_DETACH_L;
}

/* lua_pushstring() */
JNLUA_THREADLOCAL const char *pushstring_s;
JNLUA_THREADLOCAL jsize pushstring_length;
static int pushstring_protected(lua_State *L)
{
	lua_pushlstring(L, pushstring_s, pushstring_length);
	return 1;
}
void jcall_pushstring(JNIEnv *env, jobject obj, jstring s)
{
	JNLUA_ENV_L;
	pushstring_s = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && (pushstring_s = getstringchars(s)))
	{
		pushstring_length = (*thread_env)->GetStringUTFLength(thread_env, s);
		lua_pushcfunction(L, pushstring_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	if (pushstring_s)
	{
		releasestringchars(s, pushstring_s);
	}
	JNLUA_DETACH_L;
}

void jcall_pushstr2num(JNIEnv *env, jobject obj, jstring s)
{
	JNLUA_ENV_L;
	pushstring_s = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && (pushstring_s = getstringchars(s)))
	{
		pushstring_length = (*thread_env)->GetStringUTFLength(thread_env, s);
		lua_pushcfunction(L, pushstring_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	if (pushstring_s)
	{
		releasestringchars(s, pushstring_s);
		int isnum;
		lua_Number num = lua_tonumberx(L, -1, &isnum);
		lua_pop(L, 1);
		if(!isnum) {
			char buf[256];
			snprintf(buf, sizeof(buf), "Cannot convert String '%s' to number.", pushstring_s);
			(*thread_env)->ThrowNew(thread_env, error_class,buf);
		} else {
			lua_pushnumber(L,num);
		}
	}
	JNLUA_DETACH_L;
}

/* ---- Stack type test ---- */
/* lua_isboolean() */
jint jcall_isboolean(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_isboolean(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_iscfunction() */
jint jcall_iscfunction(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	lua_CFunction c_function = !validindex(L, index) ? NULL : lua_tocfunction(L, index);
	JNLUA_DETACH_L;
	return (jint)(c_function != NULL && c_function != calljavafunction);
}

/* lua_isfunction() */
jint jcall_isfunction(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_isfunction(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isjavafunction() */
jint jcall_isjavafunction(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_tocfunction(L, index) == calljavafunction);
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isjavaobject() */
JNLUA_THREADLOCAL int isjavaobject_result;
static int isjavaobject_protected(lua_State *L)
{
	isjavaobject_result = tojavaobject(L, 1, NULL) != NULL;
	return 0;
}
jint jcall_isjavaobject(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (!validindex(L, index))
	{
		isjavaobject_result = 0;
	}
	else if (checkstack(L, JNLUA_MINSTACK))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, isjavaobject_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	JNLUA_DETACH_L;
	return (jint)isjavaobject_result;
}

/* lua_isnil() */
jint jcall_isnil(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_isnil(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isnone() */
jint jcall_isnone(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)!validindex(L, index);
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isnoneornil() */
jint jcall_isnoneornil(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 1 : lua_isnil(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isnumber() */
jint jcall_isnumber(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_isnumber(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isstring() */
jint jcall_isstring(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_isstring(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_istable() */
jint jcall_istable(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_istable(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_isthread() */
jint jcall_isthread(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_isthread(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* ---- Stack query ---- */
/* lua_equal() */
int equal_result;
static int equal_protected(lua_State *L)
{
	equal_result = lua_equal(L, 1, 2);
	return 0;
}
jint jcall_equal(JNIEnv *env, jobject obj, jint index1, jint index2)
{
	JNLUA_ENV_L;
	if (!validindex(L, index1) || !validindex(L, index2))
	{
		equal_result = 0;
	}
	else if (checkstack(L, JNLUA_MINSTACK))
	{
		index1 = lua_absindex(L, index1);
		index2 = lua_absindex(L, index2);
		lua_pushcfunction(L, equal_protected);
		lua_pushvalue(L, index1);
		lua_pushvalue(L, index2);
		JNLUA_PCALL(L, 2, 0);
	}
	JNLUA_DETACH_L;
	return (jint)equal_result;
}

/* lua_lessthan() */
int lessthan_result;
static int lessthan_protected(lua_State *L)
{
	lessthan_result = lua_lessthan(L, 1, 2);
	return 0;
}
jint jcall_lessthan(JNIEnv *env, jobject obj, jint index1, jint index2)
{
	JNLUA_ENV_L;
	if (!validindex(L, index1) || !validindex(L, index2))
	{
		lessthan_result = 0;
	}
	else if (checkstack(L, JNLUA_MINSTACK))
	{
		index1 = lua_absindex(L, index1);
		index2 = lua_absindex(L, index2);
		lua_pushcfunction(L, lessthan_protected);
		lua_pushvalue(L, index1);
		lua_pushvalue(L, index2);
		JNLUA_PCALL(L, 2, 0);
	}
	JNLUA_DETACH_L;
	return (jint)lessthan_result;
}

/* lua_objlen() */
jint jcall_objlen(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	size_t result = 0;
	if (checkindex(L, index))
	{
		result = lua_objlen(L, index);
	}
	JNLUA_DETACH_L;
	return (jint)result;
}

/* lua_rawequal() */
jint jcall_rawequal(JNIEnv *env, jobject obj, jint index1, jint index2)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index1) || !validindex(L, index2) ? 0 : lua_rawequal(L, index1, index2));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_toboolean() */
jint jcall_toboolean(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? 0 : lua_toboolean(L, index));
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_tobytearray() */
JNLUA_THREADLOCAL const char *tobytearray_result;
JNLUA_THREADLOCAL size_t tobytearray_length;
static int tobytearray_protected(lua_State *L)
{
	tobytearray_result = lua_tolstring(L, 1, &tobytearray_length);
	return 0;
}
jbyteArray jcall_tobytearray(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jbyteArray ba = NULL;
	jbyte *b;

	tobytearray_result = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, tobytearray_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	if (!tobytearray_result)
	{
		goto END;
	}
	ba = (*thread_env)->NewByteArray(thread_env, (jsize)tobytearray_length);
	if (!ba)
	{
		goto END;
	}
	b = (*thread_env)->GetByteArrayElements(thread_env, ba, NULL);
	if (!b)
	{
		goto END;
	}
	memcpy(b, tobytearray_result, tobytearray_length);
	(*env)->ReleaseByteArrayElements(thread_env, ba, b, 0);
END:
	JNLUA_DETACH_L;
	return ba;
}

/* lua_tointeger() */
jlong jcall_tointeger(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	lua_Number result = 0;
	if (checkindex(L, index))
	{
		result = lua_tonumber(L, index);
	}
	JNLUA_DETACH_L;
	return (jlong)result;
}

/* lua_tointegerx() */
jobject jcall_tointegerx(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;

	lua_Number result = 0;
	int isnum = 0;

	if (checkindex(L, index))
	{
		result = lua_tonumberx(L, index, &isnum);
	}
	if (isnum)
	{
		const auto jobject obj1 = (*thread_env)->CallStaticObjectMethod(thread_env, integer_class, valueof_integer_id, (jlong)result);
		handlejavaexception(L, 1);
		JNLUA_DETACH_L;
		return obj1;
	}
	JNLUA_DETACH_L;
	return NULL;
}

/* lua_tojavafunction() */
JNLUA_THREADLOCAL jobject tojavafunction_result;
static int tojavafunction_protected(lua_State *L)
{
	tojavafunction_result = NULL;
	if (lua_tocfunction(L, 1) == calljavafunction)
	{
		if (lua_getupvalue(L, 1, 1))
		{
			tojavafunction_result = tojavaobject(L, -1, javafunction_interface);
		}
	}
	return 0;
}
jobject jcall_tojavafunction(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, tojavafunction_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	JNLUA_DETACH_L;
	return tojavafunction_result;
}

/* lua_tojavaobject() */
JNLUA_THREADLOCAL jobject tojavaobject_result;
static int tojavaobject_protected(lua_State *L)
{
	tojavaobject_result = tojavaobject(L, 1, NULL);
	return 0;
}
jobject jcall_tojavaobject(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, tojavaobject_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	JNLUA_DETACH_L;
	return tojavaobject_result;
}

/* lua_tonumber() */
jdouble jcall_tonumber(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;

	lua_Number result = 0.0;

	if (checkindex(L, index))
	{
		result = lua_tonumber(L, index);
	}
	JNLUA_DETACH_L;
	return (jdouble)result;
}

/* lua_tonumberx() */
jobject jcall_tonumberx(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	lua_Number result = 0.0;
	int isnum = 0;

	if (checkindex(L, index))
	{
		result = lua_tonumberx(L, index, &isnum);
	}
	if (isnum)
	{
		const auto jobject obj1 = (*thread_env)->CallStaticObjectMethod(thread_env, double_class, valueof_double_id, (jdouble)result);
		isnum = handlejavaexception(L, 1);
		JNLUA_DETACH_L;
		return obj1;
	}
	JNLUA_DETACH_L;
	return NULL;
}

/* lua_topointer() */
jlong jcall_topointer(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	const void *result = NULL;

	if (checkindex(L, index))
	{
		result = lua_topointer(L, index);
	}
	JNLUA_DETACH_L;
	return (jlong)(uintptr_t)result;
}

/* lua_tostring() */
JNLUA_THREADLOCAL const char *tostring_result;
static int tostring_protected(lua_State *L)
{
	tostring_result = lua_tostring(L, 1);
	return 0;
}
jstring jcall_tostring(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	tostring_result = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, tostring_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	jstring rtn = tostring_result ? (*thread_env)->NewStringUTF(thread_env, tostring_result) : NULL;
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_type() */
jint jcall_type(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)(!validindex(L, index) ? LUA_TNONE : lua_type(L, index));

	JNLUA_DETACH_L;
	return rtn;
}

/* ---- Stack operations ---- */
/* lua_absindex() */
jint jcall_absindex(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	jint rtn = (jint)lua_absindex(L, index);

	JNLUA_DETACH_L;
	return rtn;
}
/* lua_concat() */
JNLUA_THREADLOCAL int concat_n;
static int concat_protected(lua_State *L)
{
	lua_concat(L, concat_n);
	return 1;
}
void jcall_concat(JNIEnv *env, jobject obj, jint n)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkarg(n >= 0, "illegal count") && checknelems(L, n))
	{
		concat_n = n;
		lua_pushcfunction(L, concat_protected);
		lua_insert(L, -n - 1);
		JNLUA_PCALL(L, n, 1);
	}
	JNLUA_DETACH_L;
}

/* lua_copy() */
void jcall_copy(JNIEnv *env, jobject obj, jint from_index, jint to_index)
{
	JNLUA_ENV_L;
	if (checkindex(L, from_index) && checkindex(L, to_index))
	{
		lua_copy(L, from_index, to_index);
	}
	JNLUA_DETACH_L;
}

/* lua_gettop() */
jint jcall_gettop(JNIEnv *env, jobject obj)
{
	JNLUA_ENV_L;
	jint rtn = (jint)lua_gettop(L);

	JNLUA_DETACH_L;
	return rtn;
}

/* lua_insert() */
void jcall_insert(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkrealindex(L, index))
	{
		lua_insert(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_pop() */
void jcall_pop(JNIEnv *env, jobject obj, jint n)
{
	JNLUA_ENV_L;
	if (checkarg(n >= 0 && n <= lua_gettop(L), "illegal count"))
	{
		lua_pop(L, n);
	}
	JNLUA_DETACH_L;
}

/* lua_pushvalue() */
void jcall_pushvalue(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		lua_pushvalue(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_remove() */
void jcall_remove(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkrealindex(L, index))
	{
		lua_remove(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_replace() */
void jcall_replace(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkindex(L, index) && checknelems(L, 1))
	{
		lua_replace(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_settop() */
void jcall_settop(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if ((index >= 0 && (index <= lua_gettop(L) || checkstack(L, index - lua_gettop(L)))) || (index < 0 && checkrealindex(L, index)))
	{
		lua_settop(L, index);
	}
	JNLUA_DETACH_L;
}

/* ---- Table ---- */
/* lua_createtable() */
JNLUA_THREADLOCAL int createtable_narr;
JNLUA_THREADLOCAL int createtable_nrec;
static int createtable_protected(lua_State *L)
{
	lua_createtable(L, createtable_narr, createtable_nrec);
	return 1;
}
void jcall_createtable(JNIEnv *env, jobject obj, jint narr, jint nrec)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkarg(narr >= 0, "illegal array count") && checkarg(nrec >= 0, "illegal record count"))
	{
		createtable_narr = narr;
		createtable_nrec = nrec;
		lua_pushcfunction(L, createtable_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	JNLUA_DETACH_L;
}

/* lua_findtable() */
JNLUA_THREADLOCAL const char *findtable_fname;
JNLUA_THREADLOCAL int findtable_szhint;
JNLUA_THREADLOCAL const char *findtable_result;
static int findtable_protected(lua_State *L)
{
	findtable_result = luaL_findtable(L, 1, findtable_fname, findtable_szhint);
	return findtable_result ? 0 : 1;
}
jstring jcall_findtable(JNIEnv *env, jobject obj, jint index, jstring fname, int szhint)
{
	JNLUA_ENV_L;
	findtable_fname = NULL;
	findtable_result = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index) && (findtable_fname = getstringchars(fname)) && checkarg(szhint >= 0, "illegal size hint"))
	{
		findtable_szhint = szhint;
		index = lua_absindex(L, index);
		lua_pushcfunction(L, findtable_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, LUA_MULTRET);
	}
	if (findtable_fname)
	{
		releasestringchars(fname, findtable_fname);
	}
	jstring rtn = findtable_result ? (*thread_env)->NewStringUTF(thread_env, findtable_result) : NULL;
	JNLUA_DETACH_L;
	return rtn;
}

/* lua_getfield() */
JNLUA_THREADLOCAL const char *getfield_k;
static int getfield_protected(lua_State *L)
{
	lua_getfield(L, 1, getfield_k);
	return 1;
}
void jcall_getfield(JNIEnv *env, jobject obj, jint index, jstring k)
{
	JNLUA_ENV_L;
	getfield_k = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE) && (getfield_k = getstringchars(k)))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, getfield_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 1);
	}
	if (getfield_k)
	{
		releasestringchars(k, getfield_k);
	}
	JNLUA_DETACH_L;
}

/* lua_gettable() */
static int gettable_protected(lua_State *L)
{
	lua_gettable(L, 1);
	return 1;
}
void jcall_gettable(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, gettable_protected);
		lua_insert(L, -2);
		lua_pushvalue(L, index);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 2, 1);
	}
	JNLUA_DETACH_L;
}

/* lua_newtable() */
static int newtable_protected(lua_State *L)
{
	lua_newtable(L);
	return 1;
}
void jcall_newtable(JNIEnv *env, jobject obj)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushcfunction(L, newtable_protected);
		JNLUA_PCALL(L, 0, 1);
	}
	JNLUA_DETACH_L;
}

/* lua_next() */
JNLUA_THREADLOCAL int next_result;
static int next_protected(lua_State *L)
{
	next_result = lua_next(L, 1);
	return next_result ? 2 : 0;
}
jint jcall_next(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, next_protected);
		lua_insert(L, -2);
		lua_pushvalue(L, index);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 2, LUA_MULTRET);
	}
	JNLUA_DETACH_L;
	return (jint)next_result;
}

/* lua_rawget() */
void jcall_rawget(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checktype(L, index, LUA_TTABLE))
	{
		lua_rawget(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_rawgeti() */
void jcall_rawgeti(JNIEnv *env, jobject obj, jint index, jint n)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		lua_rawgeti(L, index, n);
	}
	JNLUA_DETACH_L;
}

/* lua_rawset() */
static int rawset_protected(lua_State *L)
{
	lua_rawset(L, 1);
	return 0;
}
void jcall_rawset(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE) && checknelems(L, 2))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, rawset_protected);
		lua_insert(L, -3);
		lua_pushvalue(L, index);
		lua_insert(L, -3);
		JNLUA_PCALL(L, 3, 0);
	}
	JNLUA_DETACH_L;
}

/* lua_rawseti() */
JNLUA_THREADLOCAL int rawseti_n;
static int rawseti_protected(lua_State *L)
{
	lua_rawseti(L, 1, rawseti_n);
	return 0;
}
void jcall_rawseti(JNIEnv *env, jobject obj, jint index, jint n)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		rawseti_n = n;
		index = lua_absindex(L, index);
		lua_pushcfunction(L, rawseti_protected);
		lua_insert(L, -2);
		lua_pushvalue(L, index);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 2, 0);
	}
	JNLUA_DETACH_L;
}

/* lua_settable() */
static int settable_protected(lua_State *L)
{
	lua_settable(L, 1);
	return 0;
}
void jcall_settable(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE) && checknelems(L, 2))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, settable_protected);
		lua_insert(L, -3);
		lua_pushvalue(L, index);
		lua_insert(L, -3);
		JNLUA_PCALL(L, 3, 0);
	}
	JNLUA_DETACH_L;
}

/* lua_setfield() */
JNLUA_THREADLOCAL const char *setfield_k;
static int setfield_protected(lua_State *L)
{
	lua_setfield(L, 1, setfield_k);
	return 0;
}
void jcall_setfield(JNIEnv *env, jobject obj, jint index, jstring k)
{
	JNLUA_ENV_L;
	setfield_k = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE) && (setfield_k = getstringchars(k)))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, setfield_protected);
		lua_insert(L, -2);
		lua_pushvalue(L, index);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 2, 0);
	}
	if (setfield_k)
	{
		releasestringchars(k, setfield_k);
	}
	JNLUA_DETACH_L;
}

/* ---- Metatable ---- */
/* lua_getmetatable() */
int jcall_getmetatable(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	int result = 0;
	if (lua_checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		result = lua_getmetatable(L, index);
	}
	JNLUA_DETACH_L;
	return (jint)result;
}

/* lua_setmetatable() */
void jcall_setmetatable(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkindex(L, index) && checknelems(L, 1) && checkarg(lua_type(L, -1) == LUA_TTABLE || lua_type(L, -1) == LUA_TNIL, "illegal type"))
	{
		lua_setmetatable(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_getmetafield() */
JNLUA_THREADLOCAL const char *getmetafield_k;
int getmetafield_result;
static int getmetafield_protected(lua_State *L)
{
	getmetafield_result = luaL_getmetafield(L, 1, getmetafield_k);
	return getmetafield_result ? 1 : 0;
}
jint jcall_getmetafield(JNIEnv *env, jobject obj, jint index, jstring k)
{
	JNLUA_ENV_L;
	getmetafield_k = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index) && (getmetafield_k = getstringchars(k)))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, getmetafield_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, LUA_MULTRET);
	}
	if (getmetafield_k)
	{
		releasestringchars(k, getmetafield_k);
	}
	JNLUA_DETACH_L;
	return (jint)getmetafield_result;
}

/* ---- Function environment ---- */
/* lua_getfenv() */
void jcall_getfenv(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checkindex(L, index))
	{
		lua_getfenv(L, index);
	}
	JNLUA_DETACH_L;
}

/* lua_setfenv() */
jint jcall_setfenv(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	int result = 0;
	if (checkindex(L, index) && checktype(L, -1, LUA_TTABLE))
	{
		result = lua_setfenv(L, index);
	}
	JNLUA_DETACH_L;
	return (jint)result;
}

/* ---- Thread ---- */
/* lua_newthread() */
static int newthread_protected(lua_State *L)
{
	lua_State *T;

	T = lua_newthread(L);
	lua_insert(L, 1);
	lua_xmove(L, T, 1);
	return 1;
}
void jcall_newthread(JNIEnv *env, jobject obj)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, -1, LUA_TFUNCTION))
	{
		lua_pushcfunction(L, newthread_protected);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 1, 1);
	}
	JNLUA_DETACH_L;
}

/* lua_resume() */
jint jcall_resume(JNIEnv *env, jobject obj, jint index, jint nargs)
{
	JNLUA_ENV_L;
	lua_State *T;
	int status;
	int nresults = 0;
	if (checktype(L, index, LUA_TTHREAD) && checkarg(nargs >= 0, "illegal argument count") && checknelems(L, nargs + 1))
	{
		T = lua_tothread(L, index);
		if (checkstack(T, nargs))
		{
			lua_xmove(L, T, nargs);
			status = lua_resume(T, nargs);
			switch (status)
			{
			case 0:
			case LUA_YIELD:
				nresults = lua_gettop(T);
				if (checkstack(L, nresults))
				{
					lua_xmove(T, L, nresults);
				}
				break;
			default:
				throw(L, status);
			}
		}
	}
	JNLUA_DETACH_L;
	return (jint)nresults;
}

/* lua_status() */
jint jcall_status(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	int result = 0;
	if (checktype(L, index, LUA_TTHREAD))
	{
		result = lua_status(lua_tothread(L, index));
	}
	JNLUA_DETACH_L;
	return (jint)result;
}

/* lua_yield() */
jint jcall_yield(JNIEnv *env, jobject obj, int nresults)
{
	JNLUA_ENV_L;
	int result = 0;
	if (checkarg(nresults >= 0, "illegal return count") && checknelems(L, nresults) && checkstate(L != getluastate(obj), "not in a thread"))
	{
		result = lua_yield(L, nresults);
	}
	JNLUA_DETACH_L;
	return (jint)result;
}

/* ---- Reference ---- */
/* lua_ref() */
JNLUA_THREADLOCAL int ref_result;
static int ref_protected(lua_State *L)
{
	ref_result = luaL_ref(L, 1);
	return 0;
}
jint jcall_ref(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, ref_protected);
		lua_insert(L, -2);
		lua_pushvalue(L, index);
		lua_insert(L, -2);
		JNLUA_PCALL(L, 2, 0);
	}
	JNLUA_DETACH_L;
	return (jint)ref_result;
}

/* lua_unref() */
JNLUA_THREADLOCAL int unref_ref;
static int unref_protected(lua_State *L)
{
	luaL_unref(L, 1, unref_ref);
	return 0;
}
void jcall_unref(JNIEnv *env, jobject obj, jint index, jint ref)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		unref_ref = ref;
		index = lua_absindex(L, index);
		lua_pushcfunction(L, unref_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	JNLUA_DETACH_L;
}

jobject jcall_getstack(JNIEnv *env, jobject obj, jint level)
{
	JNLUA_ENV_L;
	lua_Debug *ar = NULL;
	jobject result = NULL;
	if (checkarg(level >= 0, "illegal level"))
	{
		ar = malloc(sizeof(lua_Debug));
		if (ar)
		{
			memset(ar, 0, sizeof(lua_Debug));
			if (lua_getstack(L, level, ar))
			{
				result = (*thread_env)->NewObject(thread_env, luadebug_class, luadebug_init_id, (jlong)(uintptr_t)ar, JNI_TRUE);
			}
		}
	}
	if (!result)
	{
		free(ar);
	}
	JNLUA_DETACH_L;
	return result;
}

/* lua_getinfo() */
JNLUA_THREADLOCAL const char *getinfo_what;
JNLUA_THREADLOCAL jobject getinfo_ar;
JNLUA_THREADLOCAL int getinfo_result;
/* Returns the Lua debug structure in a Java debug object. */
static lua_Debug *getluadebug(jobject javadebug)
{
	return (lua_Debug *)(uintptr_t)(*thread_env)->GetLongField(thread_env, javadebug, luadebug_field_id);
}
static int getinfo_protected(lua_State *L)
{
	getinfo_result = lua_getinfo(L, getinfo_what, getluadebug(getinfo_ar));
	return 0;
}
jint jcall_getinfo(JNIEnv *env, jobject obj, jstring what, jobject ar)
{
	JNLUA_ENV_L;
	getinfo_what = NULL;
	if (checkstack(L, JNLUA_MINSTACK) && (getinfo_what = getstringchars(what)) && checknotnull(ar))
	{
		getinfo_ar = ar;
		lua_pushcfunction(L, getinfo_protected);
		JNLUA_PCALL(L, 0, 0);
	}
	if (getinfo_what)
	{
		releasestringchars(what, getinfo_what);
	}
	(*thread_env)->DeleteLocalRef(thread_env,what);
	(*thread_env)->DeleteLocalRef(thread_env,ar);
	JNLUA_DETACH_L;
	return getinfo_result;
}

/* ---- Function arguments ---- */
/* Returns the current function name. */
JNLUA_THREADLOCAL const char *funcname_result;
static int funcname_protected(lua_State *L)
{
	lua_Debug ar;

	if (lua_getstack(L, 1, &ar) && lua_getinfo(L, "n", &ar))
	{
		funcname_result = ar.name;
	}
	return 0;
}
jstring jcall_funcname(JNIEnv *env, jobject obj)
{
	JNLUA_ENV_L;
	funcname_result = NULL;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushcfunction(L, funcname_protected);
		JNLUA_PCALL(L, 0, 0);
	}
	jstring rtn = funcname_result ? (*thread_env)->NewStringUTF(thread_env, funcname_result) : NULL;
	JNLUA_DETACH_L;
	return rtn;
}

/* Returns the effective argument number, adjusting for methods. */
JNLUA_THREADLOCAL int narg_result;
static int narg_protected(lua_State *L)
{
	lua_Debug ar;

	if (lua_getstack(L, 1, &ar) && lua_getinfo(L, "n", &ar))
	{
		if (ar.namewhat && strcmp(ar.namewhat, "method") == 0)
		{
			narg_result--;
		}
	}
	return 0;
}
jint jcall_narg(JNIEnv *env, jobject obj, jint narg)
{
	JNLUA_ENV_L;
	narg_result = narg;
	if (checkstack(L, JNLUA_MINSTACK))
	{
		lua_pushcfunction(L, narg_protected);
		JNLUA_PCALL(L, 0, 0);
	}
	JNLUA_DETACH_L;
	return (jint)narg_result;
}

/* ---- Optimization ---- */
/* lua_tablesize() */
JNLUA_THREADLOCAL int tablesize_result;
static int tablesize_protected(lua_State *L)
{
	int count = 0;

	lua_pushnil(L);
	while (lua_next(L, -2))
	{
		lua_pop(L, 1);
		count++;
	}
	tablesize_result = count;
	return 0;
}
jint jcall_tablesize(JNIEnv *env, jobject obj, jint index)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE))
	{
		index = lua_absindex(L, index);
		lua_pushcfunction(L, tablesize_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	JNLUA_DETACH_L;
	return (jint)tablesize_result;
}

/* lua_tablemove() */
JNLUA_THREADLOCAL int tablemove_from;
JNLUA_THREADLOCAL int tablemove_to;
JNLUA_THREADLOCAL int tablemove_count;
static int tablemove_protected(lua_State *L)
{
	int from = tablemove_from, to = tablemove_to;
	int count = tablemove_count, i;

	if (from < to)
	{
		for (i = count - 1; i >= 0; i--)
		{
			lua_rawgeti(L, 1, from + i);
			lua_rawseti(L, 1, to + i);
		}
	}
	else if (from > to)
	{
		for (i = 0; i < count; i++)
		{
			lua_rawgeti(L, 1, from + i);
			lua_rawseti(L, 1, to + i);
		}
	}
	return 0;
}
void jcall_tablemove(JNIEnv *env, jobject obj, jint index, jint from, jint to, jint count)
{
	JNLUA_ENV_L;
	if (checkstack(L, JNLUA_MINSTACK) && checktype(L, index, LUA_TTABLE) && checkarg(count >= 0, "illegal count"))
	{
		tablemove_from = from;
		tablemove_to = to;
		tablemove_count = count;
		index = lua_absindex(L, index);
		lua_pushcfunction(L, tablemove_protected);
		lua_pushvalue(L, index);
		JNLUA_PCALL(L, 1, 0);
	}
	JNLUA_DETACH_L;
}

/* ---- Debug structure ---- */
/* Sets the Lua debug structure in a Java debug object. */
static void setluadebug(jobject javadebug, lua_Debug *ar)
{
	(*thread_env)->SetLongField(thread_env, javadebug, luadebug_field_id, (jlong)(uintptr_t)ar);
}

/* lua_debugfree() */
void jcall_debugfree(JNIEnv *env, jobject obj)
{
	lua_Debug *ar;

	JNLUA_ENV;
	ar = getluadebug(obj);
	setluadebug(obj, NULL);
	free(ar);
	JNLUA_DETACH;
}

/* lua_debugname() */
jstring jcall_debugname(JNIEnv *env, jobject obj)
{
	lua_Debug *ar;

	JNLUA_ENV;
	ar = getluadebug(obj);
	jstring rtn = ar != NULL && ar->name != NULL ? (*thread_env)->NewStringUTF(thread_env, ar->name) : NULL;
	JNLUA_DETACH;
	return rtn;
}

/* lua_debugnamewhat() */
jstring jcall_debugnamewhat(JNIEnv *env, jobject obj)
{
	lua_Debug *ar;

	JNLUA_ENV;
	ar = getluadebug(obj);
	jstring rtn = ar != NULL && ar->namewhat != NULL ? (*thread_env)->NewStringUTF(thread_env, ar->namewhat) : NULL;
	JNLUA_DETACH;
	return rtn;
}

static JNINativeMethod luastate_native_map[] = {
	{"lua_absindex", "(I)I", (void *)jcall_absindex},
	{"lua_close", "(Z)V", (void *)jcall_close},
	{"lua_concat", "(I)V", (void *)jcall_concat},
	{"lua_copy", "(II)V", (void *)jcall_copy},
	{"lua_createtable", "(II)V", (void *)jcall_createtable},
	{"lua_dump", "(Ljava/io/OutputStream;)V", (void *)jcall_dump},
	{"lua_equal", "(II)I", (void *)jcall_equal},
	{"lua_findtable", "(ILjava/lang/String;I)Ljava/lang/String;", (void *)jcall_findtable},
	{"lua_funcname", "()Ljava/lang/String;", (void *)jcall_funcname},
	{"lua_gc", "(II)I", (void *)jcall_gc},
	{"lua_getfenv", "(I)V", (void *)jcall_getfenv},
	{"lua_getfield", "(ILjava/lang/String;)V", (void *)jcall_getfield},
	{"lua_getglobal", "(Ljava/lang/String;)V", (void *)jcall_getglobal},
	{"lua_getinfo", "(Ljava/lang/String;Lcom/naef/jnlua/LuaState$LuaDebug;)I", (void *)jcall_getinfo},
	{"lua_getmetafield", "(ILjava/lang/String;)I", (void *)jcall_getmetafield},
	{"lua_getmetatable", "(I)I", (void *)jcall_getmetatable},
	{"lua_getstack", "(I)Lcom/naef/jnlua/LuaState$LuaDebug;", (void *)jcall_getstack},
	{"lua_gettable", "(I)V", (void *)jcall_gettable},
	{"lua_gettop", "()I", (void *)jcall_gettop},
	{"lua_insert", "(I)V", (void *)jcall_insert},
	{"lua_isboolean", "(I)I", (void *)jcall_isboolean},
	{"lua_iscfunction", "(I)I", (void *)jcall_iscfunction},
	{"lua_isfunction", "(I)I", (void *)jcall_isfunction},
	{"lua_isjavafunction", "(I)I", (void *)jcall_isjavafunction},
	{"lua_isjavaobject", "(I)I", (void *)jcall_isjavaobject},
	{"lua_isnil", "(I)I", (void *)jcall_isnil},
	{"lua_isnone", "(I)I", (void *)jcall_isnone},
	{"lua_isnoneornil", "(I)I", (void *)jcall_isnoneornil},
	{"lua_isnumber", "(I)I", (void *)jcall_isnumber},
	{"lua_isstring", "(I)I", (void *)jcall_isstring},
	{"lua_istable", "(I)I", (void *)jcall_istable},
	{"lua_isthread", "(I)I", (void *)jcall_isthread},
	{"lua_lessthan", "(II)I", (void *)jcall_lessthan},
	{"lua_load", "(Ljava/io/InputStream;Ljava/lang/String;Ljava/lang/String;)V", (void *)jcall_load},
	{"lua_narg", "(I)I", (void *)jcall_narg},
	{"lua_newstate", "(IJ)V", (void *)jcall_newstate},
	{"lua_newtable", "()V", (void *)jcall_newtable},
	{"lua_newthread", "()V", (void *)jcall_newthread},
	{"lua_next", "(I)I", (void *)jcall_next},
	{"lua_objlen", "(I)I", (void *)jcall_objlen},
	{"lua_openlib", "(I)V", (void *)jcall_openlib},
	{"lua_openlibs", "()V", (void *)jcall_openlibs},
	{"lua_pcall", "(II)V", (void *)jcall_pcall},
	{"lua_pop", "(I)V", (void *)jcall_pop},
	{"lua_pushboolean", "(I)V", (void *)jcall_pushboolean},
	{"lua_pushbytearray", "([B)V", (void *)jcall_pushbytearray},
	{"lua_pushinteger", "(J)V", (void *)jcall_pushinteger},
	{"lua_pushjavafunction", "(Lcom/naef/jnlua/JavaFunction;)V", (void *)jcall_pushjavafunction},
	{"lua_pushjavaobject", "(Ljava/lang/Object;)V", (void *)jcall_pushjavaobject},
	{"lua_pushjavaobjectl", "(Ljava/lang/Object;Ljava/lang/String;)V", (void *)jcall_pushjavaobjectl},
	{"lua_pushnil", "()V", (void *)jcall_pushnil},
	{"lua_pushnumber", "(D)V", (void *)jcall_pushnumber},
	{"lua_pushstring", "(Ljava/lang/String;)V", (void *)jcall_pushstring},
	{"lua_pushstr2num", "(Ljava/lang/String;)V", (void *)jcall_pushstr2num},
	{"lua_pushvalue", "(I)V", (void *)jcall_pushvalue},
	{"lua_rawequal", "(II)I", (void *)jcall_rawequal},
	{"lua_rawget", "(I)V", (void *)jcall_rawget},
	{"lua_rawgeti", "(II)V", (void *)jcall_rawgeti},
	{"lua_rawset", "(I)V", (void *)jcall_rawset},
	{"lua_rawseti", "(II)V", (void *)jcall_rawseti},
	{"lua_ref", "(I)I", (void *)jcall_ref},
	{"lua_registryindex", "()I", (void *)jcall_registryindex},
	{"lua_remove", "(I)V", (void *)jcall_remove},
	{"lua_replace", "(I)V", (void *)jcall_replace},
	{"lua_resume", "(II)I", (void *)jcall_resume},
	{"lua_setfenv", "(I)I", (void *)jcall_setfenv},
	{"lua_setfield", "(ILjava/lang/String;)V", (void *)jcall_setfield},
	{"lua_setglobal", "(Ljava/lang/String;)V", (void *)jcall_setglobal},
	{"lua_setmetatable", "(I)V", (void *)jcall_setmetatable},
	{"lua_settable", "(I)V", (void *)jcall_settable},
	{"lua_settop", "(I)V", (void *)jcall_settop},
	{"lua_status", "(I)I", (void *)jcall_status},
	{"lua_tablemove", "(IIII)V", (void *)jcall_tablemove},
	{"lua_tablesize", "(I)I", (void *)jcall_tablesize},
	{"lua_toboolean", "(I)I", (void *)jcall_toboolean},
	{"lua_tobytearray", "(I)[B", (void *)jcall_tobytearray},
	{"lua_tointeger", "(I)J", (void *)jcall_tointeger},
	{"lua_tointegerx", "(I)Ljava/lang/Long;", (void *)jcall_tointegerx},
	{"lua_tojavafunction", "(I)Lcom/naef/jnlua/JavaFunction;", (void *)jcall_tojavafunction},
	{"lua_tojavaobject", "(I)Ljava/lang/Object;", (void *)jcall_tojavaobject},
	{"lua_tonumber", "(I)D", (void *)jcall_tonumber},
	{"lua_tonumberx", "(I)Ljava/lang/Double;", (void *)jcall_tonumberx},
	{"lua_topointer", "(I)J", (void *)jcall_topointer},
	{"lua_tostring", "(I)Ljava/lang/String;", (void *)jcall_tostring},
	{"lua_type", "(I)I", (void *)jcall_type},
	{"lua_unref", "(II)V", (void *)jcall_unref},
	{"lua_version", "()Ljava/lang/String;", (void *)jcall_version},
	{"lua_yield", "(I)I", (void *)jcall_yield}};

static JNINativeMethod luadebug_native_map[] = {
	{"lua_debugfree", "()V", (void *)jcall_debugfree},
	{"lua_debugname", "()Ljava/lang/String;", (void *)jcall_debugname},
	{"lua_debugnamewhat", "()Ljava/lang/String;", (void *)jcall_debugnamewhat}};
/* ---- JNI ---- */
/* Handles the loading of this library. */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
	JNIEnv *env;

	/* Ansca: Store the Java VM pointer to a global. To be used to safely fetch a JNIEnv pointer for the current thread. */
	java_vm = vm;

	/* Get environment */
	env = get_jni_env();

	(*env)->EnsureLocalCapacity(env, 512);
	(*env)->PushLocalFrame(env, 256);
	/* Lookup and pin classes, fields and methods */
	if (!(luastate_class = referenceclass(env, "com/naef/jnlua/LuaState")) || !(luastate_id = (*env)->GetFieldID(env, luastate_class, "luaState", "J")) || !(luathread_id = (*env)->GetFieldID(env, luastate_class, "luaThread", "J")) || !(luamemorytotal_id = (*env)->GetFieldID(env, luastate_class, "luaMemoryTotal", "I")) || !(luamemoryused_id = (*env)->GetFieldID(env, luastate_class, "luaMemoryUsed", "I")) || !(yield_id = (*env)->GetFieldID(env, luastate_class, "yield", "Z")))
	{
		luastate_class = NULL;
		return JNLUA_JNIVERSION;
	}
	(*env)->RegisterNatives(env, luastate_class, luastate_native_map, sizeof(luastate_native_map) / sizeof(luastate_native_map[0]));

	if (!(print_id = (*env)->GetStaticMethodID(env, luastate_class, "println", "(Ljava/lang/String;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luadebug_class = referenceclass(env, "com/naef/jnlua/LuaState$LuaDebug")) || !(luadebug_init_id = (*env)->GetMethodID(env, luadebug_class, "<init>", "(JZ)V")) || !(luadebug_field_id = (*env)->GetFieldID(env, luadebug_class, "luaDebug", "J")))
	{
		luadebug_class = NULL;
		return JNLUA_JNIVERSION;
	}
	(*env)->RegisterNatives(env, luadebug_class, luadebug_native_map, sizeof(luadebug_native_map) / sizeof(luadebug_native_map[0]));

	if (!(javafunction_interface = referenceclass(env, "com/naef/jnlua/JavaFunction")) || !(invoke_id = (*env)->GetMethodID(env, javafunction_interface, "invoke", "(Lcom/naef/jnlua/LuaState;)I")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luaruntimeexception_class = referenceclass(env, "com/naef/jnlua/LuaRuntimeException")) || !(luaruntimeexception_id = (*env)->GetMethodID(env, luaruntimeexception_class, "<init>", "(Ljava/lang/String;)V")) || !(setluaerror_id = (*env)->GetMethodID(env, luaruntimeexception_class, "setLuaError", "(Lcom/naef/jnlua/LuaError;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luasyntaxexception_class = referenceclass(env, "com/naef/jnlua/LuaSyntaxException")) || !(luasyntaxexception_id = (*env)->GetMethodID(env, luasyntaxexception_class, "<init>", "(Ljava/lang/String;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luamemoryallocationexception_class = referenceclass(env, "com/naef/jnlua/LuaMemoryAllocationException")) || !(luamemoryallocationexception_id = (*env)->GetMethodID(env, luamemoryallocationexception_class, "<init>", "(Ljava/lang/String;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luagcmetamethodexception_class = referenceclass(env, "com/naef/jnlua/LuaGcMetamethodException")) || !(luagcmetamethodexception_id = (*env)->GetMethodID(env, luagcmetamethodexception_class, "<init>", "(Ljava/lang/String;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luamessagehandlerexception_class = referenceclass(env, "com/naef/jnlua/LuaMessageHandlerException")) || !(luamessagehandlerexception_id = (*env)->GetMethodID(env, luamessagehandlerexception_class, "<init>", "(Ljava/lang/String;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luastacktraceelement_class = referenceclass(env, "com/naef/jnlua/LuaStackTraceElement")) || !(luastacktraceelement_id = (*env)->GetMethodID(env, luastacktraceelement_class, "<init>", "(Ljava/lang/String;Ljava/lang/String;I)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(luaerror_class = referenceclass(env, "com/naef/jnlua/LuaError")) || !(luaerror_id = (*env)->GetMethodID(env, luaerror_class, "<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V")) || !(setluastacktrace_id = (*env)->GetMethodID(env, luaerror_class, "setLuaStackTrace", "([Lcom/naef/jnlua/LuaStackTraceElement;)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(nullpointerexception_class = referenceclass(env, "java/lang/NullPointerException")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(illegalargumentexception_class = referenceclass(env, "java/lang/IllegalArgumentException")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(illegalstateexception_class = referenceclass(env, "java/lang/IllegalStateException")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(error_class = referenceclass(env, "java/lang/Error")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(integer_class = referenceclass(env, "java/lang/Long")) || !(valueof_integer_id = (*env)->GetStaticMethodID(env, integer_class, "valueOf", "(J)Ljava/lang/Long;")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(double_class = referenceclass(env, "java/lang/Double")) || !(valueof_double_id = (*env)->GetStaticMethodID(env, double_class, "valueOf", "(D)Ljava/lang/Double;")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(inputstream_class = referenceclass(env, "java/io/InputStream")) || !(read_id = (*env)->GetMethodID(env, inputstream_class, "read", "([B)I")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(outputstream_class = referenceclass(env, "java/io/OutputStream")) || !(write_id = (*env)->GetMethodID(env, outputstream_class, "write", "([BII)V")))
	{
		return JNLUA_JNIVERSION;
	}
	if (!(ioexception_class = referenceclass(env, "java/io/IOException")))
	{
		return JNLUA_JNIVERSION;
	}

	/* OK */
	(*env)->PopLocalFrame(env, NULL);
	initialized = 1;
	return JNLUA_JNIVERSION;
}

/* Handles the unloading of this library. */
JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *vm, void *reserved)
{
	JNIEnv *env;

	/* Get environment */
	env = get_jni_env();

	/* Free classes */
	if (luastate_class)
	{
		(*env)->UnregisterNatives(env, luastate_class);
		(*env)->DeleteGlobalRef(env, luastate_class);
	}
	if (luadebug_class)
	{
		(*env)->UnregisterNatives(env, luadebug_class);
		(*env)->DeleteGlobalRef(env, luadebug_class);
	}
	if (javafunction_interface)
	{
		(*env)->DeleteGlobalRef(env, javafunction_interface);
	}
	if (luaruntimeexception_class)
	{
		(*env)->DeleteGlobalRef(env, luaruntimeexception_class);
	}
	if (luasyntaxexception_class)
	{
		(*env)->DeleteGlobalRef(env, luasyntaxexception_class);
	}
	if (luamemoryallocationexception_class)
	{
		(*env)->DeleteGlobalRef(env, luamemoryallocationexception_class);
	}
	if (luagcmetamethodexception_class)
	{
		(*env)->DeleteGlobalRef(env, luagcmetamethodexception_class);
	}
	if (luamessagehandlerexception_class)
	{
		(*env)->DeleteGlobalRef(env, luamessagehandlerexception_class);
	}
	if (luastacktraceelement_class)
	{
		(*env)->DeleteGlobalRef(env, luastacktraceelement_class);
	}
	if (luaerror_class)
	{
		(*env)->DeleteGlobalRef(env, luaerror_class);
	}
	if (nullpointerexception_class)
	{
		(*env)->DeleteGlobalRef(env, nullpointerexception_class);
	}
	if (illegalargumentexception_class)
	{
		(*env)->DeleteGlobalRef(env, illegalargumentexception_class);
	}
	if (illegalstateexception_class)
	{
		(*env)->DeleteGlobalRef(env, illegalstateexception_class);
	}
	if (error_class)
	{
		(*env)->DeleteGlobalRef(env, error_class);
	}
	if (integer_class)
	{
		(*env)->DeleteGlobalRef(env, integer_class);
	}
	if (double_class)
	{
		(*env)->DeleteGlobalRef(env, double_class);
	}
	if (inputstream_class)
	{
		(*env)->DeleteGlobalRef(env, inputstream_class);
	}
	if (outputstream_class)
	{
		(*env)->DeleteGlobalRef(env, outputstream_class);
	}
	if (ioexception_class)
	{
		(*env)->DeleteGlobalRef(env, ioexception_class);
	}

	/* Ansca: Release the pointer to the Java VM. */
	java_vm = NULL;
}

/* ---- JNI helpers ---- */
/* Finds a class and returns a new JNI global reference to it. */
static jclass referenceclass(JNIEnv *env, const char *className)
{
	jclass clazz;

	clazz = (*env)->FindClass(env, className);
	if (!clazz)
	{
		return NULL;
	}
	return (*env)->NewGlobalRef(env, clazz);
}

/* Return a new JNI byte array. */
static jbyteArray newbytearray(jsize length)
{
	jbyteArray array;

	array = (*thread_env)->NewByteArray(thread_env, length);
	if (!check(array != NULL, luamemoryallocationexception_class, "JNI error: NewByteArray() failed"))
	{
		return NULL;
	}
	return array;
}

/* Returns the  UTF chars of a string. */
static const char *getstringchars(jstring string)
{
	const char *utf;

	if (!checknotnull(string))
	{
		return NULL;
	}
	utf = (*thread_env)->GetStringUTFChars(thread_env, string, NULL);
	if (!check(utf != NULL, luamemoryallocationexception_class, "JNI error: GetStringUTFChars() failed"))
	{
		return NULL;
	}
	return utf;
}

/* Releaes the UTF chars of a string. */
static void releasestringchars(jstring string, const char *chars)
{
	(*thread_env)->ReleaseStringUTFChars(thread_env, string, chars);
	(*thread_env)->DeleteLocalRef(thread_env, string);
}

/* ---- Java state operations ---- */
/* Returns the Lua state from the Java state. */
static lua_State *getluastate(jobject javastate)
{
	luastate_obj = javastate;
	return (lua_State *)(uintptr_t)(*thread_env)->GetLongField(thread_env, javastate, luastate_id);
}

/* Sets the Lua state in the Java state. */
static void setluastate(jobject javastate, lua_State *L)
{
	(*thread_env)->SetLongField(thread_env, javastate, luastate_id, (jlong)(uintptr_t)L);
}

/* Returns the Lua thread from the Java state. */
static lua_State *getluathread(jobject javastate)
{
	luastate_obj = javastate;
	return (lua_State *)(uintptr_t)(*thread_env)->GetLongField(thread_env, javastate, luathread_id);
}

/* Sets the Lua state in the Java state. */
static void setluathread(jobject javastate, lua_State *L)
{
	(*thread_env)->SetLongField(thread_env, javastate, luathread_id, (jlong)(uintptr_t)L);
}

/* Gets the amount of ram available and used for and by the current Lua state. */
static void getluamemory(jint *total, jint *used)
{
	*total = (*thread_env)->GetIntField(thread_env, luastate_obj, luamemorytotal_id);
	*used = (*thread_env)->GetIntField(thread_env, luastate_obj, luamemoryused_id);
}
/* Sets the amount of ram used by the current Lua state (called by allocator). */
static void setluamemoryused(jint used)
{
	(*thread_env)->SetIntField(thread_env, luastate_obj, luamemoryused_id, used);
}

/* Returns the yield flag from the Java state */
static int getyield(jobject javastate)
{
	return (int)(*thread_env)->GetBooleanField(thread_env, javastate, yield_id);
}

/* Sets the yield flag in the Java state */
static void setyield(jobject javastate, int yield)
{
	(*thread_env)->SetBooleanField(thread_env, javastate, yield_id, (jboolean)yield);
}

/* ---- Checks ---- */
/* Returns whether an index is valid. */
static int validindex(lua_State *L, int index)
{
	int top;

	top = lua_gettop(L);
	if (index <= 0)
	{
		if (index > LUA_REGISTRYINDEX)
		{
			index = top + index + 1;
		}
		else
		{
			switch (index)
			{
			case LUA_REGISTRYINDEX:
			case LUA_ENVIRONINDEX:
			case LUA_GLOBALSINDEX:
				return 1;
			default:
				return 0; /* C upvalue access not needed, don't even validate */
			}
		}
	}
	return index >= 1 && index <= top;
}

/* Checks stack space. */
static int checkstack(lua_State *L, int space)
{
	return check(lua_checkstack(L, space), illegalstateexception_class, "stack overflow");
}

/* Checks if an index is valid. */
static int checkindex(lua_State *L, int index)
{
	return checkarg(validindex(L, index), "illegal index");
}

/* Checks if an index is valid, ignoring pseudo indexes. */
static int checkrealindex(lua_State *L, int index)
{
	int top;

	top = lua_gettop(L);
	if (index <= 0)
	{
		index = top + index + 1;
	}
	return checkarg(index >= 1 && index <= top, "illegal index");
}

/* Checks the type of a stack value. */
static int checktype(lua_State *L, int index, int type)
{
	return checkindex(L, index) && checkarg(lua_type(L, index) == type, "illegal type");
}

/* Checks that there are at least n values on the stack. */
static int checknelems(lua_State *L, int n)
{
	return checkstate(lua_gettop(L) >= n, "stack underflow");
}

/* Checks an argument for not-null. */
static int checknotnull(void *object)
{
	return check(object != NULL, nullpointerexception_class, "null");
}

/* Checks an argument condition. */
static int checkarg(int cond, const char *msg)
{
	return check(cond, illegalargumentexception_class, msg);
}

/* Checks a state condition. */
static int checkstate(int cond, const char *msg)
{
	return check(cond, illegalstateexception_class, msg);
}

/* Checks a condition. */
static int check(int cond, jthrowable throwable_class, const char *msg)
{
	if (cond)
	{
		return 1;
	}
	(*thread_env)->ThrowNew(thread_env, throwable_class, msg);
	return 0;
}

/* ---- Java objects and functions ---- */
/* Pushes a Java object on the stack. */
static void pushjavaobject(lua_State *L, jobject object)
{
	jobject *user_data;

	user_data = (jobject *)lua_newuserdata(L, sizeof(jobject));
	*user_data = (*thread_env)->NewGlobalRef(thread_env, object);
	if (!*user_data)
	{
		lua_pushliteral(L, "JNI error: NewGlobalRef() failed pushing Java object");
		lua_error(L);
	}
	int result = lua_getmetatable(L, -1);
	if (result == 0)
	{
		luaL_getmetatable(L, JNLUA_OBJECT);
		lua_setmetatable(L, -2);
	}
	else
		lua_pop(L, 1);
}

/* Returns the Java object at the specified index, or NULL if such an object is unobtainable. */
static jobject tojavaobject(lua_State *L, int index, jclass class)
{
	int result;
	jobject object;

	if (!lua_isuserdata(L, index))
	{
		return NULL;
	}
	if (!lua_getmetatable(L, index))
	{
		return NULL;
	}
	luaL_getmetatable(L, JNLUA_OBJECT);
	result = lua_rawequal(L, -1, -2);
	lua_pop(L, 2);
	if (!result)
	{
		return NULL;
	}
	object = *(jobject *)lua_touserdata(L, index);
	if (class)
	{
		if (!(*thread_env)->IsInstanceOf(thread_env, object, class))
		{
			return NULL;
		}
	}
	return object;
}

/* Returns a Java string for a value on the stack. */
static jstring tostring(lua_State *L, int index)
{
	jstring string;

	if (!luaL_callmeta(L, index, "__tostring"))
	{
		switch (lua_type(L, index))
		{
		case LUA_TNUMBER:
		case LUA_TSTRING:
			lua_pushvalue(L, index);
			break;
		case LUA_TBOOLEAN:
			lua_pushstring(L, lua_toboolean(L, index) ? "true" : "false");
			break;
		case LUA_TNIL:
			lua_pushliteral(L, "nil");
			break;
		default:
			lua_pushfstring(L, "%s: %p", luaL_typename(L, index), lua_topointer(L, index));
		}
	}
	string = (*thread_env)->NewStringUTF(thread_env, lua_tostring(L, -1));
	lua_pop(L, 1);
	return string;
}

/* Finalizes Java objects. */
static int gcjavaobject(lua_State *L)
{
	jobject obj;

	if (!thread_env)
	{
		/* Environment has been cleared as the Java VM was destroyed. Nothing to do. */
		return 0;
	}
	obj = *(jobject *)lua_touserdata(L, 1);
	if (lua_toboolean(L, lua_upvalueindex(1)))
	{
		(*thread_env)->DeleteWeakGlobalRef(thread_env, obj);
	}
	else
	{
		(*thread_env)->DeleteGlobalRef(thread_env, obj);
	}
	return 0;
}

/* Calls a Java function. If an exception is reported, store it as the cause for later use. */
static int calljavafunction(lua_State *L)
{
	jobject luastate_obj_old, javastate, javafunction;
	lua_State *T;
	int nresults;
	int err;

	/* Get Java state. */
	lua_getfield(L, LUA_REGISTRYINDEX, JNLUA_JAVASTATE);
	if (!lua_isuserdata(L, -1))
	{
		/* Java state has been cleared as the Java VM was destroyed. Cannot call. */
		lua_pushliteral(L, "no Java state");
		return lua_error(L);
	}
	(*thread_env)->PushLocalFrame(thread_env, 32);
	javastate = *(jobject *)lua_touserdata(L, -1);
	lua_pop(L, 1);

	/* Get Java function object. */
	lua_pushvalue(L, lua_upvalueindex(1));
	javafunction = tojavaobject(L, -1, javafunction_interface);
	lua_pop(L, 1);
	if (!javafunction)
	{
		/* Function was cleared from outside JNLua code. */
		lua_pushliteral(L, "no Java function");
		return lua_error(L);
	}

	/* Perform the call, handling coroutine situations. */
	luastate_obj_old = luastate_obj;
	setyield(javastate, JNI_FALSE);

	T = getluathread(javastate);
	if (T == L)
	{
		nresults = (*thread_env)->CallIntMethod(thread_env, javafunction, invoke_id, javastate);
		err = handlejavaexception(L, 0);
	}
	else
	{
		//printf("%tu -> %tu\n",(long)(uintptr_t) T,(long)(uintptr_t) L);
		setluathread(javastate, L);
		nresults = (*thread_env)->CallIntMethod(thread_env, javafunction, invoke_id, javastate);
		err = handlejavaexception(L, 0);
		setluathread(javastate, T);
	}

	luastate_obj = luastate_obj_old;
	if (err)
	{
		(*thread_env)->PopLocalFrame(thread_env, NULL);
		lua_error(T);
	}
	/* Handle yield */
	if (getyield(javastate))
	{
		if (nresults < 0 || nresults > lua_gettop(L))
		{
			lua_pushliteral(L, "illegal return count");
			return lua_error(L);
		}
		if (L == getluastate(javastate))
		{
			lua_pushliteral(L, "not in a thread");
			return lua_error(L);
		}
		(*thread_env)->PopLocalFrame(thread_env, NULL);
		return lua_yield(L, nresults);
	}
	(*thread_env)->PopLocalFrame(thread_env, NULL);
	return nresults;
}

/* Handles Lua errors. */
static int messagehandler(lua_State *L)
{
	int level, count;
	lua_Debug ar;
	jobjectArray luastacktrace;
	jstring name, source;
	jobject luastacktraceelement;
	jobject luaerror;
	jstring message;

	/* Count relevant stack frames */
	level = 1;
	count = 0;
	while (lua_getstack(L, level, &ar))
	{
		lua_getinfo(L, "nSl", &ar);
		if (isrelevant(&ar))
		{
			count++;
		}
		level++;
	}
	(*thread_env)->PushLocalFrame(thread_env, 64);
	/* Create Lua stack trace as a Java LuaStackTraceElement[] */
	luastacktrace = (*thread_env)->NewObjectArray(thread_env, count, luastacktraceelement_class, NULL);
	if (!luastacktrace)
	{
		goto END;
	}
	level = 1;
	count = 0;
	while (lua_getstack(L, level, &ar))
	{
		lua_getinfo(L, "nSl", &ar);
		if (isrelevant(&ar))
		{
			name = ar.name ? (*thread_env)->NewStringUTF(thread_env, ar.name) : NULL;
			source = ar.source ? (*thread_env)->NewStringUTF(thread_env, ar.source) : NULL;
			luastacktraceelement = (*thread_env)->NewObject(thread_env, luastacktraceelement_class, luastacktraceelement_id, name, source, ar.currentline);
			if (!luastacktraceelement)
			{
				goto END;
			}
			(*thread_env)->SetObjectArrayElement(thread_env, luastacktrace, count, luastacktraceelement);
			if ((*thread_env)->ExceptionCheck(thread_env))
			{
				goto END;
			}
			count++;
		}
		level++;
	}

	/* Get or create the error object  */
	luaerror = tojavaobject(L, -1, luaerror_class);
	if (!luaerror)
	{
		message = tostring(L, -1);
		if (!(luaerror = (*thread_env)->NewObject(thread_env, luaerror_class, luaerror_id, message, NULL)))
		{
			goto END;
		}
	}
	(*thread_env)->CallVoidMethod(thread_env, luaerror, setluastacktrace_id, luastacktrace);
	handlejavaexception(L, 1);
	/* Replace error */
	pushjavaobject(L, luaerror);

END:
	(*thread_env)->PopLocalFrame(thread_env, NULL);
	return 1;
}

/* Processes a Lua activation record and returns whether it is relevant. */
static int isrelevant(lua_Debug *ar)
{
	if (ar->name && strlen(ar->name) == 0)
	{
		ar->name = NULL;
	}
	if (ar->what && strcmp(ar->what, "C") == 0)
	{
		ar->source = NULL;
	}
	if (ar->source)
	{
		if (*ar->source == '=' || *ar->source == '@')
		{
			ar->source++;
		}
	}
	return ar->name || ar->source;
}

/* Handles Lua errors by throwing a Java exception. */
JNLUA_THREADLOCAL int throw_status;
static int throw_protected(lua_State *L)
{
	jclass class;
	jmethodID id;
	jthrowable throwable;
	jobject luaerror;

	/* Determine the type of exception to throw. */
	switch (throw_status)
	{
	case LUA_ERRRUN:
		class = luaruntimeexception_class;
		id = luaruntimeexception_id;
		break;
	case LUA_ERRSYNTAX:
		class = luasyntaxexception_class;
		id = luasyntaxexception_id;
		break;
	case LUA_ERRMEM:
		class = luamemoryallocationexception_class;
		id = luamemoryallocationexception_id;
		break;
	case LUA_ERRERR:
		class = luamessagehandlerexception_class;
		id = luamessagehandlerexception_id;
		break;
	default:
		lua_pushfstring(L, "unknown Lua status %d", throw_status);
		return lua_error(L);
	}

	/* Create exception */
	throwable = (*thread_env)->NewObject(thread_env, class, id, tostring(L, 1));
	if (!throwable)
	{
		lua_pushliteral(L, "JNI error: NewObject() failed creating throwable");
		return lua_error(L);
	}

	/* Set the Lua error, if any. */
	luaerror = tojavaobject(L, 1, luaerror_class);
	if (luaerror && class == luaruntimeexception_class)
	{
		(*thread_env)->CallVoidMethod(thread_env, throwable, setluaerror_id, luaerror);
		handlejavaexception(L, 1);
	}

	/* Throw */
	if ((*thread_env)->Throw(thread_env, throwable) < 0)
	{
		lua_pushliteral(L, "JNI error: Throw() failed");
		return lua_error(L);
	}

	return 0;
}
static void throw(lua_State * L, int status)
{
	const char *message;

	if (checkstack(L, JNLUA_MINSTACK))
	{
		throw_status = status;
		lua_pushcfunction(L, throw_protected);
		lua_insert(L, -2);
		if (lua_pcall(L, 1, 0, 0) != 0)
		{
			message = lua_tostring(L, -1);
			(*thread_env)->ThrowNew(thread_env, error_class, message ? message : "error throwing Lua exception");
		}
	}
}

/* ---- Stream adapters ---- */
/* Lua reader for Java input streams. */
static const char *readhandler(lua_State *L, void *ud, size_t *size)
{
	Stream *stream;
	int read;

	stream = (Stream *)ud;
	read = (*thread_env)->CallIntMethod(thread_env, stream->stream, read_id, stream->byte_array);
	if ((*thread_env)->ExceptionCheck(thread_env))
	{
		(*thread_env)->ExceptionClear(thread_env);
		return NULL;
	}
	if (read == -1)
	{
		return NULL;
	}
	if (stream->bytes && stream->is_copy)
	{
		(*thread_env)->ReleaseByteArrayElements(thread_env, stream->byte_array, stream->bytes, JNI_ABORT);
		stream->bytes = NULL;
	}
	if (!stream->bytes)
	{
		stream->bytes = (*thread_env)->GetByteArrayElements(thread_env, stream->byte_array, &stream->is_copy);
		if (!stream->bytes)
		{
			(*thread_env)->ThrowNew(thread_env, ioexception_class, "JNI error: GetByteArrayElements() failed accessing IO buffer");
			return NULL;
		}
	}
	*size = (size_t)read;
	return (const char *)stream->bytes;
}

/* Lua writer for Java output streams. */
static int writehandler(lua_State *L, const void *data, size_t size, void *ud)
{
	Stream *stream;

	stream = (Stream *)ud;
	if (!stream->bytes)
	{
		stream->bytes = (*thread_env)->GetByteArrayElements(thread_env, stream->byte_array, &stream->is_copy);
		if (!stream->bytes)
		{
			(*thread_env)->ThrowNew(thread_env, ioexception_class, "JNI error: GetByteArrayElements() failed accessing IO buffer");
			return 1;
		}
	}
	memcpy(stream->bytes, data, size);
	if (stream->is_copy)
	{
		(*thread_env)->ReleaseByteArrayElements(thread_env, stream->byte_array, stream->bytes, JNI_COMMIT);
	}
	(*thread_env)->CallVoidMethod(thread_env, stream->stream, write_id, stream->byte_array, 0, size);
	if ((*thread_env)->ExceptionCheck(thread_env))
	{
		(*thread_env)->ExceptionClear(thread_env);
		return 1;
	}
	return 0;
}
