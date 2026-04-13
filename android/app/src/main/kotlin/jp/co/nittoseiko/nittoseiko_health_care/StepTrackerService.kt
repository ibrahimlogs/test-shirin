package jp.co.nittoseiko.nittoseiko_health_care

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Device
import kotlinx.coroutines.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class StepTrackerService : Service(), SensorEventListener {

    companion object {
        const val ACTION_START = "jp.co.nittoseiko.nittoseiko_health_care.action.START"
        const val ACTION_STOP = "jp.co.nittoseiko.nittoseiko_health_care.action.STOP"
        const val ACTION_SET_GOAL = "jp.co.nittoseiko.nittoseiko_health_care.action.SET_GOAL"
        const val ACTION_SET_THRESHOLDS = "jp.co.nittoseiko.nittoseiko_health_care.action.SET_THRESHOLDS"
        const val ACTION_SET_MODE = "jp.co.nittoseiko.nittoseiko_health_care.action.SET_MODE"
        // NEW: force-write whatever is pending so DB == notification
        const val ACTION_FLUSH = "jp.co.nittoseiko.nittoseiko_health_care.action.FLUSH"
        const val EXTRA_GOAL = "extra_goal"
        const val EXTRA_MIN_STEPS = "extra_min_steps"
        const val EXTRA_MIN_MINUTES = "extra_min_minutes"
        const val EXTRA_FORCE_RO = "extra_force_ro"
    }

    private val TAG = "StepTrackerService"
    private val CHANNEL_ID = "StepTrackerChannel"
    private val NOTIF_ID = 1

    private val PREF = "step_tracker_prefs"
    private val KEY_LAST_TODAY = "last_today_steps"
    private val KEY_FORCE_RO = "force_read_only"
    private val KEY_TODAY_ACC = "today_accumulated"
    private val KEY_TODAY_YMD = "today_ymd"

    private var minStepsToWrite: Long = 30L
    private var minTimeToWriteMs: Long = 30_000L
    private var dailyGoal: Int = 10_000
    private val MAX_REPORT_LATENCY_MS = 30_000

    private lateinit var sensorManager: SensorManager
    private var stepCounter: Sensor? = null
    private var hc: HealthConnectClient? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private lateinit var db: StepLogDb
    private var heartbeatJob: Job? = null

    private var accumulatedToday: Int = 0
    private var lastCum: Long = -1L
    private var lastSampleCum: Long = -1L
    private var lastSampleTime: Long = 0L
    private var lastYmd: String = LocalDate.now().toString()

    private var lastWriteTime: Instant = Instant.EPOCH
    private var forceReadOnly: Boolean = true

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounter = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        hc = try {
            HealthConnectClient.getOrCreate(this)
        } catch (t: Throwable) {
            Log.w(TAG, "Health Connect unavailable; running local-only step tracking.", t)
            null
        }
        db = StepLogDb(this)

        forceReadOnly = getSharedPreferences(PREF, MODE_PRIVATE).getBoolean(KEY_FORCE_RO, true)

        createNotificationChannel()

        val p = getSharedPreferences(PREF, MODE_PRIVATE)
        val savedYmd = p.getString(KEY_TODAY_YMD, null)
        val todayYmd = LocalDate.now().toString()
        accumulatedToday = if (savedYmd == todayYmd) p.getInt(KEY_TODAY_ACC, 0) else 0
        lastYmd = todayYmd
        p.edit().putString(KEY_TODAY_YMD, todayYmd).apply()

        startForeground(NOTIF_ID, buildNotification(today = accumulatedToday))

        if (stepCounter == null) {
            Log.w(TAG, "No TYPE_STEP_COUNTER; stopping.")
            stopSelf()
            return
        }

        // Heartbeat every 30s: keep timeline alive and detect midnight rollover eagerly
        heartbeatJob = scope.launch {
            while (isActive) {
                try {
                    delay(minTimeToWriteMs)
                    val now = System.currentTimeMillis()
                    val ymdNow = LocalDate.now().toString()

                    if (ymdNow != lastYmd) {
                        // New day even without sensor events
                        accumulatedToday = 0
                        lastSampleCum = -1L
                        lastSampleTime = 0L
                        lastYmd = ymdNow
                        val pp = getSharedPreferences(PREF, MODE_PRIVATE)
                        pp.edit().putString(KEY_TODAY_YMD, ymdNow)
                            .putInt(KEY_TODAY_ACC, 0)
                            .putInt(KEY_LAST_TODAY, 0)
                            .apply()
                        updateProgress(0)
                        db.insertSample(now, ymdNow, 0)
                        db.pruneKeepLastDays(7)
                    } else {
                        // Keep-alive row so UI shows recent time ticks
                        if (lastSampleTime == 0L || (now - lastSampleTime) >= minTimeToWriteMs) {
                            db.insertSample(now, ymdNow, 0)
                            lastSampleTime = now
                            db.pruneKeepLastDays(7)
                        }
                    }
                } catch (_: Throwable) {}
            }
        }

        RestartReceiver.schedule(this, delayMs = 60_000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SET_GOAL -> {
                val g = intent.getIntExtra(EXTRA_GOAL, dailyGoal).coerceAtLeast(1)
                dailyGoal = g
                updateProgress(accumulatedToday)
            }
            ACTION_SET_THRESHOLDS -> {
                val steps = intent.getLongExtra(EXTRA_MIN_STEPS, minStepsToWrite)
                val mins = intent.getIntExtra(EXTRA_MIN_MINUTES, (minTimeToWriteMs / 60_000L).toInt())
                minStepsToWrite = steps.coerceAtLeast(1)
                minTimeToWriteMs = (mins.coerceAtLeast(1)) * 60_000L
            }
            ACTION_SET_MODE -> {
                forceReadOnly = intent.getBooleanExtra(EXTRA_FORCE_RO, true)
                getSharedPreferences(PREF, MODE_PRIVATE).edit()
                    .putBoolean(KEY_FORCE_RO, forceReadOnly)
                    .apply()
                updateProgress(accumulatedToday)
            }
            ACTION_FLUSH -> {
                // Force-write current pending delta into local DB, even if below thresholds.
                val ymdNow = LocalDate.now().toString()
                if (lastSampleCum >= 0L && lastCum >= 0L) {
                    val now = System.currentTimeMillis()
                    val delta = (lastCum - lastSampleCum).toInt().coerceAtLeast(0)
                    db.insertSample(now, ymdNow, delta)
                    db.pruneKeepLastDays(7)
                    lastSampleCum = lastCum
                    lastSampleTime = now
                } else {
                    // No baseline yet ⇒ write a zero row so readers still get a fresh timestamp
                    val now = System.currentTimeMillis()
                    db.insertSample(now, ymdNow, 0)
                    db.pruneKeepLastDays(7)
                    lastSampleTime = now
                }
                // Also reflect current accumulator in prefs so Flutter getToday() stays aligned
                getSharedPreferences(PREF, MODE_PRIVATE).edit()
                    .putInt(KEY_LAST_TODAY, accumulatedToday.coerceAtLeast(0))
                    .putInt(KEY_TODAY_ACC, accumulatedToday.coerceAtLeast(0))
                    .apply()
                updateProgress(accumulatedToday)
            }
        }

        val delay = SensorManager.SENSOR_DELAY_NORMAL
        val maxLatencyUs = MAX_REPORT_LATENCY_MS * 1000
        sensorManager.registerListener(this, stepCounter, delay, maxLatencyUs)

        updateProgress(accumulatedToday)
        RestartReceiver.schedule(this, delayMs = 60_000L)
        return START_STICKY
    }

    override fun onDestroy() {
        heartbeatJob?.cancel()
        sensorManager.unregisterListener(this)
        RestartReceiver.schedule(this, delayMs = 2_000L)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val i = Intent(applicationContext, StepTrackerService::class.java).apply {
            action = ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try { startForegroundService(i) } catch (_: Throwable) {}
        } else {
            try { startService(i) } catch (_: Throwable) {}
        }
        RestartReceiver.schedule(this, delayMs = 2_000L)
        RestartReceiver.schedule(this, delayMs = 30_000L)
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(event: SensorEvent?) {
        val e = event ?: return
        if (e.sensor.type != Sensor.TYPE_STEP_COUNTER) return

        val cum = e.values.getOrNull(0)?.toLong() ?: return
        val ymdNow = LocalDate.now().toString()

        val p = getSharedPreferences(PREF, MODE_PRIVATE)
        val savedYmd = p.getString(KEY_TODAY_YMD, ymdNow)
        if (savedYmd != ymdNow) {
            accumulatedToday = 0
            p.edit().putString(KEY_TODAY_YMD, ymdNow)
                .putInt(KEY_TODAY_ACC, 0)
                .putInt(KEY_LAST_TODAY, 0)
                .apply()
            lastSampleCum = -1L
            lastSampleTime = 0L
            lastYmd = ymdNow
            updateProgress(0)
        }

        if (lastCum < 0L) lastCum = cum
        if (lastSampleCum < 0L) {
            lastSampleCum = cum
            lastSampleTime = System.currentTimeMillis()
            updateProgress(accumulatedToday)
            return
        }

        if (cum < lastCum) {
            lastCum = cum
            lastSampleCum = cum
            lastSampleTime = System.currentTimeMillis()
            updateProgress(accumulatedToday)
            return
        }

        val delta = cum - lastCum
        lastCum = cum

        val now = System.currentTimeMillis()
        val sinceSample = now - lastSampleTime
        val deltaSinceSample = cum - lastSampleCum

        if (delta > 0) {
            accumulatedToday = (accumulatedToday + delta.toInt()).coerceAtLeast(0)
            updateProgress(accumulatedToday)
        }

        if (deltaSinceSample >= minStepsToWrite || sinceSample >= minTimeToWriteMs) {
            val toWrite = if (deltaSinceSample > 0) deltaSinceSample.toInt() else 0
            db.insertSample(now, ymdNow, toWrite)
            db.pruneKeepLastDays(7)
            lastSampleCum = cum
            lastSampleTime = now
        }
    }

    // (kept for future HC writes)
    private fun writeStepsToHC(count: Long, start: Instant, end: Instant, onOk: () -> Unit) {
        if (forceReadOnly) { onOk(); return }
        val client = hc ?: return
        scope.launch {
            try {
                val need = setOf(HealthPermission.getWritePermission(StepsRecord::class))
                val granted = client.permissionController.getGrantedPermissions()
                if (!granted.containsAll(need)) return@launch

                val zone = ZoneId.systemDefault()
                val rec = StepsRecord(
                    count = count,
                    startTime = start,
                    endTime = end,
                    startZoneOffset = zone.rules.getOffset(start),
                    endZoneOffset = zone.rules.getOffset(end),
                    metadata = androidx.health.connect.client.records.metadata.Metadata.autoRecorded(
                        device = Device(type = Device.TYPE_PHONE)
                    )
                )
                client.insertRecords(listOf(rec))
                onOk()
            } catch (_: Throwable) { }
        }
    }

    private fun buildNotification(today: Int): Notification {
        val i = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val b = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Steps ${today.coerceAtLeast(0)} / $dailyGoal")
            .setContentText("Tracking steps in background")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pi)
            .setProgress(dailyGoal, today.coerceAtMost(dailyGoal), false)

        if (Build.VERSION.SDK_INT >= 34) {
            b.setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return b.build()
    }

    private fun updateProgress(today: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(today))
        getSharedPreferences(PREF, MODE_PRIVATE).edit()
            .putInt(KEY_LAST_TODAY, today.coerceAtLeast(0))
            .putInt(KEY_TODAY_ACC, today.coerceAtLeast(0))
            .apply()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Step Tracker",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background step tracking"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }
}
