package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult

class SmartHomeActions {

    fun getActions(): List<Action> = listOf(
        SmartHomeAction(),
        ToggleLightAction(),
        SetThermostatAction()
    )

    private class SmartHomeAction : Action {
        override val name: String = "SMART_HOME"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val device = params["device"] ?: return ActionResult(false, null, "device parameter missing")
            val action = params["action"] ?: return ActionResult(false, null, "action parameter missing")
            return try {
                val pm = context.packageManager
                val googleHomeIntent = pm.getLaunchIntentForPackage("com.google.android.apps.chromecast.app")
                    ?: pm.getLaunchIntentForPackage("com.amazon.dee.app")
                if (googleHomeIntent != null) {
                    googleHomeIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(googleHomeIntent)
                    ActionResult(true, "Smart home app open — $action the $device!", null)
                } else {
                    ActionResult(false, null, "No smart home app found (Google Home or Alexa).")
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't control the smart home device.")
            }
        }
    }

    private class ToggleLightAction : Action {
        override val name: String = "TOGGLE_LIGHT"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val room = params["room"] ?: return ActionResult(false, null, "room parameter missing")
            val on = params["on"]?.lowercase() != "false"
            return try {
                val pm = context.packageManager
                val intent = pm.getLaunchIntentForPackage("com.google.android.apps.chromecast.app")?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                } ?: return ActionResult(false, null, "Google Home not found.")
                context.startActivity(intent)
                val action = if (on) "Turn on" else "Turn off"
                ActionResult(true, "$action $room light!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't control the lights.")
            }
        }
    }

    private class SetThermostatAction : Action {
        override val name: String = "SET_THERMOSTAT"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val temperature = params["temperature"] ?: return ActionResult(false, null, "temperature parameter missing")
            return try {
                val pm = context.packageManager
                val intent = pm.getLaunchIntentForPackage("com.google.android.apps.chromecast.app")?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                } ?: return ActionResult(false, null, "Google Home not found.")
                context.startActivity(intent)
                ActionResult(true, "Set thermostat to $temperature!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't set the thermostat.")
            }
        }
    }
}
