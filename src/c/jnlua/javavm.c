/*
 * $Id: javavm.c 131 2012-01-23 20:25:29Z andre@naef.com $
 * Provides the Java VM module. See LICENSE.txt for license terms.
 */

#include <stdlib.h>
#include <string.h>
#include <jni.h>
#include <lauxlib.h>
#ifdef LUA_WIN
#include <stddef.h>
#pragma warning(disable : 4996)
#endif
#ifdef LUA_USE_POSIX
#include <stdint.h>
#endif
#include "javavm.h"

/*
 * Java VM parameters.
 */
#define JAVAVM_METATABLE "javavm.metatable"
#define JAVAVM_VM "javavm.vm"
#define JAVAVM_MAXOPTIONS 128
#define JAVAVM_JNIVERSION JNI_VERSION_1_8

/*
 * Global variables for shared JNI references.
 * 
 * THREAD SAFETY:
 * - java_vm: Thread-safe (JNI spec guarantees)
 * - Class references and method IDs: Thread-safe after initialization (read-only)
 * - jobject references: Protected by global refs, thread-safe
 * - JNIEnv: MUST be obtained per-thread, never stored globally
 */
JavaVM *java_vm = NULL;

/*
 * VM record.
 */
typedef struct vm_rec
{
	JavaVM *vm;
	jobject luastate;
	int num_options;
	JavaVMOption options[JAVAVM_MAXOPTIONS];
} vm_rec;

/* Global JNI references - initialized once during VM creation, read-only afterwards */
static jclass luastate_class = NULL;
static jclass library_class = NULL;
static jobject java_library = NULL;
static jmethodID init_id = NULL;
static jmethodID openlib_id = NULL;
static jmethodID close_id = NULL;
static jmethodID trace_id = NULL;

/*
 * Forward declarations.
 */
static void clearRefs(JNIEnv *env);
static void set_trace(lua_State *L, JNIEnv *env, jobject luastate_obj);

/*
 * Raises an error from JNI.
 */
static int error(lua_State *L, JNIEnv *env, const char *msg)
{
	jthrowable throwable;
	jclass throwable_class = NULL;
	jmethodID tostring_id;
	jstring string = NULL;
	const char *extramsg = NULL;

	throwable = (*env)->ExceptionOccurred(env);
	if (throwable)
	{
		(*env)->ExceptionClear(env);
		throwable_class = (*env)->GetObjectClass(env, throwable);
		if ((tostring_id = (*env)->GetMethodID(env, throwable_class, "toString", "()Ljava/lang/String;")))
		{
			string = (*env)->CallObjectMethod(env, throwable, tostring_id);
			if (string)
			{
				extramsg = (*env)->GetStringUTFChars(env, string, NULL);
			}
		}
		jmethodID getMessage = (*env)->GetMethodID(env, throwable_class, "printStackTrace", "()V");
		(*env)->CallObjectMethod(env, throwable, getMessage);
	}
	if (extramsg)
	{
		lua_pushfstring(L, "%s (%s)", msg, extramsg);
		(*env)->ReleaseStringUTFChars(env, string, extramsg);
	}
	else
	{
		lua_pushstring(L, msg);
	}
	if (string) {
		(*env)->DeleteLocalRef(env, string);
	}
	if (throwable_class) {
		(*env)->DeleteLocalRef(env, throwable_class);
	}
	/* Release throwable local reference */
	if (throwable) {
		(*env)->DeleteLocalRef(env, throwable);
	}
	return luaL_error(L, lua_tostring(L, -1));
}

/*
 * Releases a VM.
 */
static int release_vm(lua_State *L)
{
	vm_rec *vm;
	JNIEnv *env;
	int res;
	int i;

	/* Get VM */
	vm = luaL_checkudata(L, 1, JAVAVM_METATABLE);

	/* Already released? */
	if (!vm->vm)
	{
		return 0;
	}

	/* Check thread */
	if ((*vm->vm)->GetEnv(vm->vm, (void **)&env, JAVAVM_JNIVERSION) != JNI_OK)
	{
		return luaL_error(L, "invalid thread");
	}

	/* Close the Lua state in the Java VM */
	if (vm->luastate)
	{
		if (close_id) {
			(*env)->CallVoidMethod(env, vm->luastate, close_id);
		}
		(*env)->DeleteGlobalRef(env, vm->luastate);
		vm->luastate = NULL;
	}

	/* Destroy the Java VM */
	res = (*vm->vm)->DestroyJavaVM(vm->vm);
	if (res < 0)
	{
		return luaL_error(L, "error destroying Java VM: %d", res);
	}
	vm->vm = NULL;
	java_vm = NULL;

	/* Clean up all global JNI references */
	clearRefs(env);

	/* Free options */
	for (i = 0; i < vm->num_options; i++)
	{
		free(vm->options[i].optionString);
		vm->options[i].optionString = NULL;
	}
	vm->num_options = 0;

	/* Reset method IDs */
	init_id = NULL;
	openlib_id = NULL;
	close_id = NULL;
	trace_id = NULL;

	return 0;
}

