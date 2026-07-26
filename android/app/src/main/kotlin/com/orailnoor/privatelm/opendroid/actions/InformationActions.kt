package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult

class InformationActions {

    fun getActions(): List<Action> = listOf(
        WebSearchAction(),
        GetWeatherAction(),
        GetNewsAction(),
        CalculateAction(),
        TranslateAction(),
        DefineWordAction(),
        ConvertUnitsAction()
    )

    private class WebSearchAction : Action {
        override val name: String = "WEB_SEARCH"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val query = params["query"] ?: return ActionResult(false, null, "query parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/search?q=${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Searching for '$query'!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the browser.")
            }
        }
    }

    private class GetWeatherAction : Action {
        override val name: String = "GET_WEATHER"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val location = params["location"] ?: "current location"
            return try {
                val query = if (location == "current location") "weather today" else "weather in $location"
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/search?q=${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Opening weather for $location!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't get weather info.")
            }
        }
    }

    private class GetNewsAction : Action {
        override val name: String = "GET_NEWS"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val topic = params["topic"] ?: "latest news"
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://news.google.com/search?q=${Uri.encode(topic)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Opening news about '$topic'!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open news.")
            }
        }
    }

    private class CalculateAction : Action {
        override val name: String = "CALCULATE"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val expression = params["expression"] ?: return ActionResult(false, null, "expression parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/search?q=${Uri.encode(expression)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Calculating '$expression'!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open calculator.")
            }
        }
    }

    private class TranslateAction : Action {
        override val name: String = "TRANSLATE"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val text = params["text"] ?: return ActionResult(false, null, "text parameter missing")
            val to = params["to"] ?: return ActionResult(false, null, "to parameter missing")
            val from = params["from"] ?: "auto"
            return try {
                val url = "https://translate.google.com/?sl=$from&tl=${Uri.encode(to)}&text=${Uri.encode(text)}&op=translate"
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Translating to $to!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open translator.")
            }
        }
    }

    private class DefineWordAction : Action {
        override val name: String = "DEFINE_WORD"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val word = params["word"] ?: return ActionResult(false, null, "word parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/search?q=define+${Uri.encode(word)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Looking up '$word'!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open browser.")
            }
        }
    }

    private class ConvertUnitsAction : Action {
        override val name: String = "CONVERT_UNITS"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val value = params["value"] ?: return ActionResult(false, null, "value parameter missing")
            val from = params["from"] ?: return ActionResult(false, null, "from parameter missing")
            val to = params["to"] ?: return ActionResult(false, null, "to parameter missing")
            return try {
                val query = "$value $from to $to"
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.google.com/search?q=${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Converting $query!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open converter.")
            }
        }
    }
}
