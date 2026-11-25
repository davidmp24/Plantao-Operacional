# ============================================================
#  Build Script — Sophos Workaround via Reverse Junction
#  Plantão Operacional Pro — Release APK
# ============================================================
$NomeProjeto = "PlantaoOperacional"
$JunctionPath = "C:\PlantaoOp"
$ProjetoReal = (Get-Location).Path

$env:JAVA_HOME        = "C:\Program Files\Java\jdk-17.0.1"
$env:ANDROID_HOME     = "$env:LOCALAPPDATA\Android\Sdk"
$env:GRADLE_USER_HOME = "C:\GradleHome"
$env:PATH             = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

Write-Host ""
Write-Host "=== BUILD RELEASE INICIANDO (SOPHOS BYPASS) ===" -ForegroundColor Cyan
Write-Host "GRADLE_USER_HOME:  $env:GRADLE_USER_HOME"
Write-Host "Build output:      C:\GradleBuild\$NomeProjeto"
Write-Host ""

# 1. Garante pastas raiz seguras
New-Item -ItemType Directory -Force -Path "C:\GradleBuild\$NomeProjeto" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\GradleHome"               | Out-Null

# 2. Cria a Junction Reversa (Engana o Sophos / Dart AOT)
if (Test-Path $JunctionPath) {
    cmd /c rmdir $JunctionPath
}
cmd /c mklink /J "$JunctionPath" "$ProjetoReal"

Write-Host "Junction criada: $JunctionPath -> $ProjetoReal" -ForegroundColor Cyan
Write-Host "Iniciando build a partir do caminho seguro..." -ForegroundColor Yellow

# 3. Executa o build de DENTRO da junction
Set-Location $JunctionPath

flutter build apk --release --android-skip-build-dependency-validation

# Voltar para o diretório original
Set-Location $ProjetoReal

# 4. Localizar e Copiar o APK
$apk = Get-ChildItem "C:\GradleBuild\$NomeProjeto\app\outputs\flutter-apk" -Filter "app-release.apk" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($apk) {
    Copy-Item $apk.FullName ".\app-release.apk" -Force
    Write-Host ""
    Write-Host "✅ APK gerado com sucesso: $($apk.FullName)" -ForegroundColor Green
    Write-Host "✅ Copiado para a raiz: $(Resolve-Path '.\app-release.apk')" -ForegroundColor Green
} else {
    Write-Host "❌ APK não encontrado em C:\GradleBuild\$NomeProjeto\app\outputs\flutter-apk" -ForegroundColor Red
}
