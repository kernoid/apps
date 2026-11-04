// SPDX-License-Identifier: MIT
package dev.kernoid.kernoid

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Before Dart's first connection: rustls-platform-verifier needs the JVM (ProviderCore.ready).
        ProviderCore.ready(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.kernoid.kernoid/documents")
            .setMethodCallHandler { call, result ->
                val context = applicationContext
                val main = Handler(Looper.getMainLooper())
                // Off the main thread: closing the provider's session asks the core once more.
                fun later(work: () -> Any?) =
                    ProviderSession.worker.post {
                        try {
                            val answer = work()
                            main.post { result.success(answer) }
                        } catch (error: Exception) {
                            main.post { result.error("documents", error.message, null) }
                        }
                    }
                when (call.method) {
                    "enabled" -> later { ProviderSession.signedIn(context) }
                    // The provider's own login (never the app's): kept, and the Files app shows its stores.
                    "enable" -> {
                        val kept = call.arguments as? String
                        if (kept == null) {
                            result.error("documents", "no login given", null)
                        } else {
                            later {
                                ProviderSession.close(context)
                                ProviderLogin.save(context, kept)
                                KernoidDocumentsProvider.rootsChanged(context)
                                null
                            }
                        }
                    }
                    // The login is forgotten here and handed back, so that the app can end it at the server.
                    "disable" ->
                        later {
                            ProviderSession.close(context)
                            val kept = ProviderLogin.load(context)
                            ProviderLogin.clear(context)
                            KernoidDocumentsProvider.rootsChanged(context)
                            kept
                        }
                    else -> result.notImplemented()
                }
            }
    }
}
