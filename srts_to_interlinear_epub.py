#!/bin/python3

import argparse
import srt
from ebooklib import epub
from datetime import timedelta

EPSILON = timedelta(seconds=0.0001)

def parse_srt(file_path):
  with open(file_path, 'r', encoding='utf-8') as f:
    srt_content = f.read()
  return list(srt.parse(srt_content))

def group_subtitles(eng_subs, orig_subs):
  """
  Group subtitles from two lists based on overlapping time stamps.
  Returns a list of groups, each as a tuple (list_of_eng_subs, list_of_orig_subs).
  """
  groups = []
  i, j = 0, 0
  # Process both lists until one is exhausted
  while i < len(eng_subs) and j < len(orig_subs):
    eng = eng_subs[i]
    orig = orig_subs[j]
    # Check for overlap: intervals overlap if
    # max(start times) <= min(end times)
    if max(eng.start, orig.start) <= min(eng.end, orig.end):
      group_eng = []
      group_orig = []
      # Start group from the earliest start time
      current_start = min(eng.start, orig.start)
      # Set an initial group end as the max of the two end times
      current_end = max(eng.end, orig.end)
      # Collect overlapping English subtitles
      while i < len(eng_subs) and eng_subs[i].start <= current_end:
        group_eng.append(eng_subs[i])
        current_end = max(current_end, eng_subs[i].end)
        i += 1
      # Collect overlapping Original subtitles
      while j < len(orig_subs) and orig_subs[j].start <= current_end:
        group_orig.append(orig_subs[j])
        current_end = max(current_end, orig_subs[j].end)
        j += 1
      groups.append((group_eng, group_orig))
    else:
      # No overlap: add the subtitle that starts earlier as a solo group.
      if eng.start < orig.start:
        groups.append(([eng], []))
        i += 1
      else:
        groups.append(([], [orig]))
        j += 1

  # Append any remaining subtitles as solo groups.
  while i < len(eng_subs):
    groups.append(([eng_subs[i]], []))
    i += 1
  while j < len(orig_subs):
    groups.append(([], [orig_subs[j]]))
    j += 1

  return groups

def generate_interlinear_html(groups, title):
  html = f'<html><head><meta charset="utf-8"/></head><body>\n'
  html += f'<h1>{title}</h1>\n'
  # Each group is rendered as a block with timings and the combined texts.
  for group_eng, group_orig in groups:
    # If available, pick a representative time (using the earliest start and latest end)
    if group_eng or group_orig:
      start = min([sub.start for sub in group_eng + group_orig])
      end = max([sub.end for sub in group_eng + group_orig])
      html += f'<div style="margin-bottom:1em;">\n'
      html += f'  <p><em>{str(start+EPSILON)[:-4]} - {str(end+EPSILON)[:-4]}</em></p>\n'
      if group_orig:
        orig_text = ' '.join(sub.content for sub in group_orig)
        html += f'  <p style="font-size: 117%; margin:0;">{orig_text}</p>\n'
      if group_eng:
        # Combine multiple lines if needed
        eng_text = ' '.join(sub.content for sub in group_eng)
        html += f'  <p style="color: green; margin:0;">{eng_text}</p>\n'
      html += '</div>\n'
  html += '</body></html>\n'
  return html

def create_interlinear_epub(eng_srt_file, orig_srt_file, output_filename, non_interactive):
  # Parse the subtitle files.
  eng_subs = parse_srt(eng_srt_file)
  orig_subs = parse_srt(orig_srt_file)
  # Group subtitles based on overlapping time stamps.
  groups = group_subtitles(eng_subs, orig_subs)
  # Generate interlinear HTML content.
  title = f'Interlinear Translation of {orig_srt_file}'
  if not non_interactive:
    title = input(f'Title: ')
  chapter_html = generate_interlinear_html(groups, title)
  # Create a new EPUB book.
  book = epub.EpubBook()
  book.set_identifier(orig_srt_file)
  book.set_title(title)
  book.set_language('en')
  book.add_author('Subtitle Combiner')

  # Create a chapter with the HTML content.
  chapter = epub.EpubHtml(title=title,
    file_name='chap_1.xhtml', lang='en')
  chapter.content = chapter_html
  book.add_item(chapter)

  # Set up the table of contents and spine.
  book.toc = (epub.Link('chap_1.xhtml', chapter.title, 'chap1'),)
  book.add_item(epub.EpubNcx())
  book.add_item(epub.EpubNav())
  book.spine = ['nav', chapter]

  # Write out the EPUB file.
  epub.write_epub(output_filename, book, {})

if __name__ == '__main__':
  parser = argparse.ArgumentParser(
    description='Combine two .srt files (English and original language) into an interlinear EPUB ebook, aligning by time stamps.'
  )
  parser.add_argument('eng_srt', help='Path to the English subtitle file (.srt)')
  parser.add_argument('orig_srt', help="Path to the original language subtitle file (.srt)")
  parser.add_argument('-o', '--output', default='interlinear_translation.epub', help='Output EPUB filename')
  parser.add_argument('--non-interactive', action='store_true', help='Run in non-interactive mode', default=False, dest='non_interactive')
  args = parser.parse_args()
  create_interlinear_epub(args.eng_srt, args.orig_srt, args.output, args.non_interactive)

