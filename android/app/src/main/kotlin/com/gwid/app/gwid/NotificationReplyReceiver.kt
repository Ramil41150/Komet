package com.gwid.app.gwid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput
import io.flutter.plugin.common.MethodChannel

class NotificationReplyReceiver : BroadcastReceiver() {
    companion object {
        private var methodChannel: MethodChannel? = null
        
        fun setMethodChannel(channel: MethodChannel) {
            methodChannel = channel
            android.util.Log.d("NotificationReplyReceiver", "MethodChannel set")
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.d("NotificationReplyReceiver", "onReceive called, action: ${intent.action}")
        
        if (intent.action == "com.gwid.app.REPLY_ACTION") {
            val remoteInput = RemoteInput.getResultsFromIntent(intent)
            if (remoteInput != null) {
                val replyText = remoteInput.getCharSequence("key_text_reply")?.toString()
                val chatId = intent.getLongExtra("chat_id", 0L)
                
                android.util.Log.d("NotificationReplyReceiver", "Reply text: $replyText, chatId: $chatId")
                
                if (replyText != null && replyText.isNotEmpty() && chatId != 0L) {
                    // Send reply via existing MethodChannel
                    try {
                        methodChannel?.invokeMethod("sendReplyFromNotification", mapOf(
                            "chatId" to chatId,
                            "text" to replyText
                        ))
                        android.util.Log.d("NotificationReplyReceiver", "Reply sent via MethodChannel")
                        
                        // Cancel notification after sending
                        val notificationHelper = NotificationHelper(context)
                        notificationHelper.cancelNotification(chatId)
                    } catch (e: Exception) {
                        android.util.Log.e("NotificationReplyReceiver", "Error sending via MethodChannel: ${e.message}")
                        // Save for processing on next app start
                        savePendingReply(context, chatId, replyText)
                    }
                }
            }
        }
    }
    
    private fun savePendingReply(context: Context, chatId: Long, text: String) {
        try {
            val prefs = context.getSharedPreferences("flutter_notification_replies", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            editor.putLong("pending_reply_chat_id", chatId)
            editor.putString("pending_reply_text", text)
            editor.putLong("pending_reply_timestamp", System.currentTimeMillis())
            editor.apply()
            android.util.Log.d("NotificationReplyReceiver", "Saved pending reply to SharedPreferences")
        } catch (e: Exception) {
            android.util.Log.e("NotificationReplyReceiver", "Error saving pending reply: ${e.message}")
        }
    }
}
