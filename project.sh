#!/bin/bash
set -e
mkdir -p FakeMenu && cd FakeMenu
mkdir -p .
cat > build.gradle.kts <<'END_OF_FILE'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
END_OF_FILE
mkdir -p .
cat > gradle.properties <<'END_OF_FILE'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
END_OF_FILE
mkdir -p .
cat > settings.gradle.kts <<'END_OF_FILE'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "FakeMenu"
include(":app")
END_OF_FILE
mkdir -p app
cat > app/build.gradle.kts <<'END_OF_FILE'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.example.fakemenu"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.fakemenu"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
END_OF_FILE
mkdir -p app/src/main
cat > app/src/main/AndroidManifest.xml <<'END_OF_FILE'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service
            android:name=".OverlayService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="floating_menu" />
        </service>
    </application>
</manifest>
END_OF_FILE
mkdir -p app/src/main/java/com/example/fakemenu
cat > app/src/main/java/com/example/fakemenu/FloatingMenu.kt <<'END_OF_FILE'
package com.example.fakemenu

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

internal sealed class Item
internal class Toggle(val key: String, val label: String, val def: Boolean) : Item()
internal class Slide(val key: String, val label: String, val lo: Int, val hi: Int, val def: Int, val unit: String = "") : Item()

/** Плавающее меню. Это только интерфейс: ни в какие игры оно не вмешивается. */
class FloatingMenu(private val ctx: Context) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val dens = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * dens).toInt()
    private val live = ctx.getSharedPreferences("menu_live", Context.MODE_PRIVATE)
    private val saved = ctx.getSharedPreferences("menu_saved", Context.MODE_PRIVATE)

    private val tabs = listOf("Aimbot", "Visuals", "Misc", "Load")
    private val pages: List<List<Item>> = listOf(
        listOf(
            Toggle("aimbot", "Aimbot", true), Toggle("silent", "Silent (Test)", false),
            Toggle("vis", "Visibility check", true), Toggle("scope", "Scoping check", false),
            Toggle("shoot", "Shooting check", false), Toggle("drawfov", "Draw FOV", false),
            Slide("fov", "FOV", 1, 180, 60, "°"), Slide("smooth", "Smooth", 1, 20, 5)
        ),
        listOf(
            Toggle("box", "ESP Box", true), Toggle("name", "ESP Name", true),
            Toggle("hp", "ESP Health", false), Toggle("skel", "Skeleton", false),
            Toggle("dist", "Distance", false), Toggle("chams", "Chams", false),
            Slide("maxd", "Max distance", 10, 300, 150, " m")
        ),
        listOf(
            Toggle("fps", "FPS counter", false), Toggle("wm", "Watermark", true),
            Toggle("stream", "Streamer mode", false), Toggle("fov2", "Custom FOV", false),
            Slide("opacity", "Menu opacity", 30, 100, 100, "%")
        )
    )

    private val menuP = params(min(dp(330), ctx.resources.displayMetrics.widthPixels - dp(16)),
        min(dp(270), ctx.resources.displayMetrics.heightPixels - dp(16))).apply { x = dp(32); y = dp(24) }
    private val bubbleP = params(dp(48), dp(48))

    private lateinit var menuView: MenuRoot
    private lateinit var bubbleView: View
    private lateinit var titleTv: TextView
    private lateinit var content: LinearLayout
    private val tabViews = ArrayList<TextView>()
    private var menuAdded = false
    private var bubbleAdded = false

    private fun params(w: Int, h: Int) = WindowManager.LayoutParams(
        w, h, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.START }

    fun start() { buildMenu(); buildBubble(); showMenu() }

    fun stop() {
        if (menuAdded) wm.removeView(menuView)
        if (bubbleAdded) wm.removeView(bubbleView)
        menuAdded = false; bubbleAdded = false
    }

    private fun showMenu() {
        val dm = ctx.resources.displayMetrics
        if (bubbleAdded) {
            menuP.x = bubbleP.x.coerceIn(0, max(0, dm.widthPixels - menuP.width))
            menuP.y = bubbleP.y.coerceIn(0, max(0, dm.heightPixels - menuP.height))
            wm.removeView(bubbleView); bubbleAdded = false
        }
        if (!menuAdded) { wm.addView(menuView, menuP); menuAdded = true }
    }

    private fun showBubble() {
        if (menuAdded) {
            bubbleP.x = menuP.x; bubbleP.y = menuP.y
            wm.removeView(menuView); menuAdded = false
        }
        if (!bubbleAdded) { wm.addView(bubbleView, bubbleP); bubbleAdded = true }
    }

    private fun move(v: View, p: WindowManager.LayoutParams, dx: Float, dy: Float) {
        val dm = ctx.resources.displayMetrics
        p.x = (p.x + dx).toInt().coerceIn(0, max(0, dm.widthPixels - p.width))
        p.y = (p.y + dy).toInt().coerceIn(0, max(0, dm.heightPixels - p.height))
        wm.updateViewLayout(v, p)
    }

    private fun label(s: String, size: Float, color: Int, bold: Boolean = false) = TextView(ctx).apply {
        text = s; textSize = size; setTextColor(color); maxLines = 1
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun buildMenu() {
        val root = MenuRoot(ctx, dp(96)) { dx, dy -> move(menuView, menuP, dx, dy) }
        menuView = root
        root.orientation = LinearLayout.HORIZONTAL
        root.background = GradientDrawable().apply { setColor(0xFF1E1E20.toInt()); cornerRadius = dp(18).toFloat() }
        root.clipToOutline = true

        val side = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF19191A.toInt()) }
        root.addView(side, LinearLayout.LayoutParams(dp(96), MATCH_PARENT))
        side.addView(EmblemView(ctx), LinearLayout.LayoutParams(dp(34), dp(34)).apply {
            gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(14); bottomMargin = dp(12)
        })
        tabs.forEachIndexed { i, name ->
            val tv = label(name, 15f, Color.WHITE, true).apply {
                gravity = Gravity.CENTER; setOnClickListener { selectTab(i) }
            }
            tabViews.add(tv)
            side.addView(tv, LinearLayout.LayoutParams(MATCH_PARENT, dp(42)))
        }

        val right = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        root.addView(right, LinearLayout.LayoutParams(0, MATCH_PARENT, 1f))
        val head = LinearLayout(ctx).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), 0, dp(4), 0) }
        titleTv = label("", 13f, 0xFF8E8E93.toInt(), true)
        head.addView(titleTv, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        val hideBtn = label("—", 18f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER; setOnClickListener { menuView.post { showBubble() } }
        }
        head.addView(hideBtn, LinearLayout.LayoutParams(dp(44), dp(36)))
        right.addView(head, LinearLayout.LayoutParams(MATCH_PARENT, dp(36)))

        val sv = ScrollView(ctx).apply { isVerticalScrollBarEnabled = false; overScrollMode = View.OVER_SCROLL_NEVER }
        content = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        sv.addView(content, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        right.addView(sv, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))

        selectTab(0)
        applyOpacity()
    }

    private fun applyOpacity() { menuView.alpha = live.getInt("opacity", 100) / 100f }

    private fun selectTab(i: Int) {
        tabViews.forEachIndexed { j, tv ->
            tv.setBackgroundColor(if (j == i) 0xFF2C2C2E.toInt() else Color.TRANSPARENT)
            tv.setTextColor(if (j == i) Color.WHITE else 0xFFBDBDC2.toInt())
        }
        titleTv.text = tabs[i]
        content.removeAllViews()
        if (i == tabs.lastIndex) loadPage()
        else pages[i].forEach { content.addView(when (it) { is Toggle -> toggleRow(it); is Slide -> sliderRow(it) }) }
    }

    private fun toggleRow(t: Toggle): View {
        val row = LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), 0, dp(12), 0)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, dp(46))
        }
        row.addView(label(t.label, 15f, Color.WHITE, true), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        val sw = ToggleSwitch(ctx, live.getBoolean(t.key, t.def)) { live.edit().putBoolean(t.key, it).apply() }
        row.addView(sw)
        row.setOnClickListener { sw.toggle() }
        return row
    }

    private fun sliderRow(s: Slide): View {
        val col = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(14), dp(4), dp(14), dp(4))
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        val cur = live.getInt(s.key, s.def)
        val valueTv = label("$cur${s.unit}", 13f, 0xFF8E8E93.toInt())
        val top = LinearLayout(ctx)
        top.addView(label(s.label, 15f, Color.WHITE, true), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        top.addView(valueTv)
        col.addView(top)
        col.addView(FakeSlider(ctx, s.lo, s.hi, cur) { v ->
            valueTv.text = "$v${s.unit}"
            live.edit().putInt(s.key, v).apply()
            if (s.key == "opacity") applyOpacity()
        }, LinearLayout.LayoutParams(MATCH_PARENT, dp(30)))
        return col
    }

    private fun loadPage() {
        fun btn(s: String, onClick: () -> Unit) = label(s, 14f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply { setColor(0xFF3A3A3C.toInt()); cornerRadius = dp(10).toFloat() }
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, dp(38)).apply { setMargins(dp(14), dp(5), dp(14), dp(5)) }
        }
        content.addView(btn("Save config") { copy(live, saved); toast("Сохранено") })
        content.addView(btn("Load config") { copy(saved, live); applyOpacity(); toast("Загружено") })
        content.addView(btn("Reset") { live.edit().clear().apply(); applyOpacity(); toast("Сброшено") })
        content.addView(label("Демо-меню: ничего не меняет в играх.", 11f, 0xFF8E8E93.toInt()).apply {
            maxLines = 3; setPadding(dp(14), dp(8), dp(14), dp(8))
        })
    }

    private fun copy(from: SharedPreferences, to: SharedPreferences) {
        val e = to.edit().clear()
        for ((k, v) in from.all) when (v) { is Boolean -> e.putBoolean(k, v); is Int -> e.putInt(k, v) }
        e.apply()
    }

    private fun toast(s: String) = Toast.makeText(ctx, s, Toast.LENGTH_SHORT).show()

    private fun buildBubble() {
        val b = FrameLayout(ctx)
        b.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(0xFF1C1C1E.toInt()); setStroke(dp(1), 0x665B7CFF)
        }
        b.addView(EmblemView(ctx), FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER))
        bubbleView = b
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        b.setOnTouchListener(object : View.OnTouchListener {
            var sx = 0f; var sy = 0f; var lx = 0f; var ly = 0f; var moved = false
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> { sx = e.rawX; sy = e.rawY; lx = sx; ly = sy; moved = false }
                    MotionEvent.ACTION_MOVE -> {
                        if (!moved && (abs(e.rawX - sx) > slop || abs(e.rawY - sy) > slop)) moved = true
                        if (moved) { move(v, bubbleP, e.rawX - lx, e.rawY - ly); lx = e.rawX; ly = e.rawY }
                    }
                    MotionEvent.ACTION_UP -> if (!moved) v.post { showMenu() }
                }
                return true
            }
        })
    }
}
END_OF_FILE
mkdir -p app/src/main/java/com/example/fakemenu
cat > app/src/main/java/com/example/fakemenu/MainActivity.kt <<'END_OF_FILE'
package com.example.fakemenu

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var status: TextView
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun tv(s: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = s; textSize = size; setTextColor(color); gravity = Gravity.CENTER
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setPadding(0, dp(8), 0, dp(8))
    }

    private fun btn(s: String, bg: Int, onClick: () -> Unit) = TextView(this).apply {
        text = s; textSize = 16f; setTextColor(Color.WHITE); typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
        background = GradientDrawable().apply { setColor(bg); cornerRadius = dp(14).toFloat() }
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(-1, dp(52)).apply { topMargin = dp(12) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }
        col.addView(EmblemView(this), LinearLayout.LayoutParams(dp(72), dp(72)))
        col.addView(tv("Fake Menu", 26f, Color.WHITE, true))
        col.addView(tv("Демо-меню для видео и дизайна.\nНичего не делает в играх.", 14f, 0xFF8E8E93.toInt()))
        status = tv("", 14f, 0xFFBDBDC2.toInt())
        col.addView(status)
        col.addView(btn("Запустить меню", 0xFF34C759.toInt()) { start() })
        col.addView(btn("Остановить меню", 0xFF3A3A3C.toInt()) {
            stopService(Intent(this, OverlayService::class.java)); refresh()
        })
        setContentView(col)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    override fun onResume() { super.onResume(); refresh() }

    private fun refresh() {
        val perm = if (Settings.canDrawOverlays(this)) "разрешено" else "не разрешено"
        val run = if (OverlayService.running) "запущено" else "остановлено"
        status.text = "Поверх других окон: $perm\nМеню: $run"
    }

    private fun start() {
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Включи «Поверх других окон» для этого приложения", Toast.LENGTH_LONG).show()
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            return
        }
        startForegroundService(Intent(this, OverlayService::class.java))
        moveTaskToBack(true)
    }
}
END_OF_FILE
mkdir -p app/src/main/java/com/example/fakemenu
cat > app/src/main/java/com/example/fakemenu/OverlayService.kt <<'END_OF_FILE'
package com.example.fakemenu

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.provider.Settings

