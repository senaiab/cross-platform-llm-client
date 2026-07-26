package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.util.Log
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult
import com.orailnoor.privatelm.opendroid.core.util.DurationParser
import java.util.Calendar
import java.util.TimeZone

class CalendarActions {

    fun getActions(): List<Action> = listOf(
        CreateCalendarEventAction(),
        SetAlarmAction(),
        SetTimerAction(),
        AddNoteAction(),
        ListCalendarTodayAction(),
        ListCalendarWeekAction(),
        SetReminderAction(),
        CreateTaskAction(),
        ReadNotesAction()
    )

    private class CreateCalendarEventAction : Action {
        override val name: String = "CREATE_CALENDAR_EVENT"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val title = params["title"] ?: "New Event"
            return try {
                val intent = Intent(Intent.ACTION_INSERT).apply {
                    data = CalendarContract.Events.CONTENT_URI
                    putExtra(CalendarContract.Events.TITLE, title)
                    params["location"]?.let { putExtra(CalendarContract.Events.EVENT_LOCATION, it) }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Calendar is open — fill in the details for '$title'!", null)
            } catch (e: Exception) {
                Log.e("CalendarEvent", "Failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't open the calendar app.")
            }
        }
    }

    private class SetAlarmAction : Action {
        override val name: String = "SET_ALARM"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val timeStr = params["time"]
                ?: return ActionResult(false, null, "Time is required. Use format like '5 am' or '7:30'")
            val label = params["label"]?.trim() ?: "Alarm"
            val parsed = parseTimeString(timeStr)
                ?: return ActionResult(false, null, "Couldn't understand time '$timeStr'. Try '5 am', '7:30', or '14:00'")
            val (hour, minute) = parsed
            return try {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_HOUR, hour)
                    putExtra(AlarmClock.EXTRA_MINUTES, minute)
                    putExtra(AlarmClock.EXTRA_MESSAGE, label)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Alarm set for ${formatTime(hour, minute)}!", null)
            } catch (e: Exception) {
                Log.e("SetAlarm", "Failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't set the alarm. Please open the Clock app manually.")
            }
        }

        private fun parseTimeString(input: String): Pair<Int, Int>? {
            val clean = input.lowercase().trim().replace("o'clock", "").trim()
            when (clean) {
                "midnight" -> return Pair(0, 0)
                "noon", "midday" -> return Pair(12, 0)
                "morning" -> return Pair(8, 0)
                "afternoon" -> return Pair(14, 0)
                "evening" -> return Pair(18, 0)
                "night" -> return Pair(21, 0)
            }
            // "5 am", "5am", "11 pm"
            Regex("""^(\d{1,2})\s*(am|pm)$""").find(clean)?.let {
                var hour = it.groupValues[1].toInt()
                val isPm = it.groupValues[2] == "pm"
                if (isPm && hour != 12) hour += 12
                if (!isPm && hour == 12) hour = 0
                return if (hour <= 23) Pair(hour, 0) else null
            }
            // "5:30 am", "5:30"
            Regex("""^(\d{1,2})[:\.](\d{2})(?:\s*(am|pm))?$""").find(clean)?.let {
                var hour = it.groupValues[1].toInt()
                val minute = it.groupValues[2].toInt()
                val amPm = it.groupValues[3]
                if (amPm == "pm" && hour != 12) hour += 12
                if (amPm == "am" && hour == 12) hour = 0
                return if (hour <= 23 && minute <= 59) Pair(hour, minute) else null
            }
            // Just a number — assume AM if < 12
            Regex("""^(\d{1,2})$""").find(clean)?.let {
                val hour = it.groupValues[1].toInt()
                return if (hour <= 23) Pair(hour, 0) else null
            }
            return null
        }

        private fun formatTime(hour: Int, minute: Int): String {
            val h = if (hour % 12 == 0) 12 else hour % 12
            val m = if (minute == 0) "" else ":${minute.toString().padStart(2, '0')}"
            val amPm = if (hour < 12) "AM" else "PM"
            return "$h$m $amPm"
        }
    }

    private class SetTimerAction : Action {
        override val name: String = "SET_TIMER"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val duration = params["duration"] ?: return ActionResult(false, null, "duration parameter missing")
            val label = params["label"] ?: "Timer"
            val durationMs = DurationParser.parseToMillis(duration)
            val durationSec = (durationMs / 1000).toInt().coerceAtLeast(1)
            return try {
                val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                    putExtra(AlarmClock.EXTRA_LENGTH, durationSec)
                    putExtra(AlarmClock.EXTRA_MESSAGE, label)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Timer set for $duration!", null)
            } catch (e: Exception) {
                Log.e("SetTimer", "Failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't set the timer.")
            }
        }
    }

    private class AddNoteAction : Action {
        override val name: String = "ADD_NOTE"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val content = params["content"] ?: return ActionResult(false, null, "content parameter missing")
            val title = params["title"] ?: "Note"
            return try {
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, title)
                    putExtra(Intent.EXTRA_TEXT, content)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(Intent.createChooser(intent, "Save note to").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                ActionResult(true, "Note saved: $title", null)
            } catch (e: Exception) {
                Log.e("AddNote", "Failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't save the note.")
            }
        }
    }

    private class ListCalendarTodayAction : Action {
        override val name: String = "LIST_CALENDAR_TODAY"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = context.packageManager.getLaunchIntentForPackage("com.google.android.calendar")
                    ?: Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_APP_CALENDAR) }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                ActionResult(true, "Calendar is open — check today's schedule!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the calendar.")
            }
        }
    }

    private class ListCalendarWeekAction : Action {
        override val name: String = "LIST_CALENDAR_WEEK"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = context.packageManager.getLaunchIntentForPackage("com.google.android.calendar")
                    ?: Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_APP_CALENDAR) }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                ActionResult(true, "Calendar is open — view your week!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the calendar.")
            }
        }
    }

    private class SetReminderAction : Action {
        override val name: String = "SET_REMINDER"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val text = params["text"] ?: return ActionResult(false, null, "text parameter missing")
            val datetime = params["datetime"] ?: ""
            return try {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_MESSAGE, text)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Reminder set: $text", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't set the reminder. Please use your clock or calendar app.")
            }
        }
    }

    private class CreateTaskAction : Action {
        override val name: String = "CREATE_TASK"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val title = params["title"] ?: return ActionResult(false, null, "title parameter missing")
            return try {
                // Open Google Tasks or similar
                val intent = context.packageManager.getLaunchIntentForPackage("com.google.android.apps.tasks")
                    ?: Intent(Intent.ACTION_VIEW).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                ActionResult(true, "Tasks app is open — create your task: $title", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the tasks app.")
            }
        }
    }

    private class ReadNotesAction : Action {
        override val name: String = "READ_NOTES"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = context.packageManager.getLaunchIntentForPackage("com.google.android.keep")
                    ?: Intent(Intent.ACTION_MAIN).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                ActionResult(true, "Notes app is open!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the notes app.")
            }
        }
    }
}
