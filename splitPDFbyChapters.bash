#!/bin/bash

# Check if the input file is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <pdf-file>"
  exit 1
fi

# Get input PDF file and check existence
input_pdf="$1"
if [ ! -f "$input_pdf" ]; then
  echo "Error: File '$input_pdf' not found!"
  exit 1
fi

echo "Extracting bookmark info from \"$1\"..."

previous_page=1
previous_title="Frontmatter"
title=""
pdftk "$input_pdf" dump_data | while read -r line; do
  case "$line" in
    BookmarkTitle:*)
      # Clean up title
      title=$(echo "$line" | sed 's/BookmarkTitle: //g' | python3 -c "import html; from unidecode import unidecode; print(unidecode(html.unescape(input())))" | sed 's/[<>:"/\\|?#!*]//g')
      ;;
    BookmarkPageNumber:*)
      page=$(echo "$line" | sed 's/BookmarkPageNumber: //g')
      if [ -z "$title" ]; then
        echo "No title found for Bookmark on page $page"
        exit 1
      fi
      if [ "$page" -gt "$previous_page" ]; then
        range="${previous_page}-$(($page - 1))"
        output_file="${input_pdf%.pdf}_ $previous_title.pdf"
        echo "Extracting: \"$output_file\" (pages $range)"
        qpdf --no-warn --warning-exit-0 --empty --pages "$input_pdf" "$range" -- "$output_file" || exit $?
      fi
      previous_title="$title"
      previous_page="$page"
      ;;
    PageMediaBegin|'')
      # Handle the last chapter
      if [ "$title" != "$previous_title" ]; then
        echo "Unexpected title mismatch. Got \"$title\" != \"$previous_title\""
        exit 1
      fi
      output_file="${input_pdf%.pdf}_ $title.pdf"
      echo "Extracting: $output_file (pages $page to end)"
      qpdf --no-warn --warning-exit-0 --empty --pages "$input_pdf" "$page-z" -- "$output_file" || exit $?
      break
      ;;
  esac
done
echo "Done!"
