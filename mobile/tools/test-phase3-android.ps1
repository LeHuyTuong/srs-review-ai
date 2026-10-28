# Một đợt kiểm chứng Phase 3; ghi cấu hình trước/sau và khôi phục cả override sẵn có.
$ErrorActionPreference='Stop'
$env:ANDROID_HOME='D:\Android\Sdk'
$env:ANDROID_SDK_ROOT='D:\Android\Sdk'
$env:ANDROID_AVD_HOME='D:\Android\avd'
$env:TEMP='D:\SRS-Review-AI-Mobile\.local\tmp'
$env:TMP=$env:TEMP
$env:GRADLE_USER_HOME='D:\SRS-Review-AI-Mobile\.local\gradle'
$env:JAVA_TOOL_OPTIONS='-Djava.io.tmpdir=D:/SRS-Review-AI-Mobile/.local/tmp'
$adb='D:\Android\Sdk\platform-tools\adb.exe'
$evidence='D:\SRS-Review-AI-Mobile\docs\evidence\phase3'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$initialSize=(& $adb -s emulator-5554 shell wm size) -join "`n"
$initialDensity=(& $adb -s emulator-5554 shell wm density) -join "`n"
@($initialSize,$initialDensity)|Set-Content -LiteralPath "$evidence\emulator-before.log" -Encoding utf8
try {
  & $adb -s emulator-5554 shell wm density 480
  foreach($config in @(@(360,'1080x2400'),@(390,'1170x2532'),@(412,'1236x2676'))){
    & $adb -s emulator-5554 shell wm size $config[1]
    $ErrorActionPreference='Continue'
    flutter drive --driver=test_driver/management_driver.dart --target=integration_test/management_test.dart -d emulator-5554 --dart-define="CAPTURE_WIDTH=$($config[0])" *> "$evidence\android-$($config[0]).log"
    $ErrorActionPreference='Stop'
    if($LASTEXITCODE -ne 0){throw "Kiểm thử Android $($config[0])dp thất bại; xem log evidence."}
    Write-Output "PASS Android $($config[0])dp"
  }
} finally {
  & $adb -s emulator-5554 shell wm size reset
  & $adb -s emulator-5554 shell wm density reset
  if($initialSize -match 'Override size:\s*(\d+x\d+)'){& $adb -s emulator-5554 shell wm size $Matches[1]}
  if($initialDensity -match 'Override density:\s*(\d+)'){& $adb -s emulator-5554 shell wm density $Matches[1]}
  @((& $adb -s emulator-5554 shell wm size),(& $adb -s emulator-5554 shell wm density))|Set-Content -LiteralPath "$evidence\emulator-after.log" -Encoding utf8
}
