package com.orailnoor.privatelm.opendroid.actions

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.orailnoor.privatelm.opendroid.accessibility.CallAutomator
import com.orailnoor.privatelm.opendroid.accessibility.OpenDroidAccessibilityService
import com.orailnoor.privatelm.opendroid.accessibility.SmsAutomator
import com.orailnoor.privatelm.opendroid.accessibility.WhatsAppAutomator
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult
import com.orailnoor.privatelm.opendroid.core.agent.ContactResolution
import com.orailnoor.privatelm.opendroid.core.agent.ContactResolver
import java.net.URLEncoder

class CommunicationActions(private val contactResolver: ContactResolver) {

    fun getActions(): List<Action> = listOf(
        MakeCallAction(),
        SendWhatsAppAction(),
        SendSmsAction(),
        SendEmailAction(),
        SendWhatsAppGroupAction(),
        MakeVideoCallAction(),
        ReadMessagesAction(),
        ReadEmailsAction()
    )

    private inner class MakeCallAction : Action {
        override val name: String = "MAKE_CALL"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val contact = params["contact"] ?: params["number"] ?: params["phone"]
                ?: return ActionResult(false, null, "contact or number parameter missing")

            val resolved = contactResolver.resolveWithDisambiguation(contact)
            val phone = resolved.phoneNumber
                ?: return ActionResult.NeedsInput(
                    question = "I couldn't find '$contact' in your contacts. What's their number?",
                    metadata = mapOf("param" to "contact")
                )

            if (resolved.isAmbiguous && resolved.candidates.isNotEmpty()) {
                return ActionResult.NeedsInput(
                    question = "Which '${contact}' did you mean?",
                    options = resolved.candidates.mapIndexed { i, c ->
                        "${i + 1}. ${c.name} (${ContactResolver.maskPhone(c.phoneNumber)})"
                    }
                )
            }

            return executeCall(phone, contact, context)
        }
    }

    private inner class SendWhatsAppAction : Action {
        override val name: String = "SEND_WHATSAPP"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val contact = params["contact"] ?: return ActionResult(false, null, "contact is missing")
            val message = params["message"] ?: return ActionResult(false, null, "message is missing")

            val resolved = contactResolver.resolveWithDisambiguation(contact)
            val phone = resolved.phoneNumber
                ?: return ActionResult.NeedsInput(
                    question = "I couldn't find '$contact'. What's their WhatsApp number?",
                    metadata = mapOf("param" to "contact")
                )

            return executeWhatsApp(phone, contact, message, context)
        }
    }

    private inner class SendSmsAction : Action {
        override val name: String = "SEND_SMS"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val contact = params["contact"] ?: params["to"] ?: params["recipient"]
                ?: return ActionResult(false, null, "contact parameter missing")
            val message = params["message"] ?: params["text"] ?: params["body"]
                ?: return ActionResult(false, null, "message parameter missing")

            val resolved = contactResolver.resolveWithDisambiguation(contact)
            val phone = resolved.phoneNumber
                ?: return ActionResult.NeedsInput(
                    question = "I couldn't find '$contact'. What's their phone number?",
                    metadata = mapOf("param" to "contact")
                )

            return executeSms(phone, contact, message, context)
        }
    }

    private suspend fun executeCall(phone: String, contactLabel: String, context: Context): ActionResult {
        val cleanPhone = phone.replace(Regex("[\\s\\-()]"), "").trim()
        return try {
            val callUri = Uri.parse("tel:$cleanPhone")
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                val intent = Intent(Intent.ACTION_CALL, callUri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Calling $contactLabel now!", null)
            } else {
                val intent = Intent(Intent.ACTION_DIAL, callUri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                val clicked = CallAutomator.makeCall(context, cleanPhone)
                if (clicked) ActionResult(true, "Calling $contactLabel now!", null)
                else ActionResult(false, null, "I've opened the dialer for $contactLabel — please tap call.", true)
            }
        } catch (e: Exception) {
            Log.e("MakeCall", "Call failed: ${e.localizedMessage}")
            ActionResult(false, null, "Couldn't make that call. Try again?")
        }
    }

    private suspend fun executeWhatsApp(phone: String, contactLabel: String, message: String, context: Context): ActionResult {
        return try {
            val encodedMsg = URLEncoder.encode(message, "UTF-8")
            val whatsappUri = Uri.parse("https://api.whatsapp.com/send?phone=$phone&text=$encodedMsg")
            val intent = Intent(Intent.ACTION_VIEW, whatsappUri).apply {
                setPackage("com.whatsapp")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            val autoSent = WhatsAppAutomator.automateSend(message)
            if (autoSent) ActionResult(true, "Sent your message to $contactLabel!", null)
            else ActionResult(false, null, "WhatsApp chat is open with your message ready — tap Send!", true)
        } catch (e: Exception) {
            Log.e("SendWhatsApp", "WhatsApp failed: ${e.localizedMessage}")
            ActionResult(false, null, "WhatsApp didn't work: ${e.localizedMessage}", true)
        }
    }

    private suspend fun executeSms(phone: String, contactLabel: String, message: String, context: Context): ActionResult {
        return try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                val smsManager = context.getSystemService(SmsManager::class.java)
                if (smsManager != null) {
                    smsManager.sendTextMessage(phone, null, message, null, null)
                    return ActionResult(true, "Text sent to $contactLabel!", null)
                }
            }
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("smsto:$phone")
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            val autoSent = SmsAutomator.sendSms(context, phone, message)
            if (autoSent) ActionResult(true, "Sent SMS to $contactLabel!", null)
            else ActionResult(false, null, "Messaging app is open — please tap send.", true)
        } catch (e: Exception) {
            Log.e("SendSMS", "SMS failed: ${e.localizedMessage}")
            ActionResult(false, null, "Couldn't open messaging. Try again?")
        }
    }

    private inner class SendEmailAction : Action {
        override val name: String = "SEND_EMAIL"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val to = params["to"] ?: return ActionResult(false, null, "to email is missing")
            val subject = params["subject"] ?: ""
            val body = params["body"] ?: ""
            return try {
                val intent = Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("mailto:")
                    putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, body)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Email to $to is ready — just review and send!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the email app.")
            }
        }
    }

    private inner class SendWhatsAppGroupAction : Action {
        override val name: String = "SEND_WHATSAPP_GROUP"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val groupName = params["groupName"] ?: return ActionResult(false, null, "groupName parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    setPackage("com.whatsapp")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "WhatsApp is open — find the '$groupName' group and send your message!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open WhatsApp. Is it installed?")
            }
        }
    }

    private inner class MakeVideoCallAction : Action {
        override val name: String = "MAKE_VIDEO_CALL"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val contact = params["contact"] ?: return ActionResult(false, null, "contact parameter missing")
            val resolved = contactResolver.resolveWithDisambiguation(contact)
            val phone = resolved.phoneNumber ?: ""
            return try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://api.whatsapp.com/send?phone=$phone")).apply {
                    setPackage("com.whatsapp")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Video call to $contact is starting!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't start the video call. Try again?")
            }
        }
    }

    private class ReadMessagesAction : Action {
        override val name: String = "READ_MESSAGES"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_APP_MESSAGING)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Messages app is open!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the messaging app.")
            }
        }
    }

    private class ReadEmailsAction : Action {
        override val name: String = "READ_EMAILS"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_APP_EMAIL)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Your email is open!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the email app.")
            }
        }
    }
}
