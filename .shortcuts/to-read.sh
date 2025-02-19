#!/data/data/com.termux/files/usr/bin/bash
python3 /data/data/com.termux/files/home/storage/shared/Documents/buddhist-uni.github.io/scripts/prepare-to-read-data.py /data/data/com.termux/files/home/storage/shared/Download/ 2> >(termux-clipboard-set)

read -p "Press enter to exit..." foo
