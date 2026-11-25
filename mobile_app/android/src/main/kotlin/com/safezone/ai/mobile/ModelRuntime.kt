package com.safezone.ai.mobile

import android.content.Context
import android.os.Build
import org.json.JSONObject
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.Tensor
import org.tensorflow.lite.support.metadata.MetadataExtractor
import org.tensorflow.lite.support.metadata.schema.NormalizationOptions
import org.tensorflow.lite.support.metadata.schema.ProcessUnitOptions
import org.tensorflow.lite.support.metadata.schema.ImageProperties
import org.tensorflow.lite.support.metadata.schema.ContentProperties
import org.tensorflow.lite.support.metadata.schema.ColorSpaceType
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.io.RandomAccessFile
import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipFile
import android.media.MediaMetadataRetriever
import android.os.Debug
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.gpu.GpuDelegate
import android.graphics.BitmapFactory

/** Single worker owns all interpreters. Candidate inference never destroys the active interpreter. */
class ModelRuntime(private val context: Context) {
    private var active: Interpreter? = null
    private val gpuDelegates = java.util.IdentityHashMap<Interpreter, GpuDelegate>()
    private var video: MediaMetadataRetriever? = null
    private var videoModels = listOf<Pair<Interpreter, Map<*, *>>>()
    private var memoryMb = 0.0
    private var memorySampleNs = 0L

