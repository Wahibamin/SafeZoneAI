package com.safezone.ai.mobile

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.*

/** All images live in memory. Coordinates returned in the upright, unmirrored source space. */
object DetectionPipeline {
    private val buffers = java.util.WeakHashMap<Interpreter, Pair<ByteBuffer, ByteBuffer>>()
    fun camera(args: Map<String, Any?>): Bitmap {
        val w = (args["width"] as Number).toInt()
        val h = (args["height"] as Number).toInt()
        require(w in 1..4096 && h in 1..4096)
        val planes = args["planes"] as List<*>
        require(planes.size == 3 && args["format"] == "yuv420") { "Only YUV420 camera frames are supported" }
        val data = planes.map { (it as Map<*, *>)["bytes"] as ByteArray }
        val rows = planes.map { ((it as Map<*, *>)["rowStride"] as Number).toInt() }
        val strides = planes.map { ((it as Map<*, *>)["pixelStride"] as? Number)?.toInt() ?: 1 }
        for (i in 0..2) {
            val pw = if (i == 0) w else (w + 1) / 2
            val ph = if (i == 0) h else (h + 1) / 2
            require(rows[i] > 0 && strides[i] > 0 &&
                (ph - 1).toLong() * rows[i] + (pw - 1).toLong() * strides[i] < data[i].size)
        }
        val yData = data[0]; val uData = data[1]; val vData = data[2]
        val yRow = rows[0]; val uRow = rows[1]; val vRow = rows[2]
        val yStride = strides[0]; val uStride = strides[1]; val vStride = strides[2]
        val pixels = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            val yy = max(0, (yData[y * yRow + x * yStride].toInt() and 255) - 16) * 1.164f
            val u = (uData[y / 2 * uRow + x / 2 * uStride].toInt() and 255) - 128
            val v = (vData[y / 2 * vRow + x / 2 * vStride].toInt() and 255) - 128
            val r = (yy + 1.596f * v).roundToInt().coerceIn(0, 255)
            val g = (yy - .813f * v - .391f * u).roundToInt().coerceIn(0, 255)
            val b = (yy + 2.018f * u).roundToInt().coerceIn(0, 255)
            pixels[y * w + x] = Color.rgb(r, g, b)
        }
        val bitmap = Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
        val rotation = (args["rotation"] as Number).toInt()
        require(rotation in listOf(0, 90, 180, 270))
        if (rotation == 0) return bitmap
        val upright = Bitmap.createBitmap(bitmap, 0, 0, w, h, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        if (upright !== bitmap) bitmap.recycle()
        return upright
    }

