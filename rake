#!/bin/bash -u

# Initialize variables
EXIT_CODE=0
FROM_OPT="now-5m"
TO_OPT="now"
MESSAGE_OPT=
OUT_OPT=
LIMIT_OPT=100
ENDPOINT_OPT=
USER_OPT=
PASSWD_OPT=
DEBUG_FLAG=0
CSV_FLAG=0
VERBOSE_FLAG=${VERBOSE_FLAG:-0}
CONFIG=~/.rake/config.json
CMD=$(basename $0)
export TMPDIR=$(mktemp -d /tmp/${CMD}.XXXXXX)
URL=
BASEURL=
API=
USER=
PASSWD=

# Handler when exit.
cleanup() {
    debugMsg "DEBUG: chelanup"

    if [ -d "$TMPDIR" ]; then
	/bin/rm -rf "$TMPDIR" > /dev/null 2>&1
    fi
}
trap cleanup EXIT

# Handler when interrupted by CTRL-C.
sigtrap() {
    echo " Ctrl-C detected. Cleaning temporary files.." 1>&2
    cleanup
    exit 1
}
trap sigtrap 2

# Show exit code
exitCode() {
   if [ $VERBOSE_FLAG -eq 1 ]; then
       if [ $1 -eq 0 ]; then
	   echo -e "\e[32mExit Code: ${1}\e[m"
       else
	   echo -e "\e[31mExit Code: ${1}\e[m"
       fi
   fi
}

# Function to display error messages.
errorMsg() {
    echo -e "\e[31mERROR:\e[m" $* 1>&2
}

# Function to display debug messages.
debugMsg() {
    if [ $DEBUG_FLAG -eq 0 ]; then
    	return
    fi
    echo $* 1>&2
}

# Function to display messages.
userMsg() {
    echo $* 1>&2
}

