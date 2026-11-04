#!/usr/bin/env bash
# Click on the clock: this month, weeks from Monday, this week in green; a second click closes it.
source "$HOME/.config/sketchybar/colors.sh"
if [ "$(sketchybar --query clock | jq -r .popup.drawing)" = on ]; then
  sketchybar --set clock popup.drawing=off; exit 0
fi
today=$(date +%-d)
i=0
while IFS= read -r line && [ $i -lt 8 ]; do
  color="$TEXT"
  [ $i -eq 0 ] && color="$ACCENT"
  [ $i -ge 2 ] && grep -qE "(^| )$today( |$)" <<<"$line" && color="$OK"
  sketchybar --set "clock.cal.$i" label="$line" label.color="$color" drawing=on
  i=$((i + 1))
done < <(/usr/bin/python3 -I -c '
import calendar, datetime
d = datetime.date.today()
months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre",
          "novembre", "décembre"]
print(f"{months[d.month - 1]} {d.year}".center(20).rstrip())
print("lu ma me je ve sa di")
for week in calendar.Calendar(0).monthdayscalendar(d.year, d.month):
    print(" ".join(f"{x:2d}" if x else "  " for x in week))
')
while [ $i -lt 8 ]; do sketchybar --set "clock.cal.$i" drawing=off; i=$((i + 1)); done
sketchybar --set clock popup.drawing=on
