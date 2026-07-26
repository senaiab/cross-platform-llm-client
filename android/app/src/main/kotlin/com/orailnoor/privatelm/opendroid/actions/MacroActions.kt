package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.util.Log
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult
import com.orailnoor.privatelm.opendroid.data.db.dao.MacroDao
import com.orailnoor.privatelm.opendroid.data.db.entities.MacroEntity
import java.util.UUID

class MacroActions(private val macroDao: MacroDao) {

    fun getActions(): List<Action> = listOf(
        RunMacroAction(macroDao),
        CreateMacroAction(macroDao),
        ScheduleMacroAction(macroDao)
    )

    private class RunMacroAction(private val macroDao: MacroDao) : Action {
        override val name: String = "RUN_MACRO"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val macroName = params["macroName"] ?: return ActionResult(false, null, "macroName parameter missing")
            return try {
                val macro = macroDao.getMacroByName(macroName)
                if (macro != null) {
                    ActionResult(true, macro.stepsJson, null)
                } else {
                    ActionResult(false, null, "Macro '$macroName' not found.")
                }
            } catch (e: Exception) {
                Log.e("RunMacro", "Macro failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't run that macro right now.")
            }
        }
    }

    private class CreateMacroAction(private val macroDao: MacroDao) : Action {
        override val name: String = "CREATE_MACRO"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val name = params["name"] ?: return ActionResult(false, null, "name parameter missing")
            val steps = params["steps"] ?: return ActionResult(false, null, "steps parameter missing")
            return try {
                val entity = MacroEntity(
                    id = UUID.randomUUID().toString(),
                    name = name,
                    trigger = "manual",
                    stepsJson = steps,
                    isSystem = false,
                    isEnabled = true
                )
                macroDao.insertMacro(entity)
                ActionResult(true, "Macro '$name' is ready!", null)
            } catch (e: Exception) {
                Log.e("CreateMacro", "Create failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't create that macro.")
            }
        }
    }

    private class ScheduleMacroAction(private val macroDao: MacroDao) : Action {
        override val name: String = "SCHEDULE_MACRO"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val macroName = params["macroName"] ?: return ActionResult(false, null, "macroName parameter missing")
            val cronExpression = params["cronExpression"] ?: return ActionResult(false, null, "cronExpression parameter missing")
            return try {
                val macro = macroDao.getMacroByName(macroName)
                    ?: MacroEntity(
                        id = UUID.randomUUID().toString(),
                        name = macroName,
                        trigger = "cron:$cronExpression",
                        stepsJson = "[]",
                        isSystem = false,
                        isEnabled = true
                    )
                macroDao.insertMacro(macro.copy(trigger = "cron:$cronExpression"))
                ActionResult(true, "Macro '$macroName' is scheduled!", null)
            } catch (e: Exception) {
                Log.e("ScheduleMacro", "Schedule failed: ${e.localizedMessage}")
                ActionResult(false, null, "Couldn't schedule that macro.")
            }
        }
    }
}
