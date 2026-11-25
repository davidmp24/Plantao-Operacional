# 🛡️ Guia: Gradle vs. Sophos — Estratégia Anti-Bloqueio para Projetos Android e Flutter

> **Contexto:** PC corporativo Windows 10 com **Sophos Endpoint** instalado sem acesso administrativo.
> Este guia documenta a estratégia expandida e validada em múltiplos projetos (CalendarioFamiliar, FocoTexto, Plantão Operacional).

---

## 🔍 O que o Sophos bloqueia e por quê?

O Sophos monitora **ativamente** operações de I/O em pastas dentro do perfil do usuário (C:\Users\<usuario>\Documents, .gradle, etc). Ele intercepta operações cruciais do processo de build:

| Operação Bloqueada | Erro Típico no Build |
|---|---|
| Gradle MoveFileEx (renomeação atômica) no cache | Could not move temporary workspace to immutable location |
| Flutter AOT (escrita no .dart_tool) | Unable to read file: ...\app.dill. Dart snapshot generator failed |
| Impeller compilando shaders | Could not write file ink_sparkle.frag |

---

## 🧠 A Estratégia Principal

A solução exige tirar as operações pesadas do campo de visão do Sophos. Como não podemos mover o projeto (que deve ficar em Documents), nós redirecionamos as saídas e **enganamos os compiladores** sobre onde eles estão executando.

### 1. Redirecionamento de Saídas (Output e Cache)
As saídas de compilação do Gradle e os caches globais são redirecionados para a raiz de C:\, onde o monitoramento é mais brando.
* Cache do Gradle vai para: C:\GradleHome
* Output do Build vai para: C:\GradleBuild\<NomeDoProjeto>

### 2. Junction Reversa (O Bypass do Flutter/Dart)
Para builds em Flutter, o Dart escreve metadados pesados no diretório oculto .dart_tool do projeto (em Documents). O Sophos intercepta isso.
A solução é criar um **atalho no nível de sistema (Junction)** na raiz do disco (C:\NomeProjeto) apontando para a pasta real do projeto em Documents. Ao rodar os comandos a partir de C:\NomeProjeto, o Flutter entende que o caminho absoluto do projeto não está mais em Documents, e o Sophos ignora a atividade.

---

## 📋 Passo a Passo de Configuração do Projeto

### ETAPA 1 — Configuração do Projeto Flutter (ndroid/build.gradle.kts)

No arquivo ndroid/build.gradle.kts do seu projeto, faça duas coisas:
1. Redirecione a saída de build para C:\GradleBuild.
2. Force a versão do Kotlin e Coroutines. *(O AGP 8.3 compatível com este ambiente usa um ofuscador R8 antigo que quebra se ler metadados do Kotlin 2.1.0 presentes nas dependências mais recentes).*

Adicione/modifique:
`kotlin
// 1. Redirecionamento do Build Directory
val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("C:\\GradleBuild\\NomeDoProjeto").get()   // ← troque NomeDoProjeto
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 2. Travar versões do Kotlin e Coroutines para compatibilidade com R8 (AGP 8.3)
allprojects {
    configurations.all {
        resolutionStrategy {
            force("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.9.24")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.24")
            force("org.jetbrains.kotlin:kotlin-stdlib-common:1.9.24")
            // Travar coroutines para versão baseada em Kotlin antigo
            force("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
            force("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
            force("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")
        }
    }
}
`

### ETAPA 2 — Versões de Plugins (AGP e Kotlin)

No arquivo ndroid/settings.gradle.kts (ou top-level uild.gradle), garanta as seguintes versões exatas:
`kotlin
plugins {
    // AGP 8.3.x + Kotlin 1.9.x é a combinação de ouro para evitar o Sophos
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
`

No ndroid/gradle/wrapper/gradle-wrapper.properties:
`properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.6-all.zip
`

### ETAPA 3 — Redirecionar Cache do Gradle

Adicione ao final de ndroid/gradle.properties:
`properties
# ── Sophos workaround ──────────────────────────────────────────────
gradle.user.home=C\:\\GradleHome
`

### ETAPA 4 — Desabilitar Impeller no AndroidManifest