class OverlayService : Service() {
    private var menu: FloatingMenu? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() { super.onCreate(); running = true }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopSelf(); return START_NOT_STICKY }
        startForeground(1, notification())
        if (!Settings.canDrawOverlays(this)) { stopSelf(); return START_NOT_STICKY }
        if (menu == null) menu = FloatingMenu(this).also { it.start() }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        menu?.stop(); menu = null; running = false
        super.onDestroy()
    }

    private fun notification(): Notification {
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel("menu", "Menu", NotificationManager.IMPORTANCE_LOW))
        val fl = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val stop = PendingIntent.getService(this, 0, Intent(this, OverlayService::class.java).setAction(ACTION_STOP), fl)
        val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), fl)
        return Notification.Builder(this, "menu")
            .setSmallIcon(R.drawable.ic_star)
            .setContentTitle("Fake Menu")
            .setContentText("Меню запущено")
            .setContentIntent(open)
            .addAction(0, "Остановить", stop)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.example.fakemenu.STOP"
        @Volatile var running = false
    }
}
END_OF_FILE
mkdir -p app/src/main/java/com/example/fakemenu
cat > app/src/main/java/com/example/fakemenu/Widgets.kt <<'END_OF_FILE'
package com.example.fakemenu

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.LinearLayout
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