/*
 * Returns a string representation of a VM.
 */
static int tostring_vm(lua_State *L)
{
	vm_rec *vm;
	int i;

	vm = luaL_checkudata(L, 1, JAVAVM_METATABLE);
	lua_pushfstring(L, "Java VM (%p)", vm->vm);
	luaL_checkstack(L, vm->num_options, NULL);
	for (i = 0; i < vm->num_options; i++)
	{
		lua_pushfstring(L, "\n\t%s", vm->options[i].optionString);
	}
	lua_concat(L, vm->num_options + 1);
	return 1;
}

/*
 * Creates a VM.
 */

static char *strdup1(const char *src)
{
	size_t len = strlen(src) + 1;
	char *s = malloc(len);
	if (s == NULL)
		return NULL;
	return (char *)memcpy(s, src, len);
}

static int trace_on = 0;

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

static void set_trace(lua_State *L, JNIEnv *env, jobject luastate_obj)
{
	if (!trace_id || !luastate_obj || !env)
		return;
	(*env)->CallIntMethod(env, luastate_obj, trace_id, trace_on);
}

static void clearRefs(JNIEnv *env) {
	/* Clear all global references if env is valid */
	if (!env) {
		return;
	}
	if (luastate_class) {
		(*env)->DeleteGlobalRef(env, luastate_class);
		luastate_class = NULL;
	}
	if (library_class) {
		(*env)->DeleteGlobalRef(env, library_class);
		library_class = NULL;
	}
	if (java_library) {
		(*env)->DeleteGlobalRef(env, java_library);
		java_library = NULL;
	}
}

