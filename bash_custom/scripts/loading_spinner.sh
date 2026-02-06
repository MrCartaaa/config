"${@:2}" &
printf "$1\t  "
i=1
while ps -p $! >/dev/null; do
  for X in "🕛" "🕐" "🕑" "🕒" "🕓" "🕔" "🕕" "🕖" "🕗" "🕘" "🕙" "🕚"; do
    echo -en "\b\b$X"
    sleep 0.1
  done
done
echo -e "\b\b  "