/** Простой логотип: четырёхлучевая звезда. */
class EmblemView(ctx: Context) : View(ctx) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    override fun onDraw(c: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val r = min(width, height) / 2f * 0.92f
        val k = r * 0.2f
        path.reset()
        path.moveTo(cx, cy - r)
        path.quadTo(cx + k, cy - k, cx + r, cy)
        path.quadTo(cx + k, cy + k, cx, cy + r)
        path.quadTo(cx - k, cy + k, cx - r, cy)
        path.quadTo(cx - k, cy - k, cx, cy - r)
        path.close()
        paint.shader = LinearGradient(cx - r, cy - r, cx + r, cy + r,
            0xFF8EF0FF.toInt(), 0xFF5B7CFF.toInt(), Shader.TileMode.CLAMP)
        c.drawPath(path, paint)
    }
}

/** Переключатель в стиле iOS (зелёный/серый). */
class ToggleSwitch(ctx: Context, initial: Boolean, private val onChange: (Boolean) -> Unit) : View(ctx) {
    private var isOn = initial
    private var progress = if (initial) 1f else 0f
    private val track = Paint(Paint.ANTI_ALIAS_FLAG)
    private val knob = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val rect = RectF()
    private val eval = ArgbEvaluator()

    init { setOnClickListener { toggle() } }

