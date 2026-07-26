package com.orailnoor.privatelm.opendroid.core.agent

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs

class DeviceStateProvider(private val context: Context) {

    fun getBatteryLevel(): Int {
        val batteryStatus = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (level >= 0 && scale > 0) (level * 100 / scale) else -1
    }

    fun isCharging(): Boolean {
        val batteryStatus = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
               status == BatteryManager.BATTERY_STATUS_FULL
    }

    fun isWifiConnected(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    fun isMobileDataConnected(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
    }

    fun getAvailableStorageBytes(): Long {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return stat.availableBlocksLong * stat.blockSizeLong
    }

    fun getTotalStorageBytes(): Long {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return stat.blockCountLong * stat.blockSizeLong
    }

    fun getSystemInfoSummary(): String {
        val battery = getBatteryLevel()
        val charging = if (isCharging()) " (charging)" else ""
        val wifi = if (isWifiConnected()) "WiFi" else if (isMobileDataConnected()) "Mobile Data" else "No internet"
        val storageAvailMb = getAvailableStorageBytes() / (1024 * 1024)
        val storageTotalMb = getTotalStorageBytes() / (1024 * 1024)
        return "Battery: $battery%$charging | Network: $wifi | Storage: ${storageAvailMb}MB free / ${storageTotalMb}MB total"
    }
}
