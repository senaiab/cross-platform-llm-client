package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult

class FoodShoppingActions {

    fun getActions(): List<Action> = listOf(
        OrderFoodAction(),
        OrderGroceryAction(),
        SearchAmazonAction(),
        SearchFlipkartAction()
    )

    private class OrderFoodAction : Action {
        override val name: String = "ORDER_FOOD"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val items = params["items"] ?: return ActionResult(false, null, "items parameter missing")
            val app = params["app"]?.lowercase() ?: "zomato"
            return try {
                val pm = context.packageManager
                val pkg = if (app == "swiggy") "in.swiggy.android" else "com.application.zomato"
                val launchIntent = pm.getLaunchIntentForPackage(pkg)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                } ?: Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://$app.com")).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                context.startActivity(launchIntent)
                ActionResult(true, "${app.replaceFirstChar { it.uppercase() }} is open — order $items!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open food delivery app.")
            }
        }
    }

    private class OrderGroceryAction : Action {
        override val name: String = "ORDER_GROCERY"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val items = params["items"] ?: return ActionResult(false, null, "items parameter missing")
            val app = params["app"]?.lowercase() ?: "blinkit"
            return try {
                val pkg = when (app) {
                    "zepto" -> "com.zepto.rider"
                    "bigbasket" -> "com.bigbasket"
                    else -> "com.grofers.customerapp"
                }
                val pm = context.packageManager
                val launchIntent = pm.getLaunchIntentForPackage(pkg)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                } ?: Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://$app.com")).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                context.startActivity(launchIntent)
                ActionResult(true, "${app.replaceFirstChar { it.uppercase() }} is open — order $items!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open grocery app.")
            }
        }
    }

    private class SearchAmazonAction : Action {
        override val name: String = "SEARCH_AMAZON"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val query = params["query"] ?: return ActionResult(false, null, "query parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.amazon.com/s?k=${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Searching Amazon for '$query'!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open Amazon.")
            }
        }
    }

    private class SearchFlipkartAction : Action {
        override val name: String = "SEARCH_FLIPKART"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val query = params["query"] ?: return ActionResult(false, null, "query parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.flipkart.com/search?q=${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Searching Flipkart for '$query'!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open Flipkart.")
            }
        }
    }
}