static int create_vm(lua_State *L)
{
	vm_rec *vm;
	JNIEnv *env;
	jobject luastate_obj;
	jfieldID java_id;
	int i;
	const char *option;
	JavaVMInitArgs vm_args;
	int res;

	/* Check for existing VM */
	lua_getfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	if (!lua_isnil(L, -1))
	{
		return luaL_error(L, "VM already created");
	}
	lua_pop(L, 1);

	/* Create VM */
	vm = lua_newuserdata(L, sizeof(vm_rec));
	memset(vm, 0, sizeof(vm_rec));
	luaL_getmetatable(L, JAVAVM_METATABLE);
	lua_setmetatable(L, -2);
	/* Process options */
	vm->num_options = lua_gettop(L) - 1;
	if (vm->num_options > JAVAVM_MAXOPTIONS)
	{
		return luaL_error(L, "%d options limit, got %d", JAVAVM_MAXOPTIONS, vm->num_options);
	}
	for (i = 1; i <= vm->num_options; i++)
	{
		option = luaL_checkstring(L, i);
		if (strcmp(option, "vfprintf") == 0 || strcmp(option, "exit") == 0 || strcmp(option, "abort") == 0)
		{
			return luaL_error(L, "unsupported option '%s'", option);
		}
		vm->options[i - 1].optionString = strdup1(option);
		if (!vm->options[i - 1].optionString)
		{
			return luaL_error(L, "out of memory");
		}
	}

	/* Create Java VM */
	vm_args.version = JAVAVM_JNIVERSION;
	vm_args.options = vm->options;
	vm_args.nOptions = vm->num_options;
	vm_args.ignoreUnrecognized = JNI_TRUE;
	res = JNI_CreateJavaVM(&vm->vm, (void **)&env, &vm_args);
	if (res < 0)
	{
		for (int j = 0; j < vm->num_options; j++) {
			free(vm->options[j].optionString);
		}
		return luaL_error(L, "error creating Java VM: %d (%s)", res, 
			res == JNI_ERR ? "JNI_ERR" : 
			res == JNI_EDETACHED ? "JNI_EDETACHED" : 
			res == JNI_EVERSION ? "JNI_EVERSION" : "Unknown error");
	}

	java_vm = vm->vm;

	/* Ensure adequate local capacity (512 is standard, matches jnlua.c pattern) */
	if ((*env)->EnsureLocalCapacity(env, 512) < 0) {
		for (int j = 0; j < vm->num_options; j++) {
			free(vm->options[j].optionString);
		}
		return luaL_error(L, "Failed to ensure local capacity");
	}
	/* Create local frame for temporary JNI references */
	if ((*env)->PushLocalFrame(env, 128) < 0) {
		for (int j = 0; j < vm->num_options; j++) {
			free(vm->options[j].optionString);
		}
		return luaL_error(L, "Failed to push local frame");
	}
	/* Create a LuaState in the Java VM */
	if (!(luastate_class = referenceclass(env, "com/naef/jnlua/LuaState"))			 // //
		|| !(init_id  = (*env)->GetMethodID(env, luastate_class, "<init>", "(JI)V")) 
		|| !(close_id = (*env)->GetMethodID(env, luastate_class, "close", "()V")))
	{
		clearRefs(env);
		(*env)->PopLocalFrame(env, NULL);
		return error(L, env, "LuaState not found");
	}
	/* Load the Java module */
	if (!(library_class = referenceclass(env, "com/naef/jnlua/LuaState$Library")) 
	   || !(openlib_id  = (*env)->GetMethodID(env, luastate_class, "openLib", "(Lcom/naef/jnlua/LuaState$Library;)V")) 
	   || !(java_id     = (*env)->GetStaticFieldID(env, library_class, "JAVA", "Lcom/naef/jnlua/LuaState$Library;")) 
	   || !(java_library = (*env)->NewGlobalRef(env,(*env)->GetStaticObjectField(env, library_class, java_id))))
	{
		clearRefs(env);
		(*env)->PopLocalFrame(env, NULL);
		return error(L, env, "Java module not found");
	}
	/* Create LuaState object with ownState=1 to indicate VM-owned state */
	luastate_obj = (*env)->NewObject(env, luastate_class, init_id, (jlong)(uintptr_t)L);
	
	if (!luastate_obj)
	{
		clearRefs(env);
		(*env)->PopLocalFrame(env, NULL);
		return error(L, env, "error creating LuaState");
	}

	if((trace_id = (*env)->GetMethodID(env, luastate_class, "trace", "(I)I")) && trace_on > 0)
	{
		set_trace(L, env, luastate_obj);
	}

	(*env)->CallVoidMethod(env, luastate_obj, openlib_id, java_library);
	if ((*env)->ExceptionCheck(env))
	{
		(*env)->DeleteLocalRef(env, luastate_obj);
		clearRefs(env);
		(*env)->PopLocalFrame(env, NULL);
		return error(L, env, "error loading Java module");
	}
	
	/* Convert to global reference and store in vm_rec */
	vm->luastate = (*env)->NewGlobalRef(env, luastate_obj);
	if (!vm->luastate)
	{
		(*env)->DeleteLocalRef(env, luastate_obj);
		clearRefs(env);
		(*env)->PopLocalFrame(env, NULL);
		return luaL_error(L, "error creating global reference for LuaState");
	}
	
	/* Store VM */
	lua_pushvalue(L, -1);
	lua_setfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	(*env)->PopLocalFrame(env, NULL);
	return 1;
}

static int attach_vm(lua_State *L)
{
	JNIEnv *local_env;
	int needs_detach = 0;

	if (!java_vm)
	{
		return luaL_error(L, "Java VM has not been created");
	}

	/* Check if classes and methods are initialized */
	if (!luastate_class || !init_id || !openlib_id || !java_library)
	{
		return luaL_error(L, "Java VM classes not initialized. Call create() first.");
	}

	lua_getfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	if (!lua_isnil(L, -1))
	{
		lua_pop(L, 1);
		return luaL_error(L, "VM already attached");
	}
	lua_pop(L, 1);

	const int envStat = (*java_vm)->GetEnv(java_vm, (void **)&local_env, JAVAVM_JNIVERSION);
	if (envStat == JNI_EDETACHED)
	{
		if ((*java_vm)->AttachCurrentThread(java_vm, (void **)&local_env, NULL) != 0)
		{
			return luaL_error(L, "Failed to AttachCurrentThread");
		}
		needs_detach = 1;
	}
	else if (envStat != JNI_OK)
	{
		return luaL_error(L, "Failed to GetEnv: %d", envStat);
	}

	/* Create LuaState object with ownState=0 (external state) */
	jobject luastate_local = (*local_env)->NewObject(local_env, luastate_class, init_id, (jlong)(uintptr_t)L, (jint)0);
	if (!luastate_local)
	{
		/* Detach thread on error path */
		if (needs_detach)
			(*java_vm)->DetachCurrentThread(java_vm);
		return error(L, local_env, "error creating LuaState");
	}
	
	(*local_env)->CallVoidMethod(local_env, luastate_local, openlib_id, java_library);
	if ((*local_env)->ExceptionCheck(local_env))
	{
		/* Delete local reference and detach thread on error */
		(*local_env)->DeleteLocalRef(local_env, luastate_local);
		if (needs_detach)
			(*java_vm)->DetachCurrentThread(java_vm);
		return error(L, local_env, "error loading Java module");
	}
	
	jobject *user_data = (jobject *)lua_newuserdata(L, sizeof(jobject));
	*user_data = (*local_env)->NewGlobalRef(local_env, luastate_local);
	
	/* Delete local reference after converting to global */
	(*local_env)->DeleteLocalRef(local_env, luastate_local);
	
	lua_setfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);

	if (needs_detach)
		(*java_vm)->DetachCurrentThread(java_vm);
	return 1;
}

