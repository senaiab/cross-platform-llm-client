package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult

class FinanceActions {

    fun getActions(): List<Action> = listOf(
        PayUpiAction(),
        CheckBalanceAction(),
        SplitBillAction()
    )

    private class PayUpiAction : Action {
        override val name: String = "PAY_UPI"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val to = params["to"] ?: return ActionResult(false, null, "to parameter missing")
            val amount = params["amount"] ?: return ActionResult(false, null, "amount parameter missing")
            val note = params["note"] ?: ""
            val app = params["app"]?.lowercase() ?: "gpay"
            return try {
                val upiUri = "upi://pay?pa=$to&am=$amount&tn=${Uri.encode(note)}&cu=INR"
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(upiUri)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                val pm = context.packageManager
                if (pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).isNotEmpty()) {
                    context.startActivity(intent)
                    ActionResult(true, "UPI payment to $to for Rs $amount is ready — confirm to pay!", null)
                } else {
                    // Fallback to open the payment app
                    val pkg = when (app) {
                        "phonepe" -> "com.phonepe.app"
                        "paytm" -> "net.one97.paytm"
                        else -> "com.google.android.apps.nbu.paisa.user"
                    }
                    val launchIntent = pm.getLaunchIntentForPackage(pkg)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (launchIntent != null) {
                        context.startActivity(launchIntent)
                        ActionResult(true, "Payment app is open — pay Rs $amount to $to!", null)
                    } else {
                        ActionResult(false, null, "No UPI payment app found. Install GPay, PhonePe, or Paytm.")
                    }
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't initiate UPI payment.")
            }
        }
    }

    private class CheckBalanceAction : Action {
        override val name: String = "CHECK_BALANCE"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val pm = context.packageManager
                val gPayIntent = pm.getLaunchIntentForPackage("com.google.android.apps.nbu.paisa.user")
                    ?: pm.getLaunchIntentForPackage("net.one97.paytm")
                    ?: pm.getLaunchIntentForPackage("com.phonepe.app")
                if (gPayIntent != null) {
                    gPayIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(gPayIntent)
                    ActionResult(true, "Payment app is open — check your balance there!", null)
                } else {
                    ActionResult(false, null, "No payment app found.")
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open payment app.")
            }
        }
    }

    private class SplitBillAction : Action {
        override val name: String = "SPLIT_BILL"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val totalAmount = params["totalAmount"] ?: return ActionResult(false, null, "totalAmount parameter missing")
            val people = params["people"] ?: return ActionResult(false, null, "people parameter missing")
            return try {
                val peopleCount = people.toIntOrNull()
                if (peopleCount != null && peopleCount > 0) {
                    val total = totalAmount.replace("[^0-9.]".toRegex(), "").toDoubleOrNull() ?: 0.0
                    val perPerson = total / peopleCount
                    ActionResult(true, "Split Rs $totalAmount among $peopleCount people: Rs ${"%.2f".format(perPerson)} each!", null)
                } else {
                    val names = people.split(",").map { it.trim() }.filter { it.isNotBlank() }
                    val total = totalAmount.replace("[^0-9.]".toRegex(), "").toDoubleOrNull() ?: 0.0
                    val perPerson = if (names.isNotEmpty()) total / names.size else total
                    ActionResult(true, "Split Rs $totalAmount: Rs ${"%.2f".format(perPerson)} each for ${names.joinToString(", ")}!", null)
                }
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't calculate the split.")
            }
        }
    }
}