# Progress dot
progressMsg() {
    if [ $DEBUG_FLAG -eq 1 ]; then
	return
    fi

    if [ $# -eq 1 ]; then
	if [ $1 -eq 0 ]; then
	    echo -n "Processing." 1>&2
	else
	    echo -n "." 1>&2
	fi
    else
	echo "." 1>&2
    fi
}

# Add query pattern
addQueryPattern() {
    local file="$1"
    local queries
    local temp=$(mktemp)

    queries=$(cat << EOS
    .default+={queries:[
    "The system has encountered an unhandled Exception",
    "ObjectOptimisticLockingFailureException",
    "ODBC SQL Server Wire Protocol driver",
    "Error creating compute session",
    "Error stopping CAS session",
    "Child terminated by signal",
    "ServerOperationException",
    "OAuth token is expired",
    "Unable to launch node",
    "JobExecutionException",
    "Internal Server Error",
    "Operation timed out",
    "Unhandled Exception",
    "SAS/TK is aborting",
    "Java heap space",
    "out of memory",
    "OutOfMemory",
    "Unexpected",
    "SSL error",
    "Exception",
    "Failure",
    "killed",
    "panic",
    "OOM"
    ]}
EOS
)

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function addQueryPattern."
    	return 1
    fi

    jq -r --arg q "$queries" "$queries" "$file" > $temp
    if [ $? -ne 0 ]; then
	errorMsg "jq command returned error status in addQueryPattern}."
    	return 1
    fi

    mv -f $temp "$file"
    if [ $? -ne 0 ]; then
	errorMsg "mv command returned error status in addQueryPattern}."
    	return 1
    fi
}

# Check the configuration file and create a template file if it does not exist.
checkConfigFile() {
    local file="$1"
    local var
    local perm
    local -r endpoint="https://osd.example.com"
    local -r api="api/console/proxy"
    local -r passwd="blah-blah"

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function checkConfigFile."
    	return 1
    fi

    debugMsg "DEBUG: checkConfigFile $*"

    if [ ! -r "$file" ]; then
	errorMsg "File $file does not exist."
	userMsg "Edit the properties in the created $file file."

	if [ ! -d $(dirname "$file") ]; then
	    mkdir -p $(dirname "$file")
	fi
	printf '{"default":{"endpoint":"%s","api":"%s","user":"admin","passwd":"%s" }}' $endpoint $api $passwd | jq . > $file

	addQueryPattern "$file"
	chmod go-rwx "$file"
	ls -l "$file" 1>&2
	return 1
    fi

    for var in endpoint api user passwd
    do
    	jq -r --exit-status -r ".\"default\".\"${var}\"" "$file" > /dev/null
	if [ $? -ne 0 ]; then
	    errorMsg "Property ${var} is missing in ${file}."
	    return 1
	fi
    done

    perm=$(stat -c "%A" "$file")
    if [ "${perm:4:6}" != "------" ]; then
	errorMsg "Changed $file permissions to prevent access by other users."
	chmod go-rwx "$file"
	return 1
    fi
    return 0
}

# Check whether the commands can be used in the script.
checkCommand() {
    local cmd

    for cmd in curl jq date egrep
    do
	which $cmd > /dev/null
	if [ $? -ne 0 ]; then
	    errorMsg "Command '$cmd' not found."
	    return 1
	fi
    done
    return 0
}

# Function to validate the format of a date-time argument.
checkDateTimeFormat() {
    local dt=$1

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function checkDateTimeFormat."
    	return 1
    fi

    echo "$dt" | egrep -q '^(now|now-[0-9][0-9]*[smhdwMy])$'
    if [ $? -eq 0 ]; then
    	return 0
    fi

    date --utc +"%Y-%m-%dT%H:%M:%S.000Z" -d "$dt" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
	errorMsg "'$dt' date/time format is invalid."
    	return 1
    fi
    return 0
}

# Compares two datetimes and returns a value.
compareTimes() {
    if [ $# -ne 2 ]; then
	errorMsg "Invalid argument for function compareTimes."
	return 1
    fi

    checkDateTimeFormat $1 || return 1

    checkDateTimeFormat $2 || return 1

    if [[ $1 < $2 ]]; then
  	return 0
    fi
    return 1
}

# Convert the now-5m and date/time formats to UTC.
convertDateTimeFormat() {
    local dt="$1"
    local var

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function convertDateTimeFormat."
    	return 1
    fi

    checkDateTimeFormat $dt || return 1

    if [ $dt = "now" ]; then
	var="now"
    else
    	sym=${dt: -1}
	case ${sym} in
	  "s")
	    var=$(echo $dt | sed 's/s/seconds/');;
	  "m")
	    var=$(echo $dt | sed 's/m/minutes/');;
	  "h")
	    var=$(echo $dt | sed 's/h/hours/');;
	  "d")
	    var=$(echo $dt | sed 's/d/days/');;
	  "w")
	    var=$(echo $dt | sed 's/w$/weeks/');;
	  "M")
	    var=$(echo $dt | sed 's/M/months/');;
	  "y")
	    var=$(echo $dt | sed 's/y/years/');;
	  *)
	    var=$(date +%Y-%m-%dT%H:%M:%S%z -d "$dt")
	esac
    fi

    date --utc +"%Y-%m-%dT%H:%M:%S.000Z" -d $var
}

# Read the config file and set the environment variables for each property.
readConfigFile() {
    local file="$1"
    local -r profile="default"

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function readConfigFile."
    	return 1
    fi

    debugMsg "DEBUG: readConfigFile $*"

    if [ -n "$ENDPOINT_OPT" ]; then
	BASEURL="$ENDPOINT_OPT"
    else
	BASEURL=$(jq -r ".${profile}.\"endpoint\"" "$file")
    fi
    API=$(jq -r ".${profile}.\"api\"" "$file")
    URL="${BASEURL}/${API}?path=viya_logs-*/_search&method=GET"
    if [ -n "$USER_OPT" ]; then
	USER="$USER_OPT"
    else
	USER=$(jq -r ".${profile}.\"user\"" "$file")
    fi

    if [ -n "$PASSWD_OPT" ]; then
	PASSWD="$PASSWD_OPT"
    else
	PASSWD=$(jq -r ".${profile}.\"passwd\"" "$file")
    fi
}

