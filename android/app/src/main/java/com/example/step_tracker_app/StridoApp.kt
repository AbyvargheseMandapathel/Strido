package com.example.step_tracker_app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.work.Configuration
import androidx.work.WorkManager

class StridoApp : Application(), Configuration.Provider {

    companion object {
        const val NOTIFICATION_CHANNEL_ID = "strido_foreground_channel"
        const val NOTIFICATION_CHANNEL_NAME = "Strido Tracker Service"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initializeWorkManager()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Strido running in the background to track your steps 24/7"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }

            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun initializeWorkManager() {
        WorkManager.initialize(
            this,
            workManagerConfiguration
        )
    }

    // ✅ Correct way to implement Configuration.Provider
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()
}
