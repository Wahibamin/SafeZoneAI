package com.safezone.ai.mobile

import android.os.Build
import android.os.BatteryManager
import android.os.PowerManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.safezone.ai.mobile/native_runtime"
    private val modelWorker = Executors.newSingleThreadExecutor()
    private val models by lazy { ModelRuntime(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspectModel", "smokeModel", "switchModel", "closeModels", "inferCamera", "inferImage", "beginVideo", "videoFrame", "endVideo" -> {
                    modelWorker.execute {
                        try {
                            val value: Any? = when (call.method) {
                                "closeModels" -> { models.close(); null }
                                "inferCamera" -> models.infer(call.arguments as Map<String, Any?>)
                                "inferImage" -> models.inferImage(call.arguments as Map<String, Any?>)
                                "beginVideo" -> models.beginVideo(call.arguments as Map<String, Any?>)
                                "videoFrame" -> models.videoFrame(requireNotNull(call.argument<Number>("timestampMs")).toLong())
                                "endVideo" -> { models.endVideo(); null }
                                "inspectModel" -> models.inspect(requireNotNull(call.argument<String>("filePath")))
                                else -> models.smoke(requireNotNull(call.argument<String>("filePath")), call.method == "switchModel", call.argument<String>("accelerator") ?: "cpu")
                            }
                            runOnUiThread { result.success(value) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("MODEL_RUNTIME", e.message ?: e.javaClass.simpleName, null) }
                        } catch (e: LinkageError) {
                            runOnUiThread { result.error("MODEL_RUNTIME_UNAVAILABLE", e.message, null) }
                        }
                    }
                }
                "getDeviceInfo" -> {
                    val info = mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "device" to Build.DEVICE,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "isFoldableTarget" to (Build.MODEL.contains("SM-F711", ignoreCase = true) || Build.DEVICE.contains("b2q", ignoreCase = true))
                    )
                    result.success(info)
                }
                "getDeviceHealth" -> {
                    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                    val batteryC = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                        ?.takeIf { it >= 0 }?.div(10.0)
                    result.success(mapOf(
                        "thermal_status" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power.currentThermalStatus else 0,
                        "battery_c" to batteryC
                    ))
                }
                "inspectTfliteHeader" -> {
                    val path = call.argument<String>("filePath")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARG", "File path is required", null)
                    } else {
                        result.success(inspectFlatBufferHeader(path))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        modelWorker.execute { models.close() }
        modelWorker.shutdown()
        super.onDestroy()
    }

    private fun inspectFlatBufferHeader(path: String): Map<String, Any> {
        val file = File(path)
        if (!file.exists() || !file.isFile) {
            return mapOf("valid" to false, "error" to "File does not exist at path")
        }
        if (file.length() < 32) {
            return mapOf("valid" to false, "error" to "File too small to be a valid TFLite FlatBuffer")
        }
        return try {
            RandomAccessFile(file, "r").use { raf ->
                val header = ByteArray(8)
                raf.readFully(header)
                val magic = String(header, 4, 4, Charsets.US_ASCII)
                val isTfliteMagic = magic == "TFL3"
                mapOf(
                    "valid" to isTfliteMagic,
                    "magic" to magic,
                    "sizeBytes" to file.length(),
                    "error" to if (isTfliteMagic) "" else "Invalid TFLite FlatBuffer identifier ($magic != TFL3)"
                )
            }
        } catch (e: Exception) {
            mapOf("valid" to false, "error" to (e.message ?: "Failed to read file header"))
        }
    }
}
