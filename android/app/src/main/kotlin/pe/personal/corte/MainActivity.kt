package pe.personal.corte

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // JPEG con el codificador del sistema: RGBA crudo -> Bitmap -> JPEG, fuera del hilo principal.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "corte/jpeg").setMethodCallHandler { call, result ->
            val w = call.argument<Int>("w")!!
            val h = call.argument<Int>("h")!!
            val px = call.argument<ByteArray>("px")!!
            val q = call.argument<Int>("q")!!
            val main = Handler(Looper.getMainLooper())
            thread {
                try {
                    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bmp.copyPixelsFromBuffer(ByteBuffer.wrap(px)) // ARGB_8888 en memoria = bytes RGBA
                    val out = ByteArrayOutputStream(px.size / 8)
                    bmp.compress(Bitmap.CompressFormat.JPEG, q, out)
                    bmp.recycle()
                    val bytes = out.toByteArray()
                    main.post { result.success(bytes) }
                } catch (e: Throwable) {
                    main.post { result.error("jpeg", e.message, null) }
                }
            }
        }
    }
}
