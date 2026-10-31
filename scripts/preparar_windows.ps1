# Zeluvori AI - preparacao local para Windows + Galaxy A14.
# Execute na pasta raiz do repositorio no PowerShell do VS Code.
$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))

function Require-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Programa '$name' nao encontrado. Instale/configure e reabra o VS Code."
    }
}
Require-Command "flutter"
Write-Host "Verificando ambiente Flutter..." -ForegroundColor Cyan
flutter --version
if ($LASTEXITCODE -ne 0) { throw "Flutter nao esta funcionando." }

Write-Host "Criando estrutura Android para desenvolvimento..." -ForegroundColor Cyan
flutter create . --platforms android
if ($LASTEXITCODE -ne 0) { throw "flutter create falhou." }

Write-Host "Configurando o Galaxy A14 e o identificador separado .dev..." -ForegroundColor Cyan
if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 setup_android.py
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python setup_android.py
} else {
    throw "Python 3 nao encontrado. Instale Python 3 e reabra o VS Code."
}
if ($LASTEXITCODE -ne 0) { throw "setup_android.py falhou." }

# Flutter cria um teste demonstrativo para MyApp; nosso aplicativo usa LinguaFlowApp.
$generatedTest = Join-Path "test" "widget_test.dart"
if (Test-Path $generatedTest) {
    $contents = Get-Content $generatedTest -Raw
    if ($contents -match "MyApp") {
        Remove-Item $generatedTest
    }
}

$modelFolder = Join-Path "assets" "models"
New-Item -ItemType Directory -Force -Path $modelFolder | Out-Null
$modelPath = Join-Path $modelFolder "ggml-tiny-q5_1.bin"
$expected = "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7"
$download = $true
if (Test-Path $modelPath) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $modelPath).Hash.ToLowerInvariant()
    if ($actual -eq $expected) {
        Write-Host "Modelo Whisper ja verificado. Nao precisa baixar novamente." -ForegroundColor Green
        $download = $false
    }
}
if ($download) {
    Write-Host "Baixando modelo Whisper original (apenas uma vez)..." -ForegroundColor Cyan
    $uri = "https://huggingface.co/ggerganov/whisper.cpp/resolve/f281eb45af861ab5e5297d23694b7d46e090c02c/ggml-tiny-q5_1.bin"
    Invoke-WebRequest -Uri $uri -OutFile $modelPath -MaximumRedirection 10
    $actual = (Get-FileHash -Algorithm SHA256 -Path $modelPath).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item $modelPath -ErrorAction SilentlyContinue
        throw "Hash do modelo diferente do esperado. Download descartado."
    }
    Write-Host "Modelo Whisper verificado com SHA-256." -ForegroundColor Green
}

Write-Host "Instalando dependencias Flutter..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou." }

Write-Host ""
Write-Host "PREPARACAO CONCLUIDA!" -ForegroundColor Green
Write-Host "Conecte o Galaxy com Depuracao USB e autorize o computador."
Write-Host "Execute: flutter devices"
Write-Host "Depois:  flutter run"
Write-Host "O aplicativo 'Zeluvori DEV' instala ao lado do Zeluvori oficial."
Write-Host "Para Hot Reload, pressione 'r' no terminal do flutter run."