    fun infer(interpreter: Interpreter, bitmap: Bitmap, contract: Map<*, *>, confidence: Float, iou: Float): Map<String, Any> {
        val started = System.nanoTime()
        val inputTensor = interpreter.getInputTensor(0)
        val shape = inputTensor.shape()
        require(shape.size == 4 && shape[0] == 1 && shape[3] == 3)
        val ih = shape[1]; val iw = shape[2]
        val scale = min(iw.toDouble() / bitmap.width, ih.toDouble() / bitmap.height)
        val rw = (bitmap.width * scale).roundToInt(); val rh = (bitmap.height * scale).roundToInt()
        val px = ((iw - rw) / 2.0 - .1).roundToInt(); val py = ((ih - rh) / 2.0 - .1).roundToInt()
        val letterbox = Bitmap.createBitmap(iw, ih, Bitmap.Config.ARGB_8888)
        Canvas(letterbox).apply {
            drawColor(Color.rgb(114, 114, 114))
            drawBitmap(bitmap, null, android.graphics.Rect(px, py, px + rw, py + rh), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        val rgb = IntArray(iw * ih)
        letterbox.getPixels(rgb, 0, iw, 0, 0, iw, ih); letterbox.recycle()
        val inp = contract["input"] as Map<*, *>
        val norm = inp["normalization"] as Map<*, *>
        val means = norm["mean"] as List<*>; val stds = norm["std"] as List<*>
        val mean = FloatArray(3) { (means[it % means.size] as Number).toFloat() }
        val std = FloatArray(3) { (stds[it % stds.size] as Number).toFloat() }
        val inputType = inputTensor.dataType().toString()
        val tensor = interpreter.getOutputTensor(0)
        val pair = buffers.getOrPut(interpreter) {
            ByteBuffer.allocateDirect(inputTensor.numBytes()).order(ByteOrder.nativeOrder()) to
                ByteBuffer.allocateDirect(tensor.numBytes()).order(ByteOrder.nativeOrder())
        }
        val input = pair.first.apply { clear() }
        val quant = inputTensor.quantizationParams()
        for (pixel in rgb) for (c in 0..2) {
            val value = (((pixel shr (16 - 8 * c)) and 255) - mean[c]) / std[c]
            when (inputType) {
                "FLOAT32" -> input.putFloat(value)
                "UINT8" -> input.put((value / quant.scale + quant.zeroPoint).roundToInt().coerceIn(0,255).toByte())
                "INT8" -> input.put((value / quant.scale + quant.zeroPoint).roundToInt().coerceIn(-128,127).toByte())
                else -> error("Unsupported input dtype")
            }
        }
        input.rewind()
        val output = pair.second.apply { clear() }
        val inferenceStart = System.nanoTime()
        interpreter.run(input, output)
        val inferenceMs = (System.nanoTime() - inferenceStart) / 1e6
        output.rewind()
        val values = FloatArray(tensor.numElements())
        val oq = tensor.quantizationParams()
        val outputType = tensor.dataType().toString()
        for (i in values.indices) {
            values[i] = when (outputType) {
                "FLOAT32" -> output.float
                "UINT8" -> ((output.get().toInt() and 255) - oq.zeroPoint) * oq.scale
                "INT8" -> (output.get().toInt() - oq.zeroPoint) * oq.scale
                else -> error("Unsupported output dtype")
            }
            require(values[i].isFinite()) { "Non-finite detection output" }
        }
        val labels = contract["labels"] as Map<*, *>
        val out = contract["output"] as Map<*, *>
        val adapter = out["adapter"] as? String ?: "yolo_raw"
        val os = tensor.shape()
        val candidates = mutableListOf<Box>()
        fun add(x1: Float, y1: Float, x2: Float, y2: Float, score: Float, cls: Int) {
            require(cls in 0 until labels.size && score in 0f..1.001f) { "Invalid class or confidence" }
            if (score < confidence) return
            val normalized = out["coordinates"] != "pixels"
            val mx = if (normalized) iw.toFloat() else 1f
            val my = if (normalized) ih.toFloat() else 1f
            val l = ((x1 * mx - px) / scale / bitmap.width).toFloat().coerceIn(0f,1f)
            val t = ((y1 * my - py) / scale / bitmap.height).toFloat().coerceIn(0f,1f)
            val r = ((x2 * mx - px) / scale / bitmap.width).toFloat().coerceIn(0f,1f)
            val b = ((y2 * my - py) / scale / bitmap.height).toFloat().coerceIn(0f,1f)
            if (r > l && b > t) candidates.add(Box(l,t,r,b,score,cls))
        }
        when (adapter) {
            "yolo_raw" -> {
                val features = labels.size + 4
                val bcn = out["layout"] == "BCN"
                require(os.size == 3 && (if (bcn) os[1] else os[2]) == features)
                val count = if (bcn) os[2] else os[1]
                fun get(n: Int, f: Int) = values[if (bcn) f * count + n else n * features + f]
                for (n in 0 until count) {
                    var cls = 0; var score = get(n, 4)
                    for (c in 1 until labels.size) if (get(n, c + 4) > score) { score = get(n,c+4); cls = c }
                    if (score < confidence) continue
                    val x = get(n,0); val y = get(n,1); val w = get(n,2); val h = get(n,3)
                    add(x-w/2, y-h/2, x+w/2, y+h/2, score, cls)
                }
            }
            "yolo26_end2end" -> {
                require(os.size == 3 && os[2] == 6)
                for (n in 0 until os[1]) {
                    val j = n * 6
                    if (values[j+4] < confidence) continue
                    require(abs(values[j+5] - values[j+5].roundToInt()) < .001f)
                    add(values[j],values[j+1],values[j+2],values[j+3],values[j+4],values[j+5].roundToInt())
                }
            }
            else -> error("Unsupported detection adapter: $adapter")
        }
        val kept = mutableListOf<Box>()
        for (box in candidates.sortedByDescending { it.score }.take(3000)) {
            if (adapter == "yolo26_end2end" || kept.none { it.cls == box.cls && overlap(it,box) > iou }) kept.add(box)
            if (kept.size >= 300) break
        }
        return mapOf("inference_ms" to inferenceMs, "total_ms" to (System.nanoTime()-started)/1e6,
            "width" to bitmap.width, "height" to bitmap.height,
            "detections" to kept.map { mapOf("class_id" to it.cls,"confidence" to it.score.toDouble(),
                "box" to listOf(it.l.toDouble(),it.t.toDouble(),it.r.toDouble(),it.b.toDouble())) })
    }
    private data class Box(val l: Float,val t: Float,val r: Float,val b: Float,val score: Float,val cls: Int)
    private fun overlap(a: Box,b: Box): Float {
        val inter = max(0f,min(a.r,b.r)-max(a.l,b.l))*max(0f,min(a.b,b.b)-max(a.t,b.t))
        return inter / ((a.r-a.l)*(a.b-a.t)+(b.r-b.l)*(b.b-b.t)-inter).coerceAtLeast(1e-9f)
    }
}
