#!/data/data/com.termux/files/usr/bin/bash
alreadylocked="false"
termux-notification-list | jq -r '.[] | select(.id == 1337).content' | grep -qF 'wake lock held' && alreadylocked="true"
[ $alreadylocked = "false" ] && termux-wake-lock
timeout 1500 pkg upgrade -y
[ $? -gt 0 ] && echo "ERROR: pkg upgrade timeout" && dpkg --configure -a --force-confnew
apt autoremove -y
pkg autoclean
/data/data/com.termux/files/usr/bin/python3 -m pip install --upgrade regex pathvalidate unidecode ipython feedreader yaspin google google-api-python-client google_auth_oauthlib joblib youtube-transcript-api youtube-dl pypdf titlecase pyyaml ebooklib python-slugify python-frontmatter lxml beautifulsoup4 threadpoolctl wheel cython setuptools nltk;
[ $alreadylocked = "false" ] && termux-wake-unlock

