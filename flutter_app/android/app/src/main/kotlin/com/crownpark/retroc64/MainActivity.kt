package com.crownpark.retroc64

import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

/**
 * The gamepads_android plugin casts the host Activity to
 * GamepadsCompatibleActivity in onAttachedToActivityShared(). A plain
 * FlutterActivity doesn't implement it, so registration blew up with
 * "java.lang.ClassCastException: com.crownpark.retroc64.MainActivity
 * cannot be cast to org.flame_engine.gamepads_android.GamepadsCompatibleActivity"
 * on every launch -- the plugin was skipped entirely and no physical
 * controller could ever be seen on Android (external gamepad support works
 * on Linux desktop, where a different plugin implementation is used).
 *
 * Implementing the interface here wires the plugin's listeners into this
 * Activity's own input dispatch, which is what the plugin expects.
 */
class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {
    private var keyEventHandler: ((KeyEvent) -> Boolean)? = null
    private var motionEventHandler: ((MotionEvent) -> Boolean)? = null

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener,
        handler: Handler?
    ) {
        val inputManager = getSystemService(Context.INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyEventHandler = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionEventHandler = handler
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (keyEventHandler?.invoke(event) == true) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (motionEventHandler?.invoke(event) == true) {
            return true
        }
        return super.dispatchGenericMotionEvent(event)
    }

    /**
     * "All files access" (MANAGE_EXTERNAL_STORAGE) plumbing.
     *
     * The user's C64 collection lives in shared storage as .d64/.t64/.tap/
     * .prg files. None of those are media types, so READ_MEDIA_* doesn't
     * cover them: on Android 11+ the app can LIST the folder but every read
     * of a file's bytes fails, which is why games appeared in the library
     * and then launched to a black screen.
     *
     * This is a two-method channel rather than the permission_handler
     * package: permission_handler's current Android artifact fails to
     * compile against this project's Gradle/Kotlin setup (its build.gradle
     * .kts trips deprecation-as-error on srcDirs), and the whole thing we
     * need from it is two platform calls.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                "requestAllFilesAccess" -> {
                    requestAllFilesAccess()
                    // The grant happens in system Settings, so this only
                    // reports the state as of right now; Dart re-checks
                    // when the app resumes.
                    result.success(hasAllFilesAccess())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasAllFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true // pre-R: the manifest's READ_EXTERNAL_STORAGE covers it
        }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (hasAllFilesAccess()) return
        val appSpecific = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$packageName")
        )
        try {
            startActivity(appSpecific)
        } catch (_: Exception) {
            // Some OEM builds don't implement the per-app screen; the
            // global list always exists.
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    companion object {
        private const val STORAGE_CHANNEL = "com.crownpark.retroc64/storage_permissions"
    }
}
