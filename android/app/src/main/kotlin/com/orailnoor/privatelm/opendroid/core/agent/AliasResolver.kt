package com.orailnoor.privatelm.opendroid.core.agent

import com.orailnoor.privatelm.opendroid.core.util.DurationParser

object AliasResolver {

    private val appAliases = mapOf(
        "youtube" to "com.google.android.youtube",
        "chrome" to "com.android.chrome",
        "maps" to "com.google.android.apps.maps",
        "gmail" to "com.google.android.gm",
        "whatsapp" to "com.whatsapp",
        "instagram" to "com.instagram.android",
        "facebook" to "com.facebook.katana",
        "twitter" to "com.twitter.android",
        "spotify" to "com.spotify.music",
        "camera" to "android.media.action.IMAGE_CAPTURE",
        "photos" to "com.google.android.apps.photos",
        "settings" to "com.android.settings",
        "calculator" to "com.google.android.calculator",
        "calendar" to "com.google.android.calendar",
        "clock" to "com.google.android.deskclock",
        "phone" to "com.android.dialer",
        "messages" to "com.google.android.apps.messaging",
        "contacts" to "com.android.contacts",
        "files" to "com.google.android.documentsui",
        "play store" to "com.android.vending",
        "telegram" to "org.telegram.messenger",
        "netflix" to "com.netflix.mediaclient",
        "amazon" to "com.amazon.mShop.android.shopping",
        "zoom" to "us.zoom.videomeetings"
    )

    fun resolvePackageName(appName: String): String? {
        return appAliases[appName.lowercase().trim()]
    }

    fun parseDuration(input: String): Long {
        return DurationParser.parseToMillis(input)
    }
}
