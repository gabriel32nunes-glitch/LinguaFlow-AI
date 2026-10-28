package com.example.linguaflow_ai

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Reconhecimento LOCAL, sem OpenAI, Supabase, API externa, nem fallback para nuvem.
 * Android 14+ para solicitar troca automática de português/inglês.
 * O provedor do dispositivo pode NÃO implementar essa opção: verifique no aparelho.
 * Uma frase de cada vez. Retoma somente após Dart confirmar o fim do TTS.
 */
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val methodName = "app.linguaflow/offline_speech"
    private val eventName = "app.linguaflow/offline_speech/events"
    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var active = false
    private var listening = false
    private var pendingTranslation = false
    private var detectedLanguage: String? = null
    private var languageMode = "auto"
    private var otherErrors = 0

    private val retryRunnable = Runnable {
        if (active && !pendingTranslation && !listening) listenAgain()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodName)
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "checkSupport" -> {
                        val reason = checkSupport()
                        reply.success(mapOf(
                            "supported" to (reason == null),
                            "message" to (reason ?: "Pronto para áudio no próprio dispositivo")
                        ))
                    }
                    "start" -> {
                        val reason = checkSupport()
                        if (reason != null) {
                            reply.error("UNSUPPORTED", reason, null)
                        } else {
                            try {
                                languageMode = call.argument<String>("languageMode")
                                    ?.takeIf { it == "en" || it == "pt" } ?: "auto"
                                startSession()
                                reply.success(null)
                            } catch (e: Exception) {
                                stopSession()
                                reply.error("START_FAILED", e.message, null)
                            }
                        }
                    }
                    "resume" -> {
                        if (active) {
                            pendingTranslation = false
                            handler.removeCallbacks(retryRunnable)
                            handler.postDelayed(retryRunnable, 350L)
                        }
                        reply.success(null)
                    }
                    "stop" -> {
                        stopSession()
                        reply.success(null)
                    }
                    else -> reply.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }
                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
    }

    private fun checkSupport(): String? {
        if (Build.VERSION.SDK_INT < 34) {
            return "Para detectar e alternar português/inglês automaticamente nesta versão, " +
                "é necessário Android 14 ou superior. Nenhum serviço pago será usado."
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED) {
            // O Flutter pedirá a permissão ANTES de começar. 'checkSupport' é consultado
            // antes disso, portanto a ausência da permissão não bloqueia esta consulta.
        }
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
            return "Este aparelho não possui reconhecedor de fala local disponível. " +
                "Instale/ative o serviço de fala offline do Android e os modelos inglês/português."
        }
        return null
    }

    private fun startSession() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Permissão RECORD_AUDIO negada")
        }
        stopSession()
        recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        recognizer!!.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                otherErrors = 0
                send("status", "Ouvindo português e inglês…")
            }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {
                val phrase = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()?.trim()
                if (!phrase.isNullOrEmpty()) send("partial", text = phrase)
            }
            override fun onResults(results: Bundle?) {
                listening = false
                pendingTranslation = true
                val phrase = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()?.trim()
                if (phrase.isNullOrEmpty()) {
                    pendingTranslation = false
                    scheduleRetry()
                } else {
                    val actualLanguage = when (languageMode) {
                        "pt" -> "pt-BR"
                        "en" -> "en-US"
                        else -> detectedLanguage
                    }
                    send("result", text = phrase, language = actualLanguage)
                }
            }
            override fun onError(error: Int) {
                listening = false
                if (!active) return
                // Language model missing/unsupported: don't retry forever.
                if (error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                    error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE) {
                    active = false
                    send("fatal", "Modelos locais português/inglês indisponíveis. " +
                        "Instale os pacotes de reconhecimento offline nas opções de voz do Android.")
                    return
                }
                pendingTranslation = false
                // NO_MATCH and SPEECH_TIMEOUT often happen in silence; retry normally.
                if (error != SpeechRecognizer.ERROR_NO_MATCH &&
                    error != SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                    otherErrors++
                }
                if (otherErrors >= 5) {
                    active = false
                    send("fatal", "O reconhecedor local falhou repetidamente (código $error). " +
                        "Verifique os idiomas offline no aparelho e reinicie a sessão.")
                } else {
                    scheduleRetry(if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) 1100L else 550L)
                }
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onLanguageDetection(results: Bundle) {
                if (Build.VERSION.SDK_INT >= 34) {
                    detectedLanguage = results.getString(SpeechRecognizer.DETECTED_LANGUAGE)
                }
            }
        })
        active = true
        otherErrors = 0
        listenAgain()
    }

    private fun listenAgain() {
        if (!active || pendingTranslation || listening) return
        val service = recognizer ?: return
        detectedLanguage = null
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE,
                if (languageMode == "en") "en-US" else "pt-BR")
            if (Build.VERSION.SDK_INT >= 34 && languageMode == "auto") {
                putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,
                    arrayListOf("pt-BR", "en-US")
                )
                putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH,
                    RecognizerIntent.LANGUAGE_SWITCH_BALANCED)
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES,
                    arrayListOf("pt-BR", "en-US")
                )
            }
        }
        try {
            service.startListening(intent)
            listening = true
        } catch (e: Exception) {
            listening = false
            otherErrors++
            if (otherErrors >= 5) {
                active = false
                send("fatal", "Não foi possível ativar o microfone local: ${e.message}")
            } else {
                scheduleRetry(1100L)
            }
        }
    }

    private fun scheduleRetry(delay: Long = 550L) {
        handler.removeCallbacks(retryRunnable)
        if (active && !pendingTranslation) handler.postDelayed(retryRunnable, delay)
    }

    private fun send(type: String, message: String? = null, text: String? = null,
                     language: String? = null) {
        val payload = mutableMapOf<String, Any>("type" to type)
        if (message != null) payload["message"] = message
        if (text != null) payload["text"] = text
        if (language != null) payload["language"] = language
        handler.post { sink?.success(payload) }
    }

    private fun stopSession() {
        active = false
        listening = false
        pendingTranslation = false
        handler.removeCallbacks(retryRunnable)
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    override fun onPause() {
        super.onPause()
        // Sem serviço em primeiro plano nesta versão: nunca gravar escondido.
        if (active) {
            stopSession()
            send("fatal", "O aplicativo saiu de primeiro plano. Inicie novamente ao voltar.")
        }
    }

    override fun onDestroy() {
        stopSession()
        super.onDestroy()
    }
}