static int detach_vm(lua_State *L)
{
	JNIEnv *env;
	int envStat;
	int needs_detach = 0;
	
	if (!java_vm)
	{
		return luaL_error(L, "Java VM has not been created");
	}

	envStat = (*java_vm)->GetEnv(java_vm, (void **)&env, JAVAVM_JNIVERSION);
	
	if (envStat == JNI_EDETACHED)
	{
		if ((*java_vm)->AttachCurrentThread(java_vm, (void **)&env, NULL) != 0)
		{
			return luaL_error(L, "Failed to AttachCurrentThread");
		}
		needs_detach = 1;
	}
	else if (envStat != JNI_OK)
	{
		return luaL_error(L, "Failed to GetEnv: %d", envStat);
	}
	
	lua_getfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	if (lua_isnil(L, -1))
	{
		lua_pop(L, 1);
		if (needs_detach)
			(*java_vm)->DetachCurrentThread(java_vm);
		return luaL_error(L, "VM already detached");
	}
	
	jobject luastate = *(jobject *)lua_touserdata(L, -1);
	lua_pop(L, 1);
	
	if (close_id) {
		(*env)->CallVoidMethod(env, luastate, close_id);
	}
	(*env)->DeleteGlobalRef(env, luastate);
	
	lua_pushnil(L);
	lua_setfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	
	if (needs_detach)
		(*java_vm)->DetachCurrentThread(java_vm);
	return 1;
}
/*
 * Destroys the VM.
 */
static int destroy_vm(lua_State *L)
{
	/* Release VM, if any */
	lua_pushcfunction(L, release_vm);
	lua_getfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	if (lua_isnil(L, -1))
	{
		/* No VM to destroy */
		lua_pushboolean(L, 0);
		return 1;
	}
	lua_call(L, 1, 0);

	/* Clear VM */
	lua_pushnil(L);
	lua_setfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);

	/* Success */
	lua_pushboolean(L, 1);
	return 1;
}

/*
 * Returns the VM, if any.
 */
static int get_vm(lua_State *L)
{
	lua_getfield(L, LUA_REGISTRYINDEX, JAVAVM_VM);
	return 1;
}

/*
 * Set trace to debug error
 */

static int trace(lua_State *L)
{
	/* Correctly handle return values for Lua */
	if (!lua_isnumber(L, -1))
	{
		/* Return current trace_on value to Lua */
		lua_pushinteger(L, trace_on);
		return 1;
	}
	trace_on = lua_tointeger(L, -1);
	/* Note: set_trace requires JNIEnv and luastate_obj, which are not available here.
	 * The trace setting will take effect when LuaState is created/attached. */
	/* Return the new trace_on value */
	lua_pushinteger(L, trace_on);
	return 1;
}

/*
 * Java VM module functions.
 */
static const luaL_Reg functions[] = {
	{"trace", trace},
	{"create", create_vm},
	{"destroy", destroy_vm},
	{"attach", attach_vm},
	{"detach", detach_vm},
	{"get", get_vm},
	{NULL, NULL}};

/*
 * Exported functions.
 */

LUALIB_API int luaopen_javavm(lua_State *L)
{
	/* Create module */
	luaL_register(L, lua_tostring(L, -1), functions);

	/* Create metatable */
	luaL_newmetatable(L, JAVAVM_METATABLE);
	lua_pushcfunction(L, release_vm);
	lua_setfield(L, -2, "__gc");
	lua_pushcfunction(L, tostring_vm);
	lua_setfield(L, -2, "__tostring");
	lua_pop(L, 1);

	return 1;
}
