plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Importações necessárias para Properties e FileInputStream
import java.util.Properties
        import java.io.FileInputStream

// Carregando o arquivo key.properties com sintaxe Kotlin
val keystorePropertiesFile = rootProject.file("key.properties") // Procura por key.properties na pasta android/
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { fis -> // Garante que o FileInputStream seja fechado
        keystoreProperties.load(fis)
    }
}

android {
    namespace = "com.example.plantao"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // <<< NDK ATUALIZADO AQUI

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.plantao"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists() && keystoreProperties.containsKey("storeFile")) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile")) // 'file()' converte a string do caminho para um objeto File
                storePassword = keystoreProperties.getProperty("storePassword")
            } else {
                println("********************************************************************************")
                println("WARNING: 'key.properties' not found or 'storeFile' not defined in it.")
                println("Release builds will not be signed. Ensure 'android/key.properties' is set up correctly.")
                println("********************************************************************************")
                // Para evitar falha no build se o arquivo não existir, mas o build não será assinado para release.
                // Você pode optar por fazer o build falhar aqui se a assinatura for obrigatória.
                // signingConfig = signingConfigs.getByName("debug") // Fallback para debug, mas não ideal para release.
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            // Suas outras configurações de release (mantenha as que já tem, como minifyEnabled, etc.)
            // Exemplo:
            // isMinifyEnabled = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Suas dependências aqui
}