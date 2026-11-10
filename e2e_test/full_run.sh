#!/bin/zsh
# Lượt chạy demo đầy đủ: quay Artemis (headless) + điện thoại (scrcpy liên tục), chạy flow, ghép video.
#   e2e_test/full_run.sh [FL01,FL02,...]
# Cần: Artemis UI :8020, server Docker :8000, điện thoại cắm USB và đã mở khoá.
set -u
REPO=/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai
ARTEMIS=/Volumes/SSD/AppData/artemis
SERIAL=${ARTEMIS_SERIAL:-49BEF6B6TCRSJNQW}
ONLY=${1:-}
STAMP=$(date +%Y%m%d-%H%M)
OUT=$ARTEMIS/traces/demo-$STAMP
mkdir -p $OUT/ui
echo "out: $OUT"

adb -s $SERIAL shell svc power stayon true  # "usb" không ăn trên Xiaomi (mStayOn=false, đo 11/11)
adb -s $SERIAL reverse tcp:8010 tcp:8000
docker logs -f --since 1s srs-review-ai-server-1 >> /tmp/srs-docker-server.log 2>&1 &
LOGS=$!

node $REPO/e2e_test/record_artemis_ui.mjs $OUT/ui > $OUT/ui-rec.log 2>&1 &
UIREC=$!
scrcpy --serial $SERIAL --no-window --no-audio --record $OUT/phone.mkv --record-format mkv \
  --video-bit-rate 4M > $OUT/phone-rec.log 2>&1 &
PHONE=$!
sleep 5

cd $ARTEMIS
SRS_E2E_CONTAINER=srs-review-ai-server-1 SRS_E2E_HOST_PORT=8000 SRS_E2E_SERVER_LOG=/tmp/srs-docker-server.log \
ARTEMIS_SERIAL=$SERIAL ARTEMIS_BASE_URL=http://127.0.0.1:8020 \
  .venv/bin/python $REPO/e2e_test/run_suite.py --suite flows --runs 1 ${=ONLY:+--only $ONLY}  # ${=} = tách từ trong zsh
RC=$?

touch $OUT/ui/STOP
kill -TERM $PHONE; wait $PHONE 2>/dev/null  # SIGINT không dừng scrcpy --no-window; TERM chốt file mkv
wait $UIREC 2>/dev/null
kill $LOGS 2>/dev/null

UI=$(ls $OUT/ui/*.webm | head -1)
python3 $REPO/e2e_test/compose_videos.py "$UI" --phone $OUT/phone.mkv \
  --log $REPO/e2e_test/results/$(date +%Y-%m-%d).jsonl --out $OUT/side-by-side
echo "suite exit=$RC"
exit $RC
