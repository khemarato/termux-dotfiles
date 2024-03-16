#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")";

git pull;

function doIt() {
        mkdir -p ~/.local/share;
        pkg install -y rsync tree jq file build-essential git openssh binutils libandroid-spawn python perl-rename ffmpeg youtubedr termux-api qpdf poppler exiftool ripgrep termux-exec termux-tools imagemagick traceroute vim which;
        /data/data/com.termux/files/usr/bin/python3 -m pip install --upgrade pip;
        pip install regex pathvalidate unidecode ipython feedyaspin google google-api-python-client google_auth_oauthlib joblib youtube-transcript-api pypdf titlecase pyyaml ebooklib python-slugify python-frontmatter;
        pip install --upgrade --force-reinstall git+https://github.com/ytdl-org/youtube-dl.git
        pkg install libxml2 libxslt python-cryptography;
        pip install lxml beautifulsoup4;
        pkg install python-numpy matplotlib tur-repo;
        pkg install python-scipy;
        pip install threadpoolctl wheel cython setuptools nltk;
        pip install --no-build-isolation scikit-learn;
        # pkg install nodejs-lts ruby;
	rsync --exclude ".git/" --exclude ".DS_Store" --exclude "bootstrap.sh" \
  --exclude "git-completion.bash" --exclude "git-prompt.bash" \
  --exclude "dircolors" --exclude "aliases.bash" --exclude "functions.bash" \
  --exclude "thaiwordlist.txt" --exclude "en_words_huge.txt" --exclude "en_words_big.txt" --exclude "en_words.txt" \
          -avh . ~;
    termux-setup-storage;
	source ~/.bash_profile;
}

if [ "$1" == "--force" -o "$1" == "-f" ]; then
	doIt;
else
	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " -n 1;
	echo "";
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		doIt;
	fi;
fi;
unset doIt;

 doIt;

