package com.orailnoor.privatelm.opendroid.actions

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import com.orailnoor.privatelm.opendroid.actions.base.Action
import com.orailnoor.privatelm.opendroid.actions.base.ActionResult

class MediaActions {

    fun getActions(): List<Action> = listOf(
        PlayMusicAction(),
        PauseMusicAction(),
        NextTrackAction(),
        PrevTrackAction(),
        PlayYoutubeAction(),
        TakePhotoAction(),
        RecordVideoAction()
    )

    private class PlayMusicAction : Action {
        override val name: String = "PLAY_MUSIC"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val query = params["query"] ?: return ActionResult(false, null, "query parameter missing")
            val app = params["app"]?.lowercase() ?: "spotify"
            return try {
                when (app) {
                    "youtube" -> {
                        val intent = Intent(Intent.ACTION_SEARCH).apply {
                            setPackage("com.google.android.youtube")
                            putExtra("query", query)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                    }
                    else -> {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:$query")).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        try { context.startActivity(intent) } catch (e: Exception) {
                            val fallback = Intent(Intent.ACTION_VIEW,
                                Uri.parse("https://open.spotify.com/search/$query")).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(fallback)
                        }
                    }
                }
                ActionResult(true, "Playing $query!", null)
            } catch (e: Exception) {
                Log.e("PlayMusic", "Failed: ${e.message}")
                ActionResult(false, null, "Couldn't play music. Is Spotify/YouTube installed?")
            }
        }
    }

    private class PauseMusicAction : Action {
        override val name: String = "PAUSE_MUSIC"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent("com.android.music.musicservicecommand").apply {
                    putExtra("command", "pause")
                }
                context.sendBroadcast(intent)
                ActionResult(true, "Music paused!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't pause music.")
            }
        }
    }

    private class NextTrackAction : Action {
        override val name: String = "NEXT_TRACK"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent("com.android.music.musicservicecommand").apply {
                    putExtra("command", "next")
                }
                context.sendBroadcast(intent)
                ActionResult(true, "Skipped to next track!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't skip track.")
            }
        }
    }

    private class PrevTrackAction : Action {
        override val name: String = "PREV_TRACK"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent("com.android.music.musicservicecommand").apply {
                    putExtra("command", "previous")
                }
                context.sendBroadcast(intent)
                ActionResult(true, "Previous track!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't go to previous track.")
            }
        }
    }

    private class PlayYoutubeAction : Action {
        override val name: String = "PLAY_YOUTUBE"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            val query = params["query"] ?: return ActionResult(false, null, "query parameter missing")
            return try {
                val intent = Intent(Intent.ACTION_SEARCH).apply {
                    setPackage("com.google.android.youtube")
                    putExtra("query", query)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Searching YouTube for '$query'!", null)
            } catch (e: Exception) {
                val fallback = Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://www.youtube.com/results?search_query=${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallback)
                ActionResult(true, "Opened YouTube for '$query'!", null)
            }
        }
    }

    private class TakePhotoAction : Action {
        override val name: String = "TAKE_PHOTO"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Camera is open — take your photo!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the camera.")
            }
        }
    }

    private class RecordVideoAction : Action {
        override val name: String = "RECORD_VIDEO"
        override suspend fun execute(params: Map<String, String>, context: Context): ActionResult {
            return try {
                val intent = Intent(MediaStore.ACTION_VIDEO_CAPTURE).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                ActionResult(true, "Camera is open — start recording!", null)
            } catch (e: Exception) {
                ActionResult(false, null, "Couldn't open the video recorder.")
            }
        }
    }
}
