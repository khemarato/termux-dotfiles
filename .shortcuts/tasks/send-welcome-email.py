#!/data/data/com.termux/files/usr/bin/python

import tinyapi

print("Logging in...")
session = tinyapi.Session("buddhist-uni", "password")
print("Getting the welcome email...")
message = session.get_messages(order="sent_at asc", offset=2, count=1)
if len(message) == 1 and message[0]['subject'] == 'Welcome to the Buddhist University on GitHub':
  print("Sending email...")
  session.request("method:queue", message)
  print("sent")
else:
  print("Error getting message!")
  exit(1)