    fun toggle() {
        isOn = !isOn
        ValueAnimator.ofFloat(progress, if (isOn) 1f else 0f).apply {
            duration = 160
            addUpdateListener { progress = it.animatedValue as Float; invalidate() }
            start()
        }
        onChange(isOn)
    }

    override fun onMeasure(w: Int, h: Int) {
        val d = resources.displayMetrics.density
        setMeasuredDimension((50 * d).toInt(), (30 * d).toInt())
    }

    override fun onDraw(c: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        track.color = eval.evaluate(progress, 0xFFDADADA.toInt(), 0xFF34C759.toInt()) as Int
        rect.set(0f, 0f, w, h)
        c.drawRoundRect(rect, h / 2, h / 2, track)
        c.drawCircle(h / 2 + (w - h) * progress, h / 2, h / 2 - h * 0.08f, knob)
    }
}

/** Ползунок, который двигается пальцем. */
class FakeSlider(ctx: Context, private val lo: Int, private val hi: Int, initial: Int,
                 private val onChange: (Int) -> Unit) : View(ctx) {
    private var value = initial.coerceIn(lo, hi)
    private val d = resources.displayMetrics.density
    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND }

    override fun onDraw(c: Canvas) {
        val r = 8 * d
        val cy = height / 2f
        val x1 = width - r
        val kx = r + (x1 - r) * (value - lo) / (hi - lo).toFloat()
        p.strokeWidth = 4 * d
        p.color = 0xFF48484A.toInt()
        c.drawLine(r, cy, x1, cy, p)
        p.color = 0xFF34C759.toInt()
        c.drawLine(r, cy, kx, cy, p)
        p.color = Color.WHITE
        c.drawCircle(kx, cy, r, p)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                val r = 8 * d
                val frac = ((e.x - r) / (width - 2 * r)).coerceIn(0f, 1f)
                val v = (lo + frac * (hi - lo)).roundToInt()
                if (v != value) { value = v; onChange(v) }
                invalidate()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                parent?.requestDisallowInterceptTouchEvent(false)
        }
        return true
    }
}

