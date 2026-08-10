package com.vpmedia.vbotsdksample

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Quản lý notification "Đang trong cuộc gọi" khi cuộc gọi active.
 * - Tap notification → mở lại app
 * - Action "Tắt máy" → kết thúc cuộc gọi
 */
object OngoingCallNotification {
    private const val CHANNEL_ID = "vbot_ongoing_call"
    const val NOTIFICATION_ID = 9999

    fun show(context: Context, callerName: String) {
        val appContext = context.applicationContext
        val notificationManager =
            appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Tạo notification channel (Android 8+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Cuộc gọi đang diễn ra",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Intent mở app khi tap notification
        val contentIntent = PendingIntent.getActivity(
            appContext,
            0,
            Intent(appContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Intent tắt máy từ notification
        val hangupIntent = PendingIntent.getBroadcast(
            appContext,
            1,
            Intent(appContext, HangupReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Đang trong cuộc gọi")
            .setContentText(callerName)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(contentIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Tắt máy",
                hangupIntent
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        val notificationManager = context.applicationContext
            .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
    }
}