    private fun modelFile(path: String): File {
        val file = File(path).canonicalFile
        require(file.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator)) {
            "Model must be in application-private storage"
        }
        require(file.isFile && file.length() in 32..536870912L) { "Invalid model file size" }
        RandomAccessFile(file, "r").use {
            it.seek(4)
            val magic = ByteArray(4)
            it.readFully(magic)
            require(String(magic, Charsets.US_ASCII) == "TFL3") { "Invalid TFL3 header" }
        }
        return file
    }

    private fun closeInterpreter(interpreter: Interpreter) {
        interpreter.close(); gpuDelegates.remove(interpreter)?.close()
    }
    private fun open(file: File, accelerator: String = "cpu"): Interpreter {
        require(accelerator in listOf("cpu", "gpu"))
        val options = Interpreter.Options().setNumThreads(2)
        val delegate = if (accelerator == "gpu") {
            CompatibilityList().use { compatibility ->
                require(compatibility.isDelegateSupportedOnThisDevice) { "GPU delegate is not supported on this device" }
                GpuDelegate(compatibility.bestOptionsForThisDevice).also { options.addDelegate(it) }
            }
        } else null
        val interpreter = try { Interpreter(file, options) } catch (e: Exception) { delegate?.close(); throw e }
        if (delegate != null) gpuDelegates[interpreter] = delegate
        try { interpreter.allocateTensors(); return interpreter }
        catch (e: Exception) { closeInterpreter(interpreter); throw e }
    }

    private fun boundedRead(input: InputStream): ByteArray = input.use {
        val output = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val count = it.read(chunk)
            if (count < 0) break
            require(output.size() + count <= 1048576) { "Metadata exceeds size limit" }
            output.write(chunk, 0, count)
        }
        output.toByteArray()
    }

    private fun tensor(t: Tensor): Map<String, Any> = mapOf(
        "name" to t.name(), "shape" to t.shape().toList(),
        "shape_signature" to t.shapeSignature().toList(),
        "dtype" to t.dataType().toString().lowercase(), "bytes" to t.numBytes(),
        "scale" to t.quantizationParams().scale, "zero_point" to t.quantizationParams().zeroPoint
    )

    private fun jsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
        is org.json.JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }

    private fun embedded(file: File): Map<String, Any?> {
        val info = mutableMapOf<String, Any?>()
        // Recent Ultralytics exports append metadata.json to the actual FlatBuffer.
        val zip = try { ZipFile(file) } catch (_: java.util.zip.ZipException) { null }
        zip?.use { z ->
            z.getEntry("metadata.json")?.let { entry ->
                val bytes = boundedRead(z.getInputStream(entry))
                require(bytes.size <= 1048576) { "Embedded metadata too large" }
                info["ultralytics"] = jsonValue(JSONObject(String(bytes, Charsets.UTF_8)))
            }
            z.getEntry("safezone.json")?.let { entry ->
                info["safezone"] = jsonValue(JSONObject(String(boundedRead(z.getInputStream(entry)), Charsets.UTF_8)))
            }
        }
        RandomAccessFile(file, "r").use { raf ->
            val buffer = raf.channel.map(FileChannel.MapMode.READ_ONLY, 0, raf.length())
            val extractor = MetadataExtractor(buffer)
            if (extractor.hasMetadata()) {
                val meta = extractor.modelMetadata
                info["name"] = meta.name()
                info["description"] = meta.description()
                val graph = meta.subgraphMetadata(0)
                val input = graph?.inputTensorMetadata(0)
                if (input != null) {
                    val content = input.content()
                    if (content?.contentPropertiesType() == ContentProperties.ImageProperties) {
                        val image = content.contentProperties(ImageProperties()) as ImageProperties
                        info["color"] = when (image.colorSpace()) {
                            ColorSpaceType.RGB -> "RGB"
                            ColorSpaceType.GRAYSCALE -> "GRAYSCALE"
                            else -> "UNKNOWN"
                        }
                    }
                    for (i in 0 until input.processUnitsLength()) {
                        val unit = input.processUnits(i)!!
                        if (unit.optionsType() == ProcessUnitOptions.NormalizationOptions) {
                            val norm = unit.options(NormalizationOptions()) as NormalizationOptions
                            info["normalization"] = mapOf(
                                "mean" to (0 until norm.meanLength()).map { norm.mean(it) },
                                "std" to (0 until norm.stdLength()).map { norm.std(it) }
                            )
                        }
                    }
                }
                val labels = mutableListOf<String>()
                if (graph != null) {
                    for (i in 0 until graph.outputTensorMetadataLength()) {
                        val output = graph.outputTensorMetadata(i)!!
                        for (j in 0 until output.associatedFilesLength()) {
                            val associated = output.associatedFiles(j)!!
                            // TENSOR_AXIS_LABELS = 2; never treat arbitrary associated data as labels.
                            if (associated.type().toInt() == 2 && labels.isEmpty()) {
                                val name = associated.name() ?: continue
                                val bytes = boundedRead(extractor.getAssociatedFile(name))
                                require(bytes.size <= 1048576) { "Label metadata too large" }
                                labels.addAll(String(bytes, Charsets.UTF_8).lineSequence()
                                    .map { it.trim() }.filter { it.isNotEmpty() }.toList())
                            }
                        }
                    }
                }
                if (labels.isNotEmpty()) info["labels"] = labels
            }
        }
        return info
    }

    fun inspect(path: String): Map<String, Any?> {
        val file = modelFile(path)
        open(file).use { interpreter ->
            return mapOf(
                "inputs" to (0 until interpreter.inputTensorCount).map { tensor(interpreter.getInputTensor(it)) },
                "outputs" to (0 until interpreter.outputTensorCount).map { tensor(interpreter.getOutputTensor(it)) },
                "embedded" to embedded(file), "size_bytes" to file.length()
            )
        }
    }

    fun smoke(path: String, activate: Boolean, accelerator: String = "cpu"): Map<String, Any> {
        val candidate = open(modelFile(path), accelerator)
        try {
            require(candidate.inputTensorCount == 1 && candidate.outputTensorCount == 1) {
                "Only single-input/single-output detection exports are supported"
            }
            val t = candidate.getInputTensor(0)
            require(t.numBytes() in 1..67108864) { "Input tensor exceeds supported memory limit" }
            val input = ByteBuffer.allocateDirect(t.numBytes()).order(ByteOrder.nativeOrder())
            // A normalized black RGB input; no camera access and no image files.
            when (t.dataType().toString()) {
                "FLOAT32" -> repeat(t.numElements()) { input.putFloat(0f) }
                "UINT8", "INT8" -> repeat(t.numElements()) { input.put(t.quantizationParams().zeroPoint.toByte()) }
                else -> error("Unsupported input dtype")
            }
            input.rewind()
            val out = candidate.getOutputTensor(0)
            require(out.numBytes() in 1..134217728) { "Output tensor exceeds supported memory limit" }
            val output = ByteBuffer.allocateDirect(out.numBytes()).order(ByteOrder.nativeOrder())
            val started = System.nanoTime()
            candidate.run(input, output)
            val elapsedMs = (System.nanoTime() - started) / 1e6
            output.rewind()
            if (out.dataType().toString() == "FLOAT32") {
                repeat(out.numElements()) { require(output.float.isFinite()) { "Non-finite inference output" } }
            }
            val evidence = mapOf(
                "inference_ms" to elapsedMs,
                "device" to "${Build.MANUFACTURER} ${Build.MODEL} / Android ${Build.VERSION.SDK_INT}",
                "runtime" to "LiteRT/1.4.2 ${accelerator.uppercase()} Interpreter", "accelerator" to accelerator, "output_bytes" to out.numBytes(),
                "input" to "in-memory normalized black RGB tensor", "passed" to true
            )
            if (activate) {
                val previous = active
                active = candidate
                previous?.let { closeInterpreter(it) }
            }
            return evidence
        } finally {
            if (active !== candidate) closeInterpreter(candidate)
        }
    }

    fun infer(args: Map<String, Any?>): Map<String, Any> {
        val interpreter = requireNotNull(active) { "No active model" }
        val bitmap = DetectionPipeline.camera(args)
        return try {
            if (System.nanoTime() - memorySampleNs > 1_000_000_000L) {
                memoryMb = Debug.getPss() / 1024.0; memorySampleNs = System.nanoTime()
            }
            DetectionPipeline.infer(interpreter, bitmap, args["contract"] as Map<*, *>,
                (args["confidence"] as Number).toFloat(), (args["iou"] as Number).toFloat()) +
                mapOf("memory_mb" to memoryMb)
        } finally { bitmap.recycle() }
    }

    fun inferImage(args: Map<String, Any?>): Map<String, Any> {
        val bytes = args["bytes"] as ByteArray
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        return try {
            DetectionPipeline.infer(requireNotNull(active), bitmap, args["contract"] as Map<*, *>,
                (args["confidence"] as Number).toFloat(), (args["iou"] as Number).toFloat())
        } finally { bitmap.recycle() }
    }

    fun beginVideo(args: Map<String, Any?>): Map<String, Any> {
        endVideo()
        val candidates = mutableListOf<Pair<Interpreter, Map<*, *>>>()
        val retriever = MediaMetadataRetriever()
        try {
            val file = File(args["videoPath"] as String).canonicalFile
            require(file.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator)) { "Select a video with the system picker" }
            retriever.setDataSource(file.path)
            for (raw in args["models"] as List<*>) {
                val config = raw as Map<*, *>
                candidates.add(open(modelFile(config["path"] as String), args["accelerator"] as? String ?: "cpu") to config)
            }
            require(candidates.size in 1..2)
            videoModels = candidates
            video = retriever
            return mapOf("duration_ms" to (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L))
        } catch (e: Exception) {
            candidates.forEach { closeInterpreter(it.first) }; retriever.release(); throw e
        }
    }

    fun videoFrame(timestampMs: Long): List<Map<String, Any>> {
        val bitmap = requireNotNull(video).getFrameAtTime(timestampMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
            ?: error("Unable to decode video frame at $timestampMs ms")
        return try {
            // Both models receive the very same decoded bitmap, alternating order to reduce order bias.
            val results = mutableMapOf<Int, Map<String, Any>>()
            val order = videoModels.indices.toList().let { if (timestampMs % 2000L == 0L) it else it.reversed() }
            for (i in order) {
                val (interpreter, config) = videoModels[i]
                results[i] = DetectionPipeline.infer(interpreter, bitmap, config["contract"] as Map<*, *>,
                    (config["confidence"] as Number).toFloat(), (config["iou"] as Number).toFloat()) +
                    mapOf("model_id" to (config["id"] as String), "memory_mb" to Debug.getPss()/1024.0)
            }
            videoModels.indices.map { results.getValue(it) }
        } finally { bitmap.recycle() }
    }

    fun endVideo() {
        videoModels.forEach { closeInterpreter(it.first) }; videoModels = emptyList()
        video?.release(); video = null
    }
    fun close() { endVideo(); active?.let { closeInterpreter(it) }; active = null }
}