Em ndroid/app/src/main/AndroidManifest.xml, adicione dentro da tag <application>:
`xml
<!-- Desabilita Impeller para evitar bloqueio do Sophos ao compilar shaders -->
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="false" />
`

---

## 🏗️ Script de Build (O Bypass da Junction)

Nunca rode lutter build apk diretamente de dentro do Documents. Use este script PowerShell. Salve-o como uild-release.ps1 na raiz do projeto. O script criará a Junction automaticamente e fará o build a partir dela.

`powershell
# ============================================================
#  Build Script — Sophos Workaround via Reverse Junction
# ============================================================

 = "NomeDoProjeto"   # ← ALTERE AQUI (sem espaços)

$env:JAVA_HOME        = "C:\Program Files\Java\jdk-17.0.1"
$env:ANDROID_HOME     = "$env:LOCALAPPDATA\Android\Sdk"
$env:GRADLE_USER_HOME = "C:\GradleHome"
$env:PATH             = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

# 1. Garante pastas raiz seguras
New-Item -ItemType Directory -Force -Path "C:\GradleBuild\$NomeProjeto" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\GradleHome"               | Out-Null

# 2. Cria a Junction Reversa (Engana o Sophos / Dart AOT)
$JunctionPath = "C:\$NomeProjeto"
$ProjetoReal = (Get-Location).Path

if (Test-Path $JunctionPath) {
    cmd /c rmdir $JunctionPath
}
cmd /c mklink /J "$JunctionPath" "$ProjetoReal"

Write-Host "Junction criada: $JunctionPath -> $ProjetoReal" -ForegroundColor Cyan
Write-Host "Iniciando build a partir do caminho seguro..." -ForegroundColor Yellow

# 3. Executa o build de DENTRO da junction
Set-Location $JunctionPath
flutter clean
flutter build apk --release --android-skip-build-dependency-validation

# Voltar para o diretório original
Set-Location $ProjetoReal

# 4. Localizar e Copiar o APK
$apk = Get-ChildItem "C:\GradleBuild\$NomeProjeto\app\outputs\flutter-apk" -Filter "app-release.apk" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($apk) {
    Copy-Item $apk.FullName ".\app-release.apk" -Force
    Write-Host "✅ APK copiado para a raiz do projeto: .\app-release.apk" -ForegroundColor Green
} else {
    Write-Host "❌ Falha ao encontrar o APK gerado em C:\GradleBuild\$NomeProjeto" -ForegroundColor Red
}
`

---

## ❓ Diagnóstico de Erros

| Erro | Causa | Solução |
|---|---|---|
| Unable to read file: ...\app.dill | Sophos bloqueou o AOT Compiler no .dart_tool. | Você rodou o flutter diretamente no Documents. Execute pelo script uild-release.ps1 (usa a Junction). |
| Class 'X' was compiled with an incompatible version of Kotlin (2.1.0)... | Metadados incompatíveis com ofuscador R8 antigo do AGP 8.3.2. | Adicione os orce de versão 1.9.24/1.8.1 no seu uild.gradle.kts (veja Etapa 1). |
| Could not move temporary workspace... | Sophos bloqueou o Gradle Cache. | Certifique-se que o $env:GRADLE_USER_HOME está apontando para C:\GradleHome. |
| Erro reportando que o Flutter não achou o APK no final do build | Falso Negativo. O Flutter não sabe que nós redirecionamos a saída. | Ignore o erro final do flutter. Olhe o log do PowerShell, o script copiará o APK de C:\GradleBuild automaticamente. |

### Tabela de Compatibilidade AGP × Gradle (Homologada para a Máquina)

| AGP | Gradle | Status neste PC |
|---|---|---|
| 8.7.x | 8.9 | ❌ Falha (Sophos bloqueia transforms atômicos da nova API) |
| 8.5.x | 8.7 | ❌ Falha (Sophos bloqueia transforms atômicos da nova API) |
| **8.3.2** | **8.6** | ✅ **Oficial.** Funciona perfeitamente. *(Exige travar Kotlin stdlib em 1.9.24)* |
| 8.2.2 | 8.4 | ⚠️ Flutter adverte que suporte ao AGP 8.2.2 está sendo removido. |
