# Chỉ đổi kích thước màn hình emulator trong thời gian kiểm thử và luôn khôi phục.
$ErrorActionPreference='Stop'
$env:ANDROID_HOME='D:\Android\Sdk'
$env:ANDROID_SDK_ROOT='D:\Android\Sdk'
$env:ANDROID_AVD_HOME='D:\Android\avd'
$env:TEMP='D:\SRS-Review-AI-Mobile\.local\tmp'
$env:TMP=$env:TEMP
$env:GRADLE_USER_HOME='D:\SRS-Review-AI-Mobile\.local\gradle'
$env:JAVA_TOOL_OPTIONS='-Djava.io.tmpdir=D:/SRS-Review-AI-Mobile/.local/tmp'
$adb='D:\Android\Sdk\platform-tools\adb.exe'
try{
  & $adb -s emulator-5554 shell wm density 480
  foreach($config in @(@(360,'1080x2400'),@(390,'1170x2532'),@(412,'1236x2676'))){
    & $adb -s emulator-5554 shell wm size $config[1]
    $ErrorActionPreference='Continue'
    flutter drive --driver=test_driver/academic_driver.dart --target=integration_test/academic_test.dart -d emulator-5554 --dart-define="CAPTURE_WIDTH=$($config[0])" *> ".local/android-phase2-$($config[0]).log"
    $ErrorActionPreference='Stop'
    if($LASTEXITCODE -ne 0){throw "Kiểm thử Android $($config[0])dp thất bại; xem log trong .local."}
    Write-Output "PASS Android $($config[0])dp"
  }
}finally{
  & $adb -s emulator-5554 shell wm size reset
  & $adb -s emulator-5554 shell wm density reset
}
