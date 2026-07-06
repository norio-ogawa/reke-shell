#!/bin/bash

FILE=/tmp/foo.json
export VERBOSE_FLAG=1

echo "# Run with the -h option."
rake -h

echo "# Run without options."
rake

echo "# Specify date/time and output file."
FROM=$(date +%Y-%m-%dT%H:%M:%S -d "now - 3minutes")
TO=$(date +%Y-%m-%dT%H:%M:%S -d "now - 2minutes")
rake -f $FROM -t $TO -o $FILE

echo "# Specify date/time format to second."
rake -f now-30s -t now -o $FILE

echo "# Specify date/time format to minute."
rake -f now-1m -t now-10s -o $FILE

echo "# Specify date/time format to hour."
rake -f now-1h -t now-50m -o $FILE

echo "# Specify date/time format to day."
rake -f now-1d -t now-23h -o $FILE

echo "# Specify date/time format to week."
rake -f now-1w -t now-6d -o $FILE

echo "# Specify date/time format to month."
rake -f now-1M -t now-29d -o $FILE

echo "# Specify the search string."
rake -m "SAS/TK is aborting" -o $FILE

echo "# Change the output to CSV format."
rake -f now-1m -c -o ${FILE}.csv

FROM=$(date +%Y-%m-%dT%H:%M:%S -d "now - 5minutes")
TO=$(date +%Y-%m-%dT%H:%M:%S -d "now - 1minutes")

echo "# Change TZ to Asia/Tokyo."
TZ=Asia/Tokyo rake -f $FROM -t $TO -d -o $FILE

echo "# Change TZ to Europe/London."
TZ=Europe/London rake -f $FROM -t $TO -d -o $FILE

echo "# The order of date and time specification is reversed."
rake -f now-5m -t now-10m

echo "# Specified file cannot be output."
rake -o /tmp/nodir/foo.json

echo "# Specified limit."
rake -o $FILE -l 1 -f now-1h

echo "# Incorrect date/time format."
rake -f noow
rake -t nooow
rake -f now-1x

echo "# Raise HTTP_STATUS:400 error."
rake -m '{"message": "error"}'

echo "# Get the wrong username on purpose."
rake -o $FILE -p xyz

echo "# Get the endpoints wrong on purpose."
rake -o $FILE -e http://osd.example.com

unset VERBOSE_FLAG
