search() {
	ggrep -F -e "$1"
}
ggrep() {
	files=(`git grep --name-only "$@"`)
	count=${#files[@]}
	echo "Opening $count matching files."
	for i in "${!files[@]}"
	do
	  fn="${files[$i]}"
	  printf "%4s. %s\n" "$(( $i + 1 ))" "$fn"
	  read -p "    Press enter to open..."
	  termux-open $fn
	done
}
webm2ogg() {
  for f in "$@"
  do
    ffmpeg -v warning -i "$f" -vn -acodec copy "${f%.webm}.ogg" && rm "$f"
  done
}
2worstmp3() {
  for f in "$@"
  do
    b=$(echo "$f" | rev | cut -f 2- -d '.' | rev)
    echo "Converting \"$f\" to a:9 -lq.mp3..."
    ffmpeg -v warning -n -i "$f" -codec:a libmp3lame -qscale:a 9 output.mp3 && mv output.mp3 "$b-wq.mp3"
  done
}
2lqmp3() {
  for f in "$@"
  do
    b=$(echo "$f" | rev | cut -f 2- -d '.' | rev)
    echo "Converting \"$f\" to a:7 -lq.mp3..."
    ffmpeg -v warning -n -i "$f" -codec:a libmp3lame -qscale:a 7 output.mp3 && mv output.mp3 "$b-lq.mp3"
  done
}
mergeThesePdfsCmd() {
  # If a publisher splits an OA Book into N Chapters
  # Use this cmd in a directory with only those PDFs
  # mergeCmd 2-z out.pdf will print out the qpdf cmd
  # to run to merge these files, skipping their
  # first pages, for example.
  # run `mergeThesePdfsCmd | sh` to run the command
  pages="${1:-1-z}"
  outf="${2:-out.pdf}"
  ret="qpdf --empty --pages "
  for fd in *; do
    ret="$ret \"$fd\" '$pages'"
  done
  echo "$ret -- '$outf'"
}

SELECTOUTFILEPREFIX=select-pages-from-
pdfselect() {
  # Uses poppler utils to extract specific pages
  # into a new pdf file. Call with filenames only
  # and type the page ranges when prompted.
  # Normally, just use qpdf like a normal person.
  # This function is for the cases qpdf barfs on
  TEMPFILEPREFIX=pdfselect-page-
  if compgen -G "./$TEMPFILEPREFIX*.pdf" > /dev/null; then
    echo "Oops! Tempfiles still exist. Something went wrong last time? rm and retry..."
    return 1
  fi

  for fd in "$@"; do
    F=1
    while [ $F -ne 0 ]; do
      read -p "From page (0 to break): " F
      if [ $F -eq 0 ]
      then
        break
      fi
      read -p "To page: " L
      echo "Splitting from $F to $L..."
      if pdfseparate -f "$F" -l "$L" "$fd" "$TEMPFILEPREFIX%05d.pdf" ; then
        echo "Split!"
      else
        echo "Something went wrong!"
        return 1
      fi
    done
    if compgen -G "./$TEMPFILEPREFIX*.pdf" > /dev/null; then
      echo "Merging to $SELECTOUTFILEPREFIX$fd..."
      pdfunite $TEMPFILEPREFIX*.pdf "$SELECTOUTFILEPREFIX$fd" && rm $TEMPFILEPREFIX*.pdf
    fi
  done
}

edittedVolumeSplitter() {
  # Uses qpdf to help split an editted volume
  # into N, named PDFs. Call with a single file
  # then follow the prompts to set options
  if [ ! -f "$1" ]; then
    echo "ERROR: file does not exist"
    return 1
  fi
  termux-open "$1"
  read -e -p "Provide frontmatter page ranges (enter for none): " FP
  read -e -p "Provide backmatter page range(s): " BP
  if [ ! -z "$FP" ]; then
    FP="$FP,"
  fi
  if [ ! -z "$BP" ]; then
    BP=",$BP"
  fi
  i=1
  while true
  do
    read -e -d "$" -p "Filename (ending in $, empty=quit): " FD
    if [ -z "$FD" ]; then
      break
    else
      FD="${FD//[^A-Za-z0-9À-ÿĀ-žṭṅṇṃṁḍṛḷ一-鿯㐀-䶵，-？\,\. \[\]\(\)\"\'\<\>‘’‹›”“«»+@–—-]/_}.pdf"
    fi
    while true
    do
      read -e -p "Provide page range for paper #$i: " PR
      if [ -z "$PR" ]; then
        continue
      else
        break
      fi
    done
    qpdf --empty --pages "$1" "$FP$PR$BP" -- "$FD"
    if [ $? -ne 0 ]; then
      echo "ERROR: qpdf exited with code $?"
      return 1
    fi
    ((i=i+1))
  done
}

# Create a data URL from a file
function dataurl() {
	local mimeType=$(file -b --mime-type "$1");
	if [[ $mimeType == text/* ]]; then
		mimeType="${mimeType};charset=utf-8";
	fi
	echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')";
}

function tre() {
	tree -aC -I '.git|node_modules|bower_components|_site|.jekyll-cache' --dirsfirst "$@" | less -FRNX;
}

# Copy w/ progress
cp_p () {
  rsync -WavP --human-readable --progress "$1" "$2"
}

# Use Git’s colored diff as diff
hash git &>/dev/null;
if [ $? -eq 0 ]; then
	function diff() {
		git diff --no-index --color-words "$@";
	}
fi;

