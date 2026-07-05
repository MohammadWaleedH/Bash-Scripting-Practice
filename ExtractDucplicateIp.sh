
#!/bin/bash      

LOGFILE="access.log"        ##cheak for logs in file you want 

if [ ! -f "$LOGFILE" ]; then                     ## cheak log files exist 
    echo "Error: $LOGFILE not found!"
    exit 1
fi

echo "===== Top 10 Source IPs ====="                      ## print top 10 ips  

awk '{print $1}' "$LOGFILE" \                            ## arrange ips in sorted form 
| sort \
| uniq -c \                                                  ## cheak for similar ips 
| sort -nr \
| head -10                                                   ## show inly top 10 




The Goal

Suppose you have an Apache or Nginx access log like this:

192.168.1.10 - - [05/Jul/2026:09:10:21] "GET /index.html HTTP/1.1" 200 532
192.168.1.15 - - [05/Jul/2026:09:10:22] "GET /login HTTP/1.1" 200 1200
192.168.1.10 - - [05/Jul/2026:09:10:23] "GET /about HTTP/1.1" 200 800
10.10.10.5 - - [05/Jul/2026:09:10:24] "GET /admin HTTP/1.1" 404 500
192.168.1.15 - - [05/Jul/2026:09:10:25] "GET /home HTTP/1.1" 200 900
192.168.1.10 - - [05/Jul/2026:09:10:26] "GET /contact HTTP/1.1" 200 300



The first field is always the client's IP address.

We want to know:

Which IP addresses are hitting my server the most?

Desired Output
3 192.168.1.10
2 192.168.1.15
1 10.10.10.5

Or maybe only the Top 10.

Step 1 — Extract only IP addresses

Use:

awk '{print $1}' access.log

Output

192.168.1.10
192.168.1.15
192.168.1.10
10.10.10.5
192.168.1.15
192.168.1.10
Why?

awk splits every line into fields.

Field 1 = IP

Field 2 = -

Field 3 = -

Field 4 = Date

...

So  $1 means First column.

Step 2 — Sort them
awk '{print $1}' access.log | sort

Output

10.10.10.5
192.168.1.10
192.168.1.10
192.168.1.10
192.168.1.15
192.168.1.15

Why?

Because uniq only counts adjacent duplicates.

Step 3 — Count duplicates
awk '{print $1}' access.log | sort | uniq -c

Output

1 10.10.10.5
3 192.168.1.10
2 192.168.1.15

uniq -c

means

Count identical consecutive lines.

Step 4 — Sort by count

Currently

1
3
2

We want

3
2
1

Use

sort -nr

Complete command

awk '{print $1}' access.log | sort | uniq -c | sort -nr

Output

3 192.168.1.10
2 192.168.1.15
1 10.10.10.5
Step 5 — Show only Top 10
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head -10

Done!

Complete Script
#!/bin/bash


LOGFILE="access.log"

echo "Top 10 Source IP Addresses"
echo "--------------------------"

awk '{print $1}' "$LOGFILE" \
| sort \
| uniq -c \
| sort -nr \
| head -10
Sample Output
Top 10 Source IP Addresses
--------------------------
145 192.168.1.10
103 192.168.1.15
88 10.10.10.5
67 172.16.1.4
55 8.8.8.8
42 1.1.1.1

Interview-Level Version

A slightly more polished script checks whether the log file exists before processing it:

#!/bin/bash

LOGFILE="access.log"

if [ ! -f "$LOGFILE" ]; then
    echo "Error: $LOGFILE not found!"
    exit 1
fi

echo "===== Top 10 Source IPs ====="

awk '{print $1}' "$LOGFILE" \
| sort \
| uniq -c \
| sort -nr \
| head -10
