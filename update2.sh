#!/bin/bash
set -e
cd FakeMenu
cat > app/src/main/java/com/example/fakemenu/FloatingMenu.kt <<'END_OF_FILE'
package com.example.fakemenu

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import kotlin.math.max
import kotlin.math.min

internal sealed class Item
internal class Head(val text: String) : Item()
internal class Toggle(val key: String, val label: String, val def: Boolean) : Item()
internal class Slide(val key: String, val label: String, val lo: Int, val hi: Int, val def: Int, val unit: String = "") : Item()
internal class Pick(val key: String, val label: String, val opts: List<String>) : Item()
internal class Btn(val label: String, val prefix: String) : Item()

// Формат строк: "## Раздел", "Название" (переключатель, "+" в конце = включён),
// "Название = вариант1/вариант2" (выбор), "Название ~ мин макс старт единицы" (ползунок), "> Кнопка"
private const val COMBAT = """
## Aimbot
Enable +
Silent Aim
Target Bones = Head/Chest/Stomach/Arms/Legs/Feet
Multipoints Scale ~ 0 100 50 %
Visible Check +
Auto Wall
Minimum Damage ~ 1 100 20 HP
Auto Fire
Minimum Hit Chance ~ 0 100 60 %
Force Shot
Per Weapon Settings = Pistols/SMG/Rifles/Snipers/Shotguns/Heavy
Back Camera
Remove Spread
Recoil Control
Backtrack
Backtrack Ticks ~ 1 12 6
Shot Buffer ~ 0 10 2
Interpolation ~ 0 100 30 ms
Interpolation Buffer ~ 0 20 4
Auto Scope
Auto Stop = Duck/Early/Between Shots/On Land
Custom FOV ~ 1 180 60 °
Draw FOV
Aim Smooth ~ 1 20 5
## Triggerbot
Enable
Trigger Mode = Bone Groups/Hitboxes
Target Bones = Head/Chest/Stomach/Arms/Legs/Feet
Multipoints Scale ~ 0 100 50 %
Trigger Delay ~ 0 500 50 ms
Spread Prediction
Spread Circle
Minimum Hit Chance ~ 0 100 60 %
Force Shot
Crosshair Gate
Visible Check +
Minimum Damage ~ 1 100 20 HP
Auto Wall
## Anti-Aim
Enable
Yaw Mode = Backward/Offset/Jitter/Spin/Random
Random Pitch
Custom Pitch ~ -89 89 0 °
Yaw Offset ~ -180 180 0 °
Jitter Range ~ 0 180 30 °
Spin Step ~ 1 60 10 °
"""

