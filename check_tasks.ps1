# Get gradle tasks related to plugins and dex
cd android
.\gradlew.bat :app:tasks --group=build 2>&1 | Select-String -Pattern "assemble|debug|plugin" | Select-Object -First 30