# Perform a log search by specifying a period and a string(optional).
curlQuery() {
    local from="$1"
    local to="$2"
    local size=$3
    local text="$4"
    local json=$(mktemp --suffix .json)
    local binary=$(mktemp --suffix .json)
    local -r h1="osd-xsrf: osd-fetch"
    local -r h2="Content-Type: application/json"
    local code
    local match
    local range
    local body
    local stat

    if [ $# -ne 3 -a $# -ne 4 ]; then
	errorMsg "Invalid argument for function query."
	rm -f $json $binary > /dev/null 2>&1
    	return 1
    fi

    range=$(printf '"range":{"@timestamp":{"gte":"%s","lt":"%s"}}' $from $to)
    if [ -n "$text" ]; then
	match=$(printf '"should":[{"match_phrase":{"message":"%s"}}],"minimum_should_match":1' "$text")
	body=$(printf '"bool":{"must":[],"filter":[{"bool":{%s}},{%s}],"should":[],"must_not":[]}' "$match" "$range")
    else
	body="${range}"
    fi

    cat << EOS > $binary
{
  "size": ${size},
  "query": {
     ${body}
  },
  "_source": [
    "@timestamp",
    "level",
    "logsource",
    "kube.container",
    "kube.pod",
    "message",
    "properties.username",
    "kube.labels.launcher_sas_com/username",
    "kube.labels.launcher_sas_com/requested-by-client"
  ],
  "sort": [
    {
      "@timestamp": "asc"
    }
  ]
}
EOS

    code=$(curl -s -k "${URL}" -H "$h1" -H "$h2" --data-binary @${binary} -u "${USER}:${PASSWD}" -o $json -w '%{http_code}\n' -s)
    stat=$?
    if [ $stat -eq 0 ]; then
	if [ $code -eq 200 ]; then
	    jq -r '.hits.hits' $json
	elif [ $code -eq 400 ]; then
	    errorMsg "$code Bad Request, check endpoint and api in config.json."
	    userMsg "url: $BASEURL/$API"
	elif [ $code -eq 401 ]; then
	    errorMsg "$code Unauthorized, check username and password in config.json."
	elif [ $code -eq 403 ]; then
	    errorMsg "$code Forbidden, check username and password in config.json."
	elif [ $code -eq 404 ]; then
	    errorMsg "$code Not found, check endpoint and api in config.json."
	    userMsg "url: $BASEURL/$API"
	elif [ $code -eq 500 ]; then
	    errorMsg "$code Internal Server Error, check the OpenSearch serivce status."
	elif [ $code -eq 502 ]; then
	    errorMsg "$code Bad Gateway, check the OpenSearch service status."
	elif [ $code -eq 503 ]; then
	    errorMsg "$code Service Unavailable, check the OpenSearch service status."
	else
	    errorMsg "curl command returned HTTP status code ${code}."
	    userMsg "curl -s -k "${URL}" -H "$h1" -H "$h2" --data-binary @${binary} -u..."
	fi
	rm -f $json $binary > /dev/null 2>&1
	return $code
    elif [ $stat -eq 6 ]; then
	errorMsg "Check if the url value ${BASEURL}/${API} in config.json."
    else
    	errorMsg "CURL command exited with code ${stat}."
    fi
    rm -f $json $binary > /dev/null 2>&1
    return $stat
}

# Get the last timestamp from the JSON file.
getLastTimeStamp() {
    local json=$1

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function getLastTimeStamp."
    	return 1
    fi

    if [ ! -r $json ]; then
	errorMsg "Cannot read file ${json}."
    	return 1
    fi

    jq -r '.[-1: ][]._source."@timestamp"' $json
}

# Deletes records with the specified timestamp from the JSON file.
deleteLastTimeStamp() {
    local file="$1"
    local dt=$2

    if [ $# -ne 2 ]; then
	errorMsg "Invalid argument for function deleteLastTimeStamp."
    	return 1
    fi

    if [ ! -r "$file" ]; then
	errorMsg "Cannot read file ${file}."
    	return 1
    fi

    jq --arg dt $dt -r '.[]| select(._source."@timestamp"!=$dt)' "$file" | jq -s
}

# Returns the number of records in the JSON file.
countRecord() {
    local file="$1"

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function countRecord."
    	return 1
    fi

    if [ ! -r "$file" ]; then
	errorMsg "Cannot read file ${file}."
    	return 1
    fi

    jq -r '. | length' "$file"
}

# Add the record of argument 2 to the JSON file of argument 1.
appendJsonFile() {
    local file1=$1
    local file2=$2
    local temp=$(mktemp --suffix .json)

    if [ $# -ne 2 ]; then
	errorMsg "Invalid argument for function appendJsonFile."
	rm -f $temp > /dev/null 2>&1
    	return 1
    fi

    if [ ! -r $file1 ]; then
    	touch $file1
	if [ ! -r $file1 ]; then
	    errorMsg "Cannot read file ${file1}."
	    rm -f $temp > /dev/null 2>&1
	    return 1
	fi
    fi

    if [ ! -r $file2 ]; then
	errorMsg "Cannot read file ${file2}."
	rm -f $temp > /dev/null 2>&1
    	return 1
    fi

    jq -s add $file1 $file2 > $temp
    if [ $? -eq 0 ]; then
	mv $temp $file1
	if [ $? -ne 0 ]; then
	    errorMsg "Cannot move file ${temp} to ${file1}."
	    return 1
	fi
	return 0
    fi
    rm -f $temp > /dev/null 2>&1
    return 1
}

# Make a jq program to select fields and perform pattern matching.
makeJqProgram() {
    local file="$1"
    local awkpgm=$(mktemp)
    local temp=$(mktemp)
    local stat

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function makeJqProgram."
    	return 1
    fi

    debugMsg "DEBUG: makeJqProgram $*"

    if [ ! -r "$file" ]; then
	errorMsg "Cannot read file ${file}."
	return 1
    fi

    cat << 'EOS' > $awkpgm
    BEGIN {
	h = ""
	print ".[]|{"
	print "_index:._index,"
	print "_id:._id,"
	print "\"@timestamp\":._source.\"@timestamp\","
	print "year: ._source.\"@timestamp\"[:4],"
	print "month:._source.\"@timestamp\"[5:7],"
	print "day:._source.\"@timestamp\"[8:10],"
	print "hour:._source.\"@timestamp\"[11:13],"
	print "minute:._source.\"@timestamp\"[14:16],"
	print "sencond:._source.\"@timestamp\"[17:19],"
	print "logsource:._source.logsource,"
	print "level:._source.level,"
	print "pod:._source.kube.pod,"
	print "container:._source.kube.container,"
	print "message:._source.message,"
	print "username:._source.properties.username,"
	print "\"launcher_sas_com/requested-by-client\":._source.kube.labels.\"launcher_sas_com/requested-by-client\","
	print "\"launcher_sas_com/username\":._source.kube.labels.\"launcher_sas_com/username\","
	print "check:null,"
	print "pattern:null,"
	print "sort:.sort[]} |"
    }
    {
	printf("%sif([.message]|contains([%s])) then . +{check:%d, pattern: %s}\n",h,$0,NR,$0);h="el"
    }
    END {
	print "else . +{query:null,pattern:null} end"
    }
EOS

    # Extract matching patterns from config.json.
    jq '.default.queries[]' "$file" > $temp
    stat=$?
    if [ $stat -ne 0 ]; then
	errorMsg "jq command returned status ${stat} in makeJqProgram."
	return 1
    fi

    # Generate a jq program using awk.
    awk -f $awkpgm $temp
    stat=$?
    if [ $stat -ne 0 ]; then
	errorMsg "awk command returned status ${stat} in makeJqProgram."
	return 1
    fi
    return 0
}

# Format OpenSearch results for easy import into Excel.
jsonFilter() {
    local file="$1"
    local jqpgm=$(mktemp)
    local jqerr=$(mktemp)
    local stat

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function jsonFilter."
    	return 1
    fi

    if [ ! -r "$file" ]; then
	errorMsg "Cannot read file ${file}."
    	return 1
    fi

    # Make a jq program to select fields and perform pattern matching.
    makeJqProgram $CONFIG > $jqpgm
    if [ $? -ne 0 ]; then
    	return 1
    fi

    # Select fields and perform pattern matching.
    jq -f $jqpgm "$file" 2> $jqerr | jq -s
    stat=$?

    if [ $DEBUG_FLAG -eq 1 ]; then
	cp $jqpgm /tmp/debug.jq
	cp $file /tmp/debug.json
	echo "#!/bin/sh" > /tmp/debug.sh
	echo "jq -f /tmp/debug.jq /tmp/debug.json" >> /tmp/debug.sh
    fi

    if [ $stat -eq 0 ]; then
    	if [ ! -s $jqerr ]; then
	    return 0
	fi
    fi
    return 1
}

# Format OpenSearch results for easy import into Excel.
csvFilter() {
    local file="$1"
    local filter

    if [ $# -ne 1 ]; then
	errorMsg "Invalid argument for function csvFilter."
    	return 1
    fi

    if [ ! -r "$file" ]; then
	errorMsg "Cannot read file ${file}."
    	return 1
    fi

    filter=$(cat << 'EOS'
["_index","_id","@timestamp","year","month","day","hour","minute","sencond","logsource",
"level","pod","container","message","username","launcher_sas_com/requested-by-client",
"launcher_sas_com/username","check","pattern","sort"],(.[]|map(.))|@csv
EOS
)

    jq -r "$filter" "$file"
}

# Format OpenSearch results for debug.
dummyFilter() {
    local file="$1"

    cat "$file"
}

# Run OpenSearch queries.
runQuery() {
    local from=$(convertDateTimeFormat $1)
    local to=$(convertDateTimeFormat $2)
    local filter="$3"
    local message="$4"
    local query=$(mktemp --suffix .query.json)
    local result=$(mktemp --suffix .result.json)
    local temp=$(mktemp --suffix .temp.json)
    local count
    local last
    local i=0
    local status=4

    # Check and read the config file.
    checkConfigFile $CONFIG || return 2
    readConfigFile $CONFIG || return 3

    debugMsg "DEBUG: runQuery $*"

    # Set the query extraction limit to zero and execute for test.
    curlQuery $from $to 0 "$message" > $query
    if [ $? -ne 200 ]; then
        return $status
    fi

    # Repeat the OpenSearch query for the specified period.
    compareTimes $from $to
    while [ $? -eq 0 ];
    do
	progressMsg $i
    	curlQuery $from $to 10000 "$message" > $query
	if [ "$?" != "200" ]; then
	    break
	fi
	i=$(expr $i + 1)

	count=0
	count=$(countRecord $query)
	last=$(getLastTimeStamp $query)
	debugMsg "DEBUG: i=$(printf '%04d' $i) count=$(printf '%05d' $count) from=$from to=$to"

	if [ $count -eq 0 -o "$last" == "$from" ]; then
	    progressMsg
	    appendJsonFile $result $query
	    status=0
	    break 
	fi

	# Remove the date and time of the last timestamp.
	deleteLastTimeStamp $query $last > $temp

	# Add to the results data set.
	appendJsonFile $result $temp

	from=$last
	if [ $i -ge $LIMIT_OPT ]; then
	    errorMsg "API call limit of $LIMIT_OPT has been reached"
	    break;
	fi

	compareTimes $from $to
    done

    if [ $status -eq 0 ]; then
	$filter $result
    fi
    return $status
}

# Main
runCommand() {
    local file
    local count=0
    local temp=$(mktemp)
    local stat

    if [ $CSV_FLAG -eq 1 ]; then
	file=/tmp/${CMD}.$(date +%Y%m%d.%H%M%S).csv
    else
	file=/tmp/${CMD}.$(date +%Y%m%d.%H%M%S).json
    fi

    if [ -n "$OUT_OPT" ]; then
    	file="$OUT_OPT"
    fi

    runQuery $FROM_OPT $TO_OPT jsonFilter "$MESSAGE_OPT" > "$file"
    stat=$?
    if [ $stat -eq 0 ]; then
	count=$(jq length "$file")

    	if [ $CSV_FLAG -eq 1 ]; then
	    csvFilter "$file" > $temp
	    mv $temp "$file"
	fi
    	userMsg "Extracted ${count} logs from the range $FROM_OPT to $TO_OPT."
	userMsg "Saved the logs in the following file."
	userMsg "$(ls -l $file)"
	return 0
    else
	return $stat
    fi
}

# Function to display usage
usage() {
  echo "Usage: $CMD [options]"
  echo ""
  echo "Options:"
  echo "  -f <time>    Specify the start time (e.g., now-5m)"
  echo "  -t <time>    Specify the end time (e.g., now)"
  echo "  -m <message> Filter by message content (e.g., \"error\")"
  echo "  -o <file>    Write output to <file> instead of default"
  echo "  -l <N>       Limit on the number of API calls"
  echo "  -u <user>    User"
  echo "  -p <passwd>  Password"
  echo "  -e <url>     Endpoint of OpenSearch"
  echo "  -c           Output in CSV format"
  echo "  -d           Enable debug mode"
  echo "  -h           Display this help message"
  echo ""
  echo "Examples:"
  echo "  $CMD -f now-5m -t now"
  echo "  $CMD -m \"SAS/TK is aborting\""
  echo "  $CMD -c -o foo.csv"
  echo "  $CMD -d"
  echo "  $CMD -h" 
  echo ""
}

# Parse options
ORGARG="$*"
while getopts ":f:t:m:o:l:p:e:cdhv" opt; do
  case ${opt} in
    f )
      FROM_OPT=$OPTARG
      ;;
    t )
      TO_OPT=$OPTARG
      ;;
    o )
      OUT_OPT=$OPTARG
      ;;
    m )
      MESSAGE_OPT=$OPTARG
      ;;
    e )
      ENDPOINT_OPT=$OPTARG
      ;;
    u )
      USER_OPT=$OPTARG
      ;;
    p )
      PASSWD_OPT=$OPTARG
      ;;
    l )
      LIMIT_OPT=$OPTARG
      ;;
    c )
      CSV_FLAG=1
      ;;
    d )
      DEBUG_FLAG=1
      ;;
    v )
      VERBOSE_FLAG=1
      ;;
    h )
      usage
      EXIT_CODE=1
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      usage
      EXIT_CODE=2
      ;;
    : )
      echo "Invalid option: -$OPTARG requires an argument" 1>&2
      usage
      EXIT_CODE=2
      ;;
  esac
