package com.prasasti.connect

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Jembatan pemasangan APK pembaruan.
 *
 * Android tidak mengizinkan aplikasi biasa memasang APK tanpa konfirmasi
 * pengguna, jadi saluran ini hanya membuka pemasang sistem untuk berkas yang
 * sudah diunduh dan diverifikasi checksum-nya di sisi Dart.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.prasasti.connect/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "Path APK kosong.", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: ActivityNotFoundException) {
            // Perangkat tanpa layar pengaturan tersebut: abaikan.
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Berkas APK tidak ditemukan.", null)
            return
        }
        if (!canInstallPackages()) {
            result.error(
                "no_permission",
                "Izinkan pemasangan aplikasi dari Prasasti Connect terlebih dahulu.",
                null
            )
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("no_installer", "Perangkat tidak memiliki pemasang APK.", null)
        } catch (e: Exception) {
            result.error("install_failed", e.message ?: "Gagal membuka pemasang APK.", null)
        }
    }
}
