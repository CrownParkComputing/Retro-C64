package com.crownpark.retroc64

import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    /* All-files access, the Retro-Amiga way. The request opens the system's
     * All-files-access page; the parked result is completed from onResume
     * when the user comes back. The SAF folder grant below remains as the
     * no-permission fallback. */
    private var pendingStorageAccess: MethodChannel.Result? = null
    private var waitingForStorageSettings = false

    private fun hasSharedStorageAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            android.os.Environment.isExternalStorageManager()

    override fun onResume() {
        super.onResume()
        if (waitingForStorageSettings) {
            waitingForStorageSettings = false
            val pending = pendingStorageAccess
            pendingStorageAccess = null
            pending?.success(hasSharedStorageAccess())
        }
    }

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
    /**
     * The Dart call waiting on the folder picker.
     *
     * ACTION_OPEN_DOCUMENT_TREE answers through onActivityResult, which has no
     * way back to the MethodChannel result on its own, so it is parked here.
     * Cleared on every outcome, including the user backing out, or a second
     * attempt is refused as busy forever.
     */
    private var pendingFolderPick: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != MediaFolderAccess.REQUEST_PICK_FOLDER) return

        val pending = pendingFolderPick
        pendingFolderPick = null
        if (pending == null) return

        val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            pending.success(null)
            return
        }
        try {
            MediaFolderAccess.persist(this, uri)
            pending.success(uri.toString())
        } catch (e: SecurityException) {
            pending.error("not_persistable", "the folder grant could not be kept", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSharedStorageAccess" ->
                    result.success(hasSharedStorageAccess())

                "requestSharedStorageAccess" -> {
                    if (hasSharedStorageAccess()) {
                        result.success(true)
                    } else if (pendingStorageAccess != null) {
                        result.error("busy", "storage access settings are already open", null)
                    } else {
                        pendingStorageAccess = result
                        waitingForStorageSettings = true
                        val intent = Intent(
                            android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        try {
                            startActivity(intent)
                        } catch (error: Exception) {
                            startActivity(
                                Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                            )
                        }
                    }
                }

                "mediaFolderUri" ->
                    result.success(MediaFolderAccess.grantedTree(this)?.toString())

                "pickMediaFolder" -> {
                    // The answer arrives in onActivityResult, not here.
                    if (pendingFolderPick != null) {
                        result.error("busy", "a folder picker is already open", null)
                    } else {
                        pendingFolderPick = result
                        MediaFolderAccess.pickFolder(this)
                    }
                }

                "forgetMediaFolder" -> {
                    MediaFolderAccess.release(this)
                    result.success(true)
                }

                "listMediaFolder" -> {
                    val limit = call.argument<Int>("fileLimit") ?: 20000
                    val tree = MediaFolderAccess.grantedTree(this)
                    if (tree == null) {
                        result.error("no_folder", "no folder has been granted", null)
                    } else {
                        // Off the main thread: a large collection is tens of
                        // thousands of provider rows, and doing that on the UI
                        // thread is an ANR, not a slow scan.
                        Thread {
                            val entries = MediaFolderAccess.enumerate(
                                contentResolver, tree, limit)
                            val payload = entries.map {
                                mapOf(
                                    "documentId" to it.documentId,
                                    "name" to it.name,
                                    "directory" to it.relativeDirectory,
                                    "size" to it.size,
                                )
                            }
                            Handler(Looper.getMainLooper()).post { result.success(payload) }
                        }.start()
                    }
                }

                "copyFromMediaFolder" -> {
                    val documentId = call.argument<String>("documentId")
                    val destination = call.argument<String>("destination")
                    val tree = MediaFolderAccess.grantedTree(this)
                    if (documentId == null || destination == null) {
                        result.error("bad_args",
                            "copyFromMediaFolder needs documentId and destination", null)
                    } else if (tree == null) {
                        result.error("no_folder", "no folder has been granted", null)
                    } else {
                        Thread {
                            val ok = MediaFolderAccess.copyDocument(
                                contentResolver, tree, documentId, destination)
                            Handler(Looper.getMainLooper()).post { result.success(ok) }
                        }.start()
                    }
                }

                // Where a launched title is materialised. Cache, not storage:
                // it is one file, it is disposable, and the user's own folder
                // is never written to.
                "mediaCacheDirectory" -> result.success(cacheDir.absolutePath)

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val STORAGE_CHANNEL = "com.crownpark.retroc64/storage_permissions"
    }
}
