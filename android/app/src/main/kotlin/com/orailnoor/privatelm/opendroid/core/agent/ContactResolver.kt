package com.orailnoor.privatelm.opendroid.core.agent

import android.content.Context
import android.provider.ContactsContract
import android.util.Log
import com.orailnoor.privatelm.opendroid.core.memory.MemoryManager

data class ContactResolution(
    val resolvedName: String?,
    val phoneNumber: String?,
    val isAmbiguous: Boolean = false,
    val candidates: List<ContactCandidate> = emptyList()
)

data class ContactCandidate(
    val name: String,
    val phoneNumber: String
)

class ContactResolver(
    private val context: Context,
    private val memoryManager: MemoryManager
) {

    suspend fun resolveWithDisambiguation(input: String): ContactResolution {
        val trimmed = input.trim()

        // Check if it's already a phone number
        if (trimmed.matches(Regex("[+\\d\\s\\-()]{7,}"))) {
            return ContactResolution(resolvedName = null, phoneNumber = trimmed.replace("\\s".toRegex(), ""))
        }

        // Check memory for remembered preference
        val remembered = memoryManager.recallContactPreference(trimmed)
        if (remembered != null) {
            return ContactResolution(resolvedName = trimmed, phoneNumber = remembered)
        }

        // Look up in Android contacts
        val candidates = lookupContacts(trimmed)

        return when {
            candidates.isEmpty() -> ContactResolution(resolvedName = trimmed, phoneNumber = null)
            candidates.size == 1 -> ContactResolution(
                resolvedName = candidates[0].name,
                phoneNumber = candidates[0].phoneNumber
            )
            else -> ContactResolution(
                resolvedName = trimmed,
                phoneNumber = candidates[0].phoneNumber,
                isAmbiguous = true,
                candidates = candidates
            )
        }
    }

    private fun lookupContacts(name: String): List<ContactCandidate> {
        val results = mutableListOf<ContactCandidate>()
        try {
            val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            val selection = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
            val selectionArgs = arrayOf("%$name%")

            context.contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val contactName = cursor.getString(0) ?: continue
                    val phone = cursor.getString(1) ?: continue
                    results.add(ContactCandidate(contactName, phone.replace("\\s".toRegex(), "")))
                }
            }
        } catch (e: Exception) {
            Log.e("ContactResolver", "Failed to look up contact: ${e.message}")
        }
        return results
    }

    companion object {
        fun maskPhone(phone: String): String {
            if (phone.length < 4) return "****"
            return "*".repeat(phone.length - 4) + phone.takeLast(4)
        }
    }
}