done
shift $((OPTIND -1))

if [ $VERBOSE_FLAG -eq 1 ]; then
    userMsg "${CMD} $ORGARG"
fi

checkBeforeRun() {
    if [ $EXIT_CODE -ne 0 ]; then
	return 1
    fi

    # Check whether the commands can be used in the script.
    checkCommand
    if [ $? -ne 0 ]; then
    	EXIT_CODE=9
	return 1
    fi

    # Check Date/Time format.
    convertDateTimeFormat $FROM_OPT  > /dev/null
    if [ $? -ne 0 ]; then
    	EXIT_CODE=2
	return 1
    fi
    convertDateTimeFormat $TO_OPT  > /dev/null
    if [ $? -ne 0 ]; then
    	EXIT_CODE=2
	return 1
    fi

    # Check date order
    compareTimes $(convertDateTimeFormat $FROM_OPT) $(convertDateTimeFormat $TO_OPT)
    if [ $? -ne 0 ]; then
	errorMsg "from: $FROM_OPT and to: $TO_OPT values are reversed."
    	EXIT_CODE=2
	return 1
    fi

    # Check linit
    if [[ "$LIMIT_OPT" =~ ^[0-9]+$ ]]; then
        true
    else
	errorMsg "'$LIMIT_OPT' is not a number."
    	EXIT_CODE=2
	return 1
    fi

    # Test if file creation is possible
    if [ -n "$OUT_OPT" ]; then
	touch "$OUT_OPT" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
	    errorMsg "Cannot create file ${OUT_OPT}."
	    EXIT_CODE=2
	    return 1
	fi
    fi
    return 0
}

checkBeforeRun

if [ $EXIT_CODE -eq 0 ]; then
    runCommand
    EXIT_CODE=$?
fi

exitCode $EXIT_CODE
exit $EXIT_CODE
