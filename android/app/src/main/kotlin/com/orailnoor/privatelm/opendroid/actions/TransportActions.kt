package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult

class TransportActions {

    fun getActions(): List<Action> = listOf(
        GetDirectionsAction(),
        BookUberAction(),
        CheckTrafficAction()
    )

    private class GetDirectionsAction : Action {
        override val name: String = "GET_DIRECTIONS"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val to = params["to"] ?: return ActionResult(false, null, "to parameter missing")
            val from = params["from"] ?: ""
            val mode = params["mode"] ?: "drive"
            val modeCode = when (mode.lowercase()) {
                "walk" -> "w"
                "transit" -> "r"
                "bike" -> "b"
                else -> "d"
            }
            val uriStr = if (from.isNotBlank()) {
                "https://maps.google.com/maps?saddr=${Uri.encode(from)}&daddr=${Uri.encode(to)}&dirflg=$modeCode"
            } else {
                "https://maps.google.com/maps?daddr=${Uri.encode(to)}&dirflg=$modeCode"
            }
            return try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uriStr)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Opening directions to $to!", null)
            } catch (e: Exception) {
                Log.e("GetDirections", "Failed: ${e.message}")
                ActionResult(false, null, "Couldn't open maps. Is Google Maps installed?")
            }
        }
    }

    private class BookUberAction : Action {
        override val name: String = "BOOK_UBER"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val destination = params["destination"] ?: return ActionResult(false, null, "destination parameter missing")
            return try {
                val pm = context.packageManager
                val uberIntent = pm.getLaunchIntentForPackage("com.ubercab")
                if (uberIntent != null) {
                    uberIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(uberIntent)
                    ActionResult(true, "Uber is open — book your ride to $destination!", null)
                } else {
                    val webIntent = Intent(Intent.ACTION_VIEW,
                        Uri.parse("https://m.uber.com/ul/?action=setPickup&dropoff[nickname]=${Uri.encode(destination)}")).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(webIntent)
                    ActionResult(true, "Opened Uber web — book your ride to $destination!", null)
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open Uber.")
            }
        }
    }

    private class CheckTrafficAction : Action {
        override val name: String = "CHECK_TRAFFIC"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val route = params["route"] ?: "current location"
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://maps.google.com/maps?q=${Uri.encode(route)}&layer=t")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Opened traffic map for $route!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the traffic map.")
            }
        }
    }
}
