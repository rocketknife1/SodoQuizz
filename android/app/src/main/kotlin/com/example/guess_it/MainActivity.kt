package com.example.guess_it

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Partea nativa a Modului Eco (vezi lib/core/eco_mode.dart).
 *
 * Un singur mesaj, `setBrightness`, cu un double intre 0 si 1 — sau -1 pentru
 * "inapoi la luminozitatea telefonului".
 *
 * DE CE E NEVOIE DE COD NATIV: din Dart nu se poate atinge backlight-ul.
 * Alternativa 100% Flutter ar fi fost un strat negru semi-transparent peste
 * joc, care doar PARE mai intunecat — panoul consuma exact la fel, ba chiar
 * putin mai mult (mai are un strat de compus la fiecare cadru). Aici se
 * schimba luminozitatea reala a panoului, adica singura varianta care chiar
 * scade consumul si incalzirea.
 *
 * `screenBrightness` se seteaza pe FEREASTRA jocului, nu pe sistem: nu cere
 * nicio permisiune (spre deosebire de WRITE_SETTINGS), nu schimba setarea
 * telefonului si dispare de la sine cand jocul trece in fundal sau se inchide
 * — deci un utilizator nu poate ramane niciodata cu ecranul stins din cauza
 * noastra.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "sodoquizz/eco"
        /** Valoarea Android pentru "foloseste setarea de sistem". */
        const val BRIGHTNESS_OVERRIDE_NONE = -1.0f
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBrightness" -> {
                    val requested = (call.arguments as? Number)?.toFloat() ?: BRIGHTNESS_OVERRIDE_NONE
                    // Sub 0 = revenire la setarea de sistem. Peste 0 se
                    // limiteaza la [0.05, 1.0]: un 0 curat ar stinge complet
                    // ecranul pe unele telefoane, iar jocul ar parea mort.
                    val brightness = if (requested < 0f) {
                        BRIGHTNESS_OVERRIDE_NONE
                    } else {
                        requested.coerceIn(0.05f, 1.0f)
                    }
                    runOnUiThread {
                        window.attributes = window.attributes.apply { screenBrightness = brightness }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
