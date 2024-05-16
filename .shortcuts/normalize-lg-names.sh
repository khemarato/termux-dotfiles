#!/data/data/com.termux/files/usr/bin/bash

cd /data/data/com.termux/files/home/storage/shared/Download/

# Handle ZLib Files first
perl-rename -v "s/ \(Z-Library\)\.pdf/.pdf.zl/g"  *Z-Lib*
perl-rename -v "s/ Z-Library\.epub/.epub.zl/g" *Z-Lib*

# remove anything in ()s (space before or after)
perl-rename -v "s/\([a-zA-Z0-9 _\.-]*\) //g" *.epub *.pdf *.cbz
perl-rename -v "s/ \([a-zA-Z0-9 _\.-]*\)//g" *.epub *.pdf *.cbz
# remove "-Publisher" from end
perl-rename -v 's/([a-z])-[A-Z][a-zA-Z 0-9]+\.(cbz|epub|pdf)/$1.$2/g' *.epub *.pdf *.cbz
# flip from "Author - Title.ext" to "Title - Author.ext"
perl-rename -v 's/(.*) - (.*)\.([a-z0-9]+)$/$2 - $1.$3/g' *.epub *.pdf *.cbz

# Undo ZLib hiding
perl-rename -v 's/\.zl//g' *.zl

