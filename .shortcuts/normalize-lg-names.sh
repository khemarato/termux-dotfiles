#!/data/data/com.termux/files/usr/bin/bash

cd /data/data/com.termux/files/home/storage/shared/Download/

# remove anything in ()s (space before or after)
perl-rename -v "s/\([a-zA-Z0-9 _\.-]*\) //g" *
perl-rename -v "s/ \([a-zA-Z0-9 _\.-]*\)//g" *
# remove "-Publisher" from end
perl-rename -v 's/([a-z])-[A-Z][a-zA-Z 0-9]+\.(cbz|epub|pdf)/$1.$2/g' *
# flip from "Author - Title.ext" to "Title - Author.ext"
perl-rename -v 's/(.*) - (.*)\.([a-z0-9]+)$/$2 - $1.$3/g' *

