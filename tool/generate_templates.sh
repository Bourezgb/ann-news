#!/usr/bin/env bash
# يولّد خلفيات قوالب ANN (الهوية البصرية للشبكة الجزائرية للأخبار) بـ ImageMagick.
# الاستعمال: MAGICK=magick bash tool/generate_templates.sh
# النصوص نفسها تُرسم من التطبيق بناءً على assets/templates/templates.json.
set -euo pipefail
cd "$(dirname "$0")/.."
M="${MAGICK:-magick}"
OUT=assets/templates
LOGO=assets/images/ann-logo-white.png
RED="#B61A1B"

logo_at() { # $1 = width, $2 = x, $3 = y
  "$M" "$LOGO" -resize "$1x" "$OUT/.logo.png"
  echo "+$2+$3"
}

# قوالب بلون كامل (JPG): خلفية متدرجة + الشعار أعلى اليمين.
solid() { # $1 = name, $2 = top color, $3 = bottom color
  "$M" -size 2000x2000 "gradient:$2-$3" "$OUT/.base.png"
  "$M" "$OUT/.base.png" "$OUT/.logo.png" -geometry "$(logo_at 460 1460 110)" -composite \
    -quality 92 "$OUT/$1.jpg"
}

# قوالب بصورة (PNG شفافة): الصورة تظهر في الأعلى، والتدرج الأحمر والمستطيل الأبيض للعنوان في الأسفل.
photo() { # $1 = name, $2 = accent color for title box
  logo_at 460 1460 110 >/dev/null
  "$M" -size 2000x2000 xc:none \
    \( -size 1000x800 "gradient:rgba(182,26,27,0)-rgba(182,26,27,1)" \) -geometry +0+1100 -composite \
    -fill "$RED" -draw "rectangle 0,1900 2000,2000" \
    -fill white -draw "rectangle 160,1380 1700,1800" \
    "$OUT/.logo.png" -geometry +1460+110 -composite \
    "PNG32:$OUT/$1.png"
}

solid latest_solid "#B61A1B" "#8E1213"
solid urgent_solid "#E50000" "#B61A1B"
solid important_solid "#8E1213" "#B61A1B"
photo latest_photo "$RED"
photo urgent_photo "$RED"
photo important_photo "$RED"

# قالب التصريح: الجزء الأيسر شفاف لصورة المتحدث، والأيمن أحمر للنص.
logo_at 460 1460 110 >/dev/null
"$M" -size 2000x2000 xc:none -fill "$RED" -draw "rectangle 880,0 2000,2000" \
  "$OUT/.logo.png" -geometry +1460+110 -composite "PNG32:$OUT/statement_quote.png"

# الريل (1080×1920) واليوتيوب (1920×1080): مستطيلان للعنوان (أبيض ثم أحمر) فوق الصورة.
logo_at 300 720 90 >/dev/null
"$M" -size 1080x1920 xc:none -fill white -draw "rectangle 120,1090 960,1230" \
  -fill "$RED" -draw "rectangle 120,1230 960,1372" \
  "$OUT/.logo.png" -geometry +720+90 -composite "PNG32:$OUT/reel.png"

logo_at 380 1460 70 >/dev/null
"$M" -size 1920x1080 xc:none -fill white -draw "rectangle 520,600 1400,746" \
  -fill "$RED" -draw "rectangle 520,746 1400,880" \
  "$OUT/.logo.png" -geometry +1460+70 -composite "PNG32:$OUT/youtube.png"

rm -f "$OUT/.base.png" "$OUT/.logo.png"
echo "Templates generated in $OUT"
