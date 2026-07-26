package com.orailnoor.privatelm.opendroid.actions

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import com.orailnoor.privatelm.opendroid.accessibility.OpenDroidAccessibilityService
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult
import com.orailnoor.privatelm.opendroid.core.agent.DeviceStateProvider
import com.orailnoor.privatelm.opendroid.core.agent.VisionEngine
import kotlinx.coroutines.delay

class SystemActions(
    private val deviceStateProvider: DeviceStateProvider,
    private val visionEngine: VisionEngine
) {

    fun getActions(): List<Action> = listOf(
        ToggleWifiAction(),
        ToggleFlashlightAction(),
        SetVolumeAction(),
        SetBrightnessAction(),
        OpenAppAction(),
        LockScreenAction(),
        ToggleBluetoothAction(),
        ToggleDndAction(),
        TakeScreenshotAction(),
        ToggleMobileDataAction(),
        GetSystemInfoAction(),
        SetRingerModeAction(),
        AnalyzeScreenshotAction(visionEngine),
        ClearClipboardAction(),
        CopyToClipboardAction(),
        GetClipboardAction(),
        OpenBrowserAction(),
        OpenUrlAction(),
        CloseAppAction(),
        // Ask user — returns NeedsInput so PrivateLM can prompt
        AskUserAction()
    )

    private class ToggleWifiAction : Action {
        override val name: String = "TOGGLE_WIFI"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val requestedState = (params["state"] ?: "toggle").lowercase().trim()
            @Suppress("DEPRECATION")
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return ActionResult(false, null, "WiFi service unavailable")
            @Suppress("DEPRECATION")
            val currentlyOn = wifiManager.isWifiEnabled
            val targetOn = when (requestedState) {
                "on", "true", "enable" -> true
                "off", "false", "disable" -> false
                else -> !currentlyOn
            }
            if (targetOn == currentlyOn) {
                return ActionResult(true, "WiFi is already ${if (currentlyOn) "on" else "off"}!", null)
            }
            val stateWord = if (targetOn) "on" else "off"
            if (Build.VERSION.SDK_INT >= 29) {
                return try {
                    val intent = Intent(Settings.Panel.ACTION_WIFI).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    ActionResult(true, "WiFi settings opened — toggle it $stateWord!", null)
                } catch (e: Exception) {
                    ActionResult(false, null, "Couldn't open WiFi settings.")
                }
            }
            return try {
                @Suppress("DEPRECATION")
                wifiManager.isWifiEnabled = targetOn
                ActionResult(true, "WiFi turned $stateWord!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't toggle WiFi: ${e.message}")
            }
        }
    }

    private class ToggleFlashlightAction : Action {
        override val name: String = "TOGGLE_FLASHLIGHT"
        private var isOn = false
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val state = (params["state"] ?: "toggle").lowercase()
            val targetOn = when (state) {
                "on" -> true
                "off" -> false
                else -> !isOn
            }
            return try {
                val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                    ?: return ActionResult(false, null, "Camera service unavailable")
                val cameraId = cameraManager.cameraIdList.firstOrNull()
                    ?: return ActionResult(false, null, "No camera found")
                cameraManager.setTorchMode(cameraId, targetOn)
                isOn = targetOn
                ActionResult(true, "Flashlight turned ${if (targetOn) "on" else "off"}!", null)
            } catch (e: Exception) {
                Log.e("Flashlight", "Failed: ${e.message}")
                ActionResult(false, null, "Couldn't toggle flashlight.")
            }
        }
    }

    private class SetVolumeAction : Action {
        override val name: String = "SET_VOLUME"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val levelStr = params["level"] ?: return ActionResult(false, null, "level parameter missing")
            val level = levelStr.replace("%", "").trim().toIntOrNull()
                ?: return ActionResult(false, null, "Invalid volume level: $levelStr")
            val type = params["type"]?.lowercase() ?: "media"
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return ActionResult(false, null, "Audio service unavailable")
            val streamType = when (type) {
                "ring", "ringer" -> AudioManager.STREAM_RING
                "alarm" -> AudioManager.STREAM_ALARM
                "notification" -> AudioManager.STREAM_NOTIFICATION
                "system" -> AudioManager.STREAM_SYSTEM
                else -> AudioManager.STREAM_MUSIC
            }
            val maxVolume = audioManager.getStreamMaxVolume(streamType)
            val targetVolume = (level * maxVolume / 100).coerceIn(0, maxVolume)
            audioManager.setStreamVolume(streamType, targetVolume, 0)
            return ActionResult(true, "$type volume set to $level%!", null)
        }
    }

    private class SetBrightnessAction : Action {
        override val name: String = "SET_BRIGHTNESS"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val levelStr = params["level"] ?: "50"
            val level = levelStr.replace("%", "").trim().toIntOrNull()?.coerceIn(0, 100) ?: 50
            return try {
                if (Settings.System.canWrite(context)) {
                    val brightnessValue = (level * 255 / 100).coerceIn(0, 255)
                    Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, brightnessValue)
                    ActionResult(true, "Brightness set to $level%!", null)
                } else {
                    val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    ActionResult(false, null, "Need 'Modify system settings' permission. Opened settings for you.", true)
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't set brightness: ${e.message}")
            }
        }
    }

    private class OpenAppAction : Action {
        override val name: String = "OPEN_APP"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val appName = params["appName"] ?: params["app"]
                ?: return ActionResult(false, null, "appName parameter missing")
            return try {
                val pm = context.packageManager
                val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                val found = packages.firstOrNull { app ->
                    pm.getApplicationLabel(app).toString().equals(appName, ignoreCase = true)
                }
                if (found != null) {
                    val launchIntent = pm.getLaunchIntentForPackage(found.packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (launchIntent != null) {
                        context.startActivity(launchIntent)
                        return ActionResult(true, "Opening $appName!", null)
                    }
                }
                // Fallback: search by partial name
                val partial = packages.firstOrNull { app ->
                    pm.getApplicationLabel(app).toString().contains(appName, ignoreCase = true)
                }
                if (partial != null) {
                    val launchIntent = pm.getLaunchIntentForPackage(partial.packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (launchIntent != null) {
                        context.startActivity(launchIntent)
                        return ActionResult(true, "Opening ${pm.getApplicationLabel(partial)}!", null)
                    }
                }
                ActionResult(false, null, "Couldn't find app '$appName'. Is it installed?")
            } catch (e: Exception) {
                Log.e("OpenApp", "Failed: ${e.message}")
                ActionResult(false, null, "Couldn't open '$appName'.")
            }
        }
    }

    private class LockScreenAction : Action {
        override val name: String = "LOCK_SCREEN"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val service = OpenDroidAccessibilityService.getInstance()
                if (service != null) {
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                    ActionResult(true, "Screen locked!", null)
                } else {
                    val intent = Intent(Intent.ACTION_SCREEN_OFF)
                    ActionResult(false, null, "Accessibility service not running — can't lock screen.")
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't lock the screen.")
            }
        }
    }

    private class ToggleBluetoothAction : Action {
        override val name: String = "TOGGLE_BLUETOOTH"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val state = (params["state"] ?: "toggle").lowercase()
            return try {
                val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Bluetooth settings opened!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open Bluetooth settings.")
            }
        }
    }

    private class ToggleDndAction : Action {
        override val name: String = "TOGGLE_DND"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (notificationManager?.isNotificationPolicyAccessGranted == true) {
                    val state = (params["state"] ?: "toggle").lowercase()
                    val currentFilter = notificationManager.currentInterruptionFilter
                    val newFilter = when (state) {
                        "on" -> NotificationManager.INTERRUPTION_FILTER_NONE
                        "off" -> NotificationManager.INTERRUPTION_FILTER_ALL
                        else -> if (currentFilter == NotificationManager.INTERRUPTION_FILTER_NONE)
                            NotificationManager.INTERRUPTION_FILTER_ALL
                        else NotificationManager.INTERRUPTION_FILTER_NONE
                    }
                    notificationManager.setInterruptionFilter(newFilter)
                    val statusWord = if (newFilter == NotificationManager.INTERRUPTION_FILTER_NONE) "enabled" else "disabled"
                    ActionResult(true, "Do Not Disturb $statusWord!", null)
                } else {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    ActionResult(false, null, "Need DND permission. Opened settings for you.", true)
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't toggle Do Not Disturb.")
            }
        }
    }

    private class TakeScreenshotAction : Action {
        override val name: String = "TAKE_SCREENSHOT"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val service = OpenDroidAccessibilityService.getInstance()
                if (service != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val base64 = service.takeScreenshotAndEncode()
                    if (base64 != null) {
                        ActionResult.Success(mapOf("message" to "Screenshot taken!", "base64" to base64))
                    } else {
                        ActionResult(false, null, "Screenshot capture failed.")
                    }
                } else {
                    ActionResult(false, null, "Screenshots require Android 11+ and accessibility service enabled.")
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Screenshot failed: ${e.message}")
            }
        }
    }

    private class ToggleMobileDataAction : Action {
        override val name: String = "TOGGLE_MOBILE_DATA"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent(Settings.ACTION_DATA_ROAMING_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Mobile data settings opened!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open mobile data settings.")
            }
        }
    }

    private inner class GetSystemInfoAction : Action {
        override val name: String = "GET_SYSTEM_INFO"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val info = deviceStateProvider.getSystemInfoSummary()
                ActionResult(true, info, null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't get system info.")
            }
        }
    }

    private class SetRingerModeAction : Action {
        override val name: String = "SET_RINGER_MODE"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val mode = params["mode"]?.lowercase() ?: return ActionResult(false, null, "mode parameter missing")
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return ActionResult(false, null, "Audio service unavailable")
            val ringerMode = when (mode) {
                "silent" -> AudioManager.RINGER_MODE_SILENT
                "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                "normal" -> AudioManager.RINGER_MODE_NORMAL
                else -> return ActionResult(false, null, "Unknown mode: $mode")
            }
            audioManager.ringerMode = ringerMode
            return ActionResult(true, "Ringer set to $mode!", null)
        }
    }

    private class AnalyzeScreenshotAction(private val visionEngine: VisionEngine) : Action {
        override val name: String = "ANALYZE_SCREENSHOT"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val question = params["question"] ?: "What do you see on screen?"
            return try {
                val result = visionEngine.analyzeCurrentScreen(question)
                ActionResult(true, result, null)
            } catch (e: Exception) {
                ActionResult(false, null, "Screen analysis failed: ${e.message}")
            }
        }
    }

    private class ClearClipboardAction : Action {
        override val name: String = "CLEAR_CLIPBOARD"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                cm?.setPrimaryClip(ClipData.newPlainText("", ""))
                ActionResult(true, "Clipboard cleared!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't clear the clipboard.")
            }
        }
    }

    private class CopyToClipboardAction : Action {
        override val name: String = "COPY_TO_CLIPBOARD"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val text = params["text"] ?: return ActionResult(false, null, "text parameter missing")
            return try {
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                cm?.setPrimaryClip(ClipData.newPlainText("text", text))
                ActionResult(true, "Copied to clipboard!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't copy to clipboard.")
            }
        }
    }

    private class GetClipboardAction : Action {
        override val name: String = "GET_CLIPBOARD"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                val clip = cm?.primaryClip
                if (clip != null && clip.itemCount > 0) {
                    val text = clip.getItemAt(0)?.text?.toString() ?: ""
                    if (text.isNotBlank()) {
                        ActionResult(true, "Clipboard: $text", null)
                    } else {
                        ActionResult(true, "Clipboard is empty.", null)
                    }
                } else {
                    ActionResult(true, "Clipboard is empty.", null)
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't read the clipboard.")
            }
        }
    }

    private class OpenBrowserAction : Action {
        override val name: String = "OPEN_BROWSER"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://google.com")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Browser opened!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the browser.")
            }
        }
    }

    private class OpenUrlAction : Action {
        override val name: String = "OPEN_URL"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val url = params["url"] ?: return ActionResult(false, null, "url parameter missing")
            val fullUrl = if (url.startsWith("http")) url else "https://$url"
            return try {
                val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(fullUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Opening $url!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open that URL.")
            }
        }
    }

    private class CloseAppAction : Action {
        override val name: String = "CLOSE_APP"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val service = OpenDroidAccessibilityService.getInstance()
                if (service != null) {
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                    delay(300)
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
                    ActionResult(true, "App closed!", null)
                } else {
                    ActionResult(false, null, "Accessibility service not running — can't close the app.")
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't close the app.")
            }
        }
    }

    private class AskUserAction : Action {
        override val name: String = "ASK_USER"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val question = params["question"] ?: "What would you like to do?"
            val options = params["options"]?.split(",")?.map { it.trim() }?.filter { it.isNotBlank() } ?: emptyList()
            return ActionResult.NeedsInput(question = question, options = options)
        }
    }
}