/** Корень меню: тянешь за левую панель — окно двигается. */
class MenuRoot(ctx: Context, private val zone: Int, private val onDrag: (Float, Float) -> Unit) : LinearLayout(ctx) {
    private val slop = ViewConfiguration.get(ctx).scaledTouchSlop
    private var x0 = 0f
    private var y0 = 0f
    private var lx = 0f
    private var ly = 0f
    private var inZone = false
    private var dragging = false

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                x0 = e.rawX; y0 = e.rawY; lx = x0; ly = y0
                inZone = e.x < zone; dragging = false
            }
            MotionEvent.ACTION_MOVE ->
                if (inZone && !dragging && (abs(e.rawX - x0) > slop || abs(e.rawY - y0) > slop)) dragging = true
        }
        return dragging
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> return inZone
            MotionEvent.ACTION_MOVE -> if (dragging) {
                onDrag(e.rawX - lx, e.rawY - ly); lx = e.rawX; ly = e.rawY
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging = false
        }
        return true
    }
}
END_OF_FILE
mkdir -p app/src/main/res/drawable
cat > app/src/main/res/drawable/ic_star.xml <<'END_OF_FILE'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FF8EF0FF"
        android:pathData="M54,28 Q59,49 80,54 Q59,59 54,80 Q49,59 28,54 Q49,49 54,28 Z" />
</vector>
END_OF_FILE
mkdir -p app/src/main/res/mipmap-anydpi-v26
cat > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'END_OF_FILE'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_bg" />
    <foreground android:drawable="@drawable/ic_star" />
</adaptive-icon>
END_OF_FILE
mkdir -p app/src/main/res/values
cat > app/src/main/res/values/values.xml <<'END_OF_FILE'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Fake Menu</string>
    <color name="icon_bg">#1C1C1E</color>
    <color name="app_bg">#0F1117</color>
    <style name="AppTheme" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">@color/app_bg</item>
        <item name="android:statusBarColor">@color/app_bg</item>
        <item name="android:navigationBarColor">@color/app_bg</item>
    </style>
</resources>
END_OF_FILE
