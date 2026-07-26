package com.orailnoor.privatelm.opendroid.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.animation.ValueAnimator
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.orailnoor.privatelm.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import android.graphics.Bitmap
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class OpenDroidAccessibilityService : AccessibilityService() {

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var windowManager: WindowManager? = null
    private var floatingView: FloatingWidgetView? = null
    private var isButtonAdded = false
    private var isDeviceLocked = false
    private var showFloatingButton = false
    private val imeSubmitLabels = listOf("search", "go", "send", "done", "submit", "ok", "enter")

    /**
     * BroadcastReceiver that tracks device lock/unlock state.
     * Hides the floating button when the device is locked to prevent
     * unintended interaction from the lock screen.
     */
    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    isDeviceLocked = true
                    refreshFloatingButtonVisibility()
                }
                Intent.ACTION_USER_PRESENT -> {
                    isDeviceLocked = false
                    refreshFloatingButtonVisibility()
                }
                Intent.ACTION_SCREEN_ON -> {
                    val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    isDeviceLocked = keyguardManager?.isKeyguardLocked == true
                    refreshFloatingButtonVisibility()
                }
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this

        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        isDeviceLocked = keyguardManager?.isKeyguardLocked == true

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenStateReceiver, filter)

        // Always show floating button when service connects
        showFloatingButton = true
        refreshFloatingButtonVisibility()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Handle events if needed
    }

    override fun onInterrupt() {
        // Handle interruption
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(screenStateReceiver)
        } catch (e: Exception) {
            // Receiver may not have been registered
        }
        serviceScope.cancel()
        removeFloatingButton()
        instance = null
    }

    /**
     * Refreshes the floating button visibility based on both the show setting
     * and the device lock state.
     */
    private fun refreshFloatingButtonVisibility() {
        if (showFloatingButton && !isDeviceLocked) {
            addFloatingButton()
        } else {
            removeFloatingButton()
        }
    }

    private fun addFloatingButton() {
        if (isButtonAdded) return

        if (windowManager == null) {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }

        val view = FloatingWidgetView(this)
        view.updateState("idle")
        floatingView = view

        val params = WindowManager.LayoutParams(
            dpToPx(64),
            dpToPx(64),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 300
        }

        view.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isClick = false
            private val touchSlop = 10f
            private val longPressRunnable = Runnable {
                isClick = false
                triggerMicrophoneAction()
            }

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isClick = true
                        view.postDelayed(longPressRunnable, ViewConfiguration.getLongPressTimeout().toLong())
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (Math.abs(dx) > touchSlop || Math.abs(dy) > touchSlop) {
                            if (isClick) {
                                isClick = false
                                view.removeCallbacks(longPressRunnable)
                            }
                        }
                        params.x = initialX + dx.toInt()
                        params.y = initialY + dy.toInt()

                        val displayMetrics = resources.displayMetrics
                        val screenWidth = displayMetrics.widthPixels
                        val screenHeight = displayMetrics.heightPixels
                        params.x = params.x.coerceIn(0, screenWidth - params.width)
                        params.y = params.y.coerceIn(0, screenHeight - params.height)

                        try {
                            windowManager?.updateViewLayout(view, params)
                        } catch (e: Exception) {
                            // View might have been removed
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        view.removeCallbacks(longPressRunnable)
                        if (isClick) {
                            openMainActivityAction()
                        }
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        view.removeCallbacks(longPressRunnable)
                        return true
                    }
                }
                return false
            }
        })

        try {
            windowManager?.addView(view, params)
            isButtonAdded = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun removeFloatingButton() {
        if (!isButtonAdded) return
        try {
            floatingView?.let { windowManager?.removeView(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            floatingView = null
            isButtonAdded = false
        }
    }

    private fun triggerMicrophoneAction() {
        Log.d("OpenDroidAccessibilityService", "Microphone action triggered from floating button")
    }

    private fun openMainActivityAction() {
        val intent = Intent(this, com.orailnoor.privatelm.MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun dpToPx(dp: Float): Float {
        return dp * resources.displayMetrics.density
    }

    private fun dpToPx(dp: Int): Int {
        return Math.round(dp * resources.displayMetrics.density)
    }

    inner class FloatingWidgetView(context: Context) : android.widget.ImageView(context) {

        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var pulseRadius = 0f
        private var pulseAlpha = 255
        private var state: String = "idle"

        private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1500
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addUpdateListener { animation ->
                val value = animation.animatedValue as Float
                pulseRadius = value * dpToPx(8f)
                pulseAlpha = ((1f - value) * 150).toInt()
                invalidate()
            }
        }

        init {
            setImageResource(R.drawable.bot)
            scaleType = android.widget.ImageView.ScaleType.CENTER_INSIDE
            val padding = dpToPx(12)
            setPadding(padding, padding, padding, padding)
        }

        fun updateState(newState: String) {
            if (this.state == newState) return
            this.state = newState

            animator.cancel()
            when (newState) {
                "thinking" -> {
                    animator.duration = 600
                    animator.repeatMode = ValueAnimator.RESTART
                }
                "listening" -> {
                    animator.duration = 1000
                    animator.repeatMode = ValueAnimator.REVERSE
                }
                "speaking" -> {
                    animator.duration = 800
                    animator.repeatMode = ValueAnimator.REVERSE
                }
                else -> {
                    animator.duration = 2000
                    animator.repeatMode = ValueAnimator.REVERSE
                }
            }
            if (isAttachedToWindow) {
                animator.start()
            }
            invalidate()
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            animator.start()
        }

        override fun onDetachedFromWindow() {
            super.onDetachedFromWindow()
            animator.cancel()
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val radius = (width / 2f) - dpToPx(8f)

            // Draw cyber grey background circle
            paint.color = Color.parseColor("#121216")
            paint.style = Paint.Style.FILL
            canvas.drawCircle(cx, cy, radius, paint)

            // Draw center logo
            super.onDraw(canvas)

            // Draw glow border
            val color = when (state) {
                "idle" -> Color.parseColor("#00FF66")
                "listening" -> Color.parseColor("#FF3B30")
                "thinking" -> Color.parseColor("#00F0FF")
                "speaking" -> Color.parseColor("#007AFF")
                "executing" -> Color.parseColor("#00FFCC")
                else -> Color.parseColor("#00FF66")
            }

            paint.color = color
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = dpToPx(3f)

            canvas.drawCircle(cx, cy, radius, paint)

            glowPaint.color = color
            glowPaint.style = Paint.Style.STROKE

            if (state == "listening" || state == "thinking" || state == "speaking") {
                glowPaint.strokeWidth = dpToPx(1.5f)
                glowPaint.alpha = pulseAlpha
                canvas.drawCircle(cx, cy, radius + pulseRadius, glowPaint)
            }
        }
    }

    // --- Node Automation Methods ---

    fun findAndClick(text: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByText(text)
        for (node in nodes) {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                node.recycle()
                return true
            }
            var parent = node.parent
            while (parent != null) {
                if (parent.isClickable) {
                    parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    parent.recycle()
                    node.recycle()
                    return true
                }
                parent = parent.parent
            }
            node.recycle()
        }
        return false
    }

    fun findAndClickById(viewId: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByViewId(viewId)
        for (node in nodes) {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                node.recycle()
                return true
            }
            var parent = node.parent
            while (parent != null) {
                if (parent.isClickable) {
                    parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    parent.recycle()
                    node.recycle()
                    return true
                }
                parent = parent.parent
            }
            node.recycle()
        }
        return false
    }

    fun findAndType(searchText: String, content: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByText(searchText)
        for (node in nodes) {
            if (node.isEditable) {
                val arguments = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, content)
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                node.recycle()
                return true
            }
            node.recycle()
        }
        return false
    }

    fun findAndTypeById(viewId: String, content: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val nodes = rootNode.findAccessibilityNodeInfosByViewId(viewId)
        for (node in nodes) {
            if (node.isEditable) {
                val arguments = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, content)
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                node.recycle()
                return true
            }
            node.recycle()
        }
        return false
    }

    fun performImeEnter(): Boolean {
        val focusedNode = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        val success = if (focusedNode != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    focusedNode.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
                } else {
                    false
                }
            } finally {
                focusedNode.recycle()
            }
        } else {
            false
        }
        return success || performSubmitFallback()
    }

    private fun performSubmitFallback(): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val result = findSubmitNode(rootNode, imeSubmitLabels)
        rootNode.recycle()
        return result
    }

    private fun findSubmitNode(node: AccessibilityNodeInfo, labels: List<String>): Boolean {
        val text = node.text?.toString()?.lowercase()
        val contentDesc = node.contentDescription?.toString()?.lowercase()
        if (node.isClickable && (labels.contains(text) || labels.contains(contentDesc))) {
            return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (findSubmitNode(child, labels)) {
                child.recycle()
                return true
            }
            child.recycle()
        }
        return false
    }

    fun performScroll(forward: Boolean): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        val action = if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        val success = performScrollOnNode(rootNode, action)
        rootNode.recycle()
        return success
    }

    private fun performScrollOnNode(node: AccessibilityNodeInfo, action: Int): Boolean {
        if (node.isScrollable) {
            return node.performAction(action)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (performScrollOnNode(child, action)) {
                child.recycle()
                return true
            }
            child.recycle()
        }
        return false
    }

    fun clickCoordinates(x: Float, y: Float): Boolean {
        val path = Path().apply {
            moveTo(x, y)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 100)
        val gesture = GestureDescription.Builder().apply {
            addStroke(stroke)
        }.build()

        return dispatchGesture(gesture, null, null)
    }

    fun getScreenText(): String {
        val rootNode = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        extractTextFromNode(rootNode, sb)
        rootNode.recycle()
        return sb.toString()
    }

    private fun extractTextFromNode(node: AccessibilityNodeInfo, sb: StringBuilder) {
        val nodeText = node.text?.toString()
        val contentDesc = node.contentDescription?.toString()

        if (!nodeText.isNullOrEmpty()) {
            sb.append(nodeText).append("\n")
        } else if (!contentDesc.isNullOrEmpty()) {
            sb.append(contentDesc).append("\n")
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            extractTextFromNode(child, sb)
            child.recycle()
        }
    }

    suspend fun takeScreenshotAndEncode(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return null
        }
        return suspendCoroutine { continuation ->
            try {
                takeScreenshot(
                    android.view.Display.DEFAULT_DISPLAY,
                    mainExecutor,
                    object : TakeScreenshotCallback {
                        override fun onSuccess(screenshotResult: ScreenshotResult) {
                            try {
                                val hardwareBuffer = screenshotResult.hardwareBuffer
                                val colorSpace = screenshotResult.colorSpace
                                val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                                if (bitmap == null) {
                                    continuation.resume(null)
                                    return
                                }
                                val softwareBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                bitmap.recycle()
                                hardwareBuffer.close()

                                if (softwareBitmap == null) {
                                    continuation.resume(null)
                                    return
                                }

                                val outputStream = ByteArrayOutputStream()
                                softwareBitmap.compress(Bitmap.CompressFormat.JPEG, 70, outputStream)
                                val byteArray = outputStream.toByteArray()
                                val base64String = Base64.encodeToString(byteArray, Base64.NO_WRAP)
                                softwareBitmap.recycle()
                                continuation.resume(base64String)
                            } catch (e: Exception) {
                                e.printStackTrace()
                                continuation.resume(null)
                            }
                        }

                        override fun onFailure(errorCode: Int) {
                            continuation.resume(null)
                        }
                    }
                )
            } catch (e: Exception) {
                e.printStackTrace()
                continuation.resume(null)
            }
        }
    }

    companion object {
        @Volatile
        private var instance: OpenDroidAccessibilityService? = null

        fun getInstance(): OpenDroidAccessibilityService? = instance
    }
}
