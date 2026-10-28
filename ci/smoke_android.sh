#!/usr/bin/env bash
# Testa instalacao e inicializacao, NAO valida traducao nem microfone.
set -euo pipefail

APP_ID="com.example.linguaflow_ai"
APK="build/app/outputs/flutter-apk/app-debug.apk"
mkdir -p ci-artifacts

adb install -r "$APK"
adb logcat -c
adb shell am start -n "$APP_ID/.MainActivity" | tee ci-artifacts/launch.txt
sleep 12

adb shell dumpsys activity activities > ci-artifacts/activities.txt
adb logcat -d -v time > ci-artifacts/logcat.txt
adb logcat -b crash -d > ci-artifacts/crash.txt
adb exec-out screencap -p > ci-artifacts/tela-inicial.png || true
adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb pull /sdcard/window.xml ci-artifacts/window.xml >/dev/null 2>&1 || true

if ! adb shell pidof "$APP_ID" > ci-artifacts/pid.txt; then
  echo "ERRO: processo Android nao permaneceu aberto." >&2
  exit 1
fi
if grep -q "FATAL EXCEPTION" ci-artifacts/crash.txt; then
  echo "ERRO: houve excecao fatal nativa." >&2
  exit 1
fi
echo "OK: app instalado e aberto no emulador. Fala, modelos ML Kit e traducao ainda precisam de testes reais."
