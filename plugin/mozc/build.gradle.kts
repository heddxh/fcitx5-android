plugins {
    id("org.fcitx.fcitx5.android.app-convention")
    id("org.fcitx.fcitx5.android.plugin-app-convention")
    id("org.fcitx.fcitx5.android.native-app-convention")
    id("org.fcitx.fcitx5.android.build-metadata")
    id("org.fcitx.fcitx5.android.data-descriptor")
    id("org.fcitx.fcitx5.android.fcitx-component")
}

val mozcDataSha256 = providers.gradleProperty("mozcDataSha256")
    .orElse(providers.environmentVariable("MOZC_DATA_SHA256"))
    .orNull

android {
    namespace = "org.fcitx.fcitx5.android.plugin.mozc"

    defaultConfig {
        applicationId = "org.fcitx.fcitx5.android.plugin.mozc"

        @Suppress("UnstableApiUsage")
        externalNativeBuild {
            cmake {
                targets(
                    "mozc"
                )
                if (mozcDataSha256 != null) {
                    arguments("-DMOZC_DATA_SHA256=$mozcDataSha256")
                }
            }
        }
    }

    buildFeatures {
        resValues = true
    }

    buildTypes {
        release {
            resValue("string", "app_name", "@string/app_name_release")
            proguardFile("proguard-rules.pro")
        }
        debug {
            resValue("string", "app_name", "@string/app_name_debug")
        }
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "**/libc++_shared.so",
                "**/libFcitx5*"
            )
        }
    }
}

dependencies {
    implementation(project(":lib:fcitx5"))
    implementation(project(":lib:plugin-base"))
}