private const val VISUALS = """
## ESP
Enable +
ESP Preview
ESP Scale ~ 50 200 100 %
Text Scale ~ 50 200 100 %
Fade Animation = Fade In/Fade Out
Visibility Conditions
Player Boxes = Regular/Corner
Box Gradient
Snap Lines = Top/Center/Bottom
Line Gradient & Glow
Nicknames = Custom Fonts/Background/Gradient/Glow/Text Styles
Nickname Case = Original/Upper/Lower
Nickname Position = Top/Right/Bottom/Left
Profile Pictures
Skeleton
Hitboxes = Wireframe/Flat/Glow Outline
Weapon ESP = Text/Icon/Grenades
Weapon Gradient & Glow
Off-Screen Indicators
Health Bar = Left/Right/Top/Bottom
Health Bar Gradient & Glow
Armor = Bar/Flag
Ammo Bar = Left/Right/Top/Bottom
Ammo Bar Gradient & Glow
Left Flags = Money/Distance
Right Flags = Bomb/Scoped/Reload/Blind
Custom Fonts & Text Styles
## Chams
Enemy Chams
Teammates Chams
Backtrack Chams (All Records)
Hit Chams
Weapon Chams
Gloves Chams
Arms Chams
Local Chams
Behind Walls
Chams Materials = Solid/Shaded/Glow/Iridescent/Water Flow/Glossy Glow/Wireframe/Glass/Blur/Crystal
Visible / Invisible Colors = Cyan/Pink/Green/White/Orange
Material Overlay
Metalness & Roughness ~ 0 100 50
Glow & Fresnel ~ 0 100 40
Iridescent Animation
Water Flow Animation
Wireframe Glow & Pulse
Glass Distortion & Frosted Effect
Blur Effect
Crystal Reflection & Animation
## World
Wireframe Walls = Local Player/Enemy
Nightmode
Delete Textures
Fullbright
Brightness Control ~ 0 100 50 %
Sky Changer = Original/Dark Storm/Clouded Sun/Unearthly Red/Under The Sea/Mega Sun
Sky Exposure & Rotation ~ 0 360 0 °
Custom Fog
Custom FOV ~ 60 140 90 °
Scope FOV ~ 10 90 40 °
Camera & Scope Speed Multiplier ~ 1 10 1 x
Show Hands In Scope
Aspect Ratio = Horizontal/Vertical
Viewmodel FOV ~ 40 120 68 °
Viewmodel Position X ~ -20 20 0
Viewmodel Position Y ~ -20 20 0
Viewmodel Position Z ~ -20 20 0
Viewmodel Angle Pitch ~ -180 180 0 °
Viewmodel Angle Yaw ~ -180 180 0 °
Viewmodel Angle Roll ~ -180 180 0 °
Left Hand
## Post-Processing
Enable
Viewmodel Effects
Bloom
Bloom Intensity & Threshold ~ 0 100 30
Bloom Diffusion ~ 0 100 50
Anamorphic Ratio ~ -100 100 0
Bloom Dirt Effect
Chromatic Aberration
Film Grain
Colored Grain
Motion Blur
Color Grading
Temperature & Tint ~ -100 100 0
Color Filter
Hue Shift ~ -180 180 0 °
Saturation ~ -100 100 0
Brightness ~ -100 100 0
Exposure & Contrast ~ -100 100 0
Vignette
Vignette Color & Opacity ~ 0 100 40 %
Depth of Field
Focus Distance ~ 1 100 10 m
Aperture ~ 1 32 5
Focal Length ~ 1 300 50 mm
Kernel Size = Small/Medium/Large/Very Large
> Reset to Defaults
## Effects
Custom Scope = Lines/Gradient
Scope Glow
Force Crosshair
Hit Effects = Lightning/Explosion/Blood Spatter/Soul Essence/Dissolve
Hit Effect Speed ~ 1 10 5
Custom Hit Effect Colors
Bullet Tracers = Solid/Gradient
Tracer Gradient = Forward/Backward/Center
Tracer Duration ~ 1 10 3 s
Tracer Width ~ 1 10 2
Show Tracers Behind Walls
Tracer Glow
Hit Marker = 2D/3D
Server Confirmed Hits
Damage Marker
Custom Marker Duration & Size ~ 1 10 3
"""

private const val MISC = """
## Misc
No Spread
No Recoil
Air Strafe
Third Person
Third Person Distance & Height ~ 10 300 100
First Person With Knife
Menu Opacity ~ 30 100 100 %
## Chat
Chat Spam
Spam Interval ~ 1 60 5 s
Team Only
Shuffle Messages
"""

private const val SKINS = """
## Skins
Skin Changer
Knife Changer
Knife = Karambit/Butterfly/M9 Bayonet/Kunai
Skin = Dragon/Fade/Neon/Gold
Sticker = None/Gold/Holo
"""

/** Плавающее меню. Это только интерфейс: ни в какие игры оно не вмешивается. */
class FloatingMenu(private val ctx: Context) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val dens = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * dens).toInt()
    private val live = ctx.getSharedPreferences("menu_live", Context.MODE_PRIVATE)
    private val saved = ctx.getSharedPreferences("menu_saved", Context.MODE_PRIVATE)

    private val tabs = listOf("Combat", "Visuals", "Misc", "Skins", "Load")
    private val pages: List<List<Item>> = listOf(parse(0, COMBAT), parse(1, VISUALS), parse(2, MISC), parse(3, SKINS))
    private var curTab = 0

    private val menuP = params(min(dp(380), ctx.resources.displayMetrics.widthPixels - dp(16)),
        min(dp(280), ctx.resources.displayMetrics.heightPixels - dp(16))).apply { x = dp(32); y = dp(24) }
    private val trigP = params(dp(80), dp(80)).apply { gravity = Gravity.CENTER }

    private lateinit var menuView: MenuRoot
    private lateinit var trigView: View
    private lateinit var titleTv: TextView
    private lateinit var content: LinearLayout
    private val tabViews = ArrayList<TextView>()
    private var menuAdded = false
    private var trigAdded = false

    private fun parse(tab: Int, src: String): List<Item> {
        var sec = 0
        val out = ArrayList<Item>()
        for (raw in src.lines()) {
            var l = raw.trim()
            if (l.isEmpty()) continue
            val p = "$tab.$sec."
            when {
                l.startsWith("## ") -> { sec++; out.add(Head(l.substring(3))) }
                l.startsWith("> ") -> out.add(Btn(l.substring(2), p))
                " = " in l -> {
                    val (n, o) = l.split(" = ")
                    out.add(Pick(p + n, n, o.split("/")))
                }
                " ~ " in l -> {
                    val (n, r) = l.split(" ~ ")
                    val t = r.split(" ")
                    out.add(Slide(if (n == "Menu Opacity") "opacity" else p + n, n,
                        t[0].toInt(), t[1].toInt(), t[2].toInt(), t.getOrElse(3) { "" }))
                }
                else -> {
                    val on = l.endsWith(" +")
                    if (on) l = l.dropLast(2)
                    out.add(Toggle(p + l, l, on))
                }
            }
        }
        return out
    }

    private fun params(w: Int, h: Int) = WindowManager.LayoutParams(
        w, h, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.START }

    fun start() { buildMenu(); buildTrigger(); showMenu() }

    fun stop() {
        if (menuAdded) wm.removeView(menuView)
        if (trigAdded) wm.removeView(trigView)
        menuAdded = false; trigAdded = false
    }

    private fun showMenu() {
        if (trigAdded) { wm.removeView(trigView); trigAdded = false }
        if (!menuAdded) { wm.addView(menuView, menuP); menuAdded = true }
    }

    /** Закрыть меню: остаётся невидимая зона в центре экрана, тап по ней открывает меню. */
    private fun hideMenu() {
        if (menuAdded) { wm.removeView(menuView); menuAdded = false }
        if (!trigAdded) {
            wm.addView(trigView, trigP); trigAdded = true
            toast("Нажми по центру экрана, чтобы открыть меню")
        }
    }

    private fun buildTrigger() {
        trigView = View(ctx).apply {
            setBackgroundColor(0x01000000)
            setOnClickListener { post { showMenu() } }
        }
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

    private fun rowLabel(s: String) = label(s, 14f, Color.WHITE, true).apply {
        maxLines = 2; ellipsize = TextUtils.TruncateAt.END
    }

    private fun buildMenu() {
        val root = MenuRoot(ctx, dp(96)) { dx, dy -> move(menuView, menuP, dx, dy) }
        menuView = root
        root.orientation = LinearLayout.HORIZONTAL
        root.background = GradientDrawable().apply { setColor(0xFF1E1E20.toInt()); cornerRadius = dp(18).toFloat() }
        root.clipToOutline = true

        val side = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(0xFF19191A.toInt()) }
        root.addView(side, LinearLayout.LayoutParams(dp(96), MATCH_PARENT))
        val logo = EmblemView(ctx).apply { setOnClickListener { menuView.post { hideMenu() } } }
        side.addView(logo, LinearLayout.LayoutParams(dp(30), dp(30)).apply {
            gravity = Gravity.CENTER_HORIZONTAL; topMargin = dp(10); bottomMargin = dp(8)
        })
        tabs.forEachIndexed { i, name ->
            val tv = label(name, 14f, Color.WHITE, true).apply {
                gravity = Gravity.CENTER; setOnClickListener { selectTab(i) }
            }
            tabViews.add(tv)
            side.addView(tv, LinearLayout.LayoutParams(MATCH_PARENT, dp(38)))
        }

        val right = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        root.addView(right, LinearLayout.LayoutParams(0, MATCH_PARENT, 1f))
        val head = LinearLayout(ctx).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), 0, dp(4), 0) }
        titleTv = label("", 13f, 0xFF8E8E93.toInt(), true)
        head.addView(titleTv, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        val closeBtn = label("×", 24f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER; setOnClickListener { menuView.post { hideMenu() } }
        }
        head.addView(closeBtn, LinearLayout.LayoutParams(dp(44), dp(36)))
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
        curTab = i
        tabViews.forEachIndexed { j, tv ->
            tv.setBackgroundColor(if (j == i) 0xFF2C2C2E.toInt() else Color.TRANSPARENT)
            tv.setTextColor(if (j == i) Color.WHITE else 0xFFBDBDC2.toInt())
        }
        titleTv.text = tabs[i]
        content.removeAllViews()
        if (i == tabs.lastIndex) loadPage()
        else pages[i].forEach {
            content.addView(when (it) {
                is Head -> headRow(it)
                is Toggle -> toggleRow(it)
                is Slide -> sliderRow(it)
                is Pick -> pickRow(it)
                is Btn -> button(it.label) { resetSection(it.prefix) }
            })
        }
    }

    private fun resetSection(prefix: String) {
        val e = live.edit()
        for (k in live.all.keys) if (k.startsWith(prefix)) e.remove(k)
        e.apply()
        selectTab(curTab)
        toast("Сброшено")
    }

    private fun headRow(h: Head) = label(h.text.uppercase(), 11f, 0xFF7FA6FF.toInt(), true).apply {
        letterSpacing = 0.08f
        setPadding(dp(14), dp(12), dp(14), dp(4))
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    }

    private fun rowBase() = LinearLayout(ctx).apply {
        gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(46); setPadding(dp(14), dp(3), dp(12), dp(3))
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    }

    private fun toggleRow(t: Toggle): View {
        val row = rowBase()
        row.addView(rowLabel(t.label), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        val sw = ToggleSwitch(ctx, live.getBoolean(t.key, t.def)) { live.edit().putBoolean(t.key, it).apply() }
        row.addView(sw)
        row.setOnClickListener { sw.toggle() }
        return row
    }

    private fun pickRow(p: Pick): View {
        val row = rowBase()
        row.addView(rowLabel(p.label), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        var idx = live.getInt(p.key, 0).coerceIn(0, p.opts.lastIndex)
        val pill = label(p.opts[idx], 13f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER; setPadding(dp(12), dp(5), dp(12), dp(5))
            background = GradientDrawable().apply { setColor(0xFF3A3A3C.toInt()); cornerRadius = dp(10).toFloat() }
        }
        val click = View.OnClickListener {
            idx = (idx + 1) % p.opts.size
            pill.text = p.opts[idx]
            live.edit().putInt(p.key, idx).apply()
        }
        row.setOnClickListener(click)
        pill.setOnClickListener(click)
        row.addView(pill)
        return row
    }

    private fun sliderRow(s: Slide): View {
        val col = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(14), dp(4), dp(14), dp(4))
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        fun fmt(v: Int) = if (s.unit.isEmpty() || s.unit == "%" || s.unit == "°") "$v${s.unit}" else "$v ${s.unit}"
        val cur = live.getInt(s.key, s.def)
        val valueTv = label(fmt(cur), 13f, 0xFF8E8E93.toInt())
        val top = LinearLayout(ctx)
        top.addView(rowLabel(s.label), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        top.addView(valueTv)
        col.addView(top)
        col.addView(FakeSlider(ctx, s.lo, s.hi, cur) { v ->
            valueTv.text = fmt(v)
            live.edit().putInt(s.key, v).apply()
            if (s.key == "opacity") applyOpacity()
        }, LinearLayout.LayoutParams(MATCH_PARENT, dp(30)))
        return col
    }

    private fun button(s: String, onClick: () -> Unit) = label(s, 14f, Color.WHITE, true).apply {
        gravity = Gravity.CENTER
        background = GradientDrawable().apply { setColor(0xFF3A3A3C.toInt()); cornerRadius = dp(10).toFloat() }
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, dp(38)).apply { setMargins(dp(14), dp(5), dp(14), dp(5)) }
    }

    private fun loadPage() {
        content.addView(button("Save config") { copy(live, saved); toast("Сохранено") })
        content.addView(button("Load config") { copy(saved, live); applyOpacity(); toast("Загружено") })
        content.addView(button("Reset all") { live.edit().clear().apply(); applyOpacity(); toast("Сброшено") })
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
}
END_OF_FILE
