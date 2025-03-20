#!/data/data/com.termux/files/usr/bin/bash
alreadylocked="false"
termux-notification-list | jq -r '.[] | select(.id == 1337).content' | grep -qF 'wake lock held' && alreadylocked="true"
[ $alreadylocked = "false" ] && termux-wake-lock
apt autoremove -y
pkg autoclean
pip install --upgrade --force-reinstall git+https://github.com/ytdl-org/youtube-dl.git
/data/data/com.termux/files/usr/bin/python3 -m pip install --upgrade regex pathvalidate unidecode ipython feedreader yaspin google google-api-python-client google_auth_oauthlib joblib youtube-transcript-api pypdf titlecase pyyaml ebooklib python-slugify python-frontmatter lxml beautifulsoup4 threadpoolctl wheel cython setuptools nltk Mastodon.py imagehash srt;
pip install --no-build-isolation scikit-learn pywavelets;
[ $alreadylocked = "false" ] && termux-wake-unlock

