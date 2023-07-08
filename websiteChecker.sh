!/bin/bash

# websiteChecker
# https://www.baeldung.com/linux/check-website-availablilty

trap "exit 1" TERM
export TOP_PID=$$
STDOUTFILE=".tempCurlStdOut" # temp file to store stdout
> $STDOUTFILE # cleans the file content

# Argument parsing follows our specification
for i in "$@"; do
  case $i in
    http*)
      WEBPAGE="${i#*=}"
      shift
      ;;
    -n=*|--notWantedContent=*)
      NOTWANTEDCONTENT="${i#*=}"
      shift
      ;;
    -r=*|--requiredContent=*)
      REQUIREDCONTENT="${i#*=}"
      shift
      ;;
    -e=*|--email=*)
      EMAIL="${i#*=}"
      shift
      ;;
    -s|--silent)
      SILENT=true
      shift
      ;;
    *)
      >&2 echo "Unknown option: $i" # stderr
      exit 1
      ;;
    *)
      ;;
  esac
done

if test -z "$WEBPAGE"; then
    >&2 echo "Missing required URL" # stderr
    exit 1;
fi

function stdOutput { 
    if ! test "$SILENT" = true; then
        echo "$1"
    fi
}

function stdError { 
    if ! test "$SILENT" = true; then
        >&2 echo "$1" # stderr
    fi
    if ! test -z "$EMAIL"; then
        echo -e "Subject: $WEBPAGE is not working\n\nThe error is: $1" | msmtp $EMAIL
    fi
    kill -s TERM $TOP_PID # abort the script execution
}

if ping -q -w 1 -c 1 8.8.8.8 > /dev/null 2>&1; then
    stdOutput "Internet connectivity OK"
    HTTPCODE=$(curl --max-time 5 --silent --write-out %{response_code} --output "$STDOUTFILE" "$WEBPAGE")
    CONTENT=$(<$STDOUTFILE) # if there are no errors, this is the HTML code of the web page
    if test $HTTPCODE -eq 200; then
        stdOutput "HTTP STATUS CODE $HTTPCODE -> OK"
    else
        stdError "HTTP STATUS CODE $HTTPCODE -> Has something gone wrong?"
    fi
    if ! test -z "$NOTWANTEDCONTENT"; then
        if echo "$CONTENT" | grep -iq "$NOTWANTEDCONTENT"; then # case insensitive check
            stdError "Not wanted content '$NOTWANTEDCONTENT'"
        fi
    fi
    if ! test -z "$REQUIREDCONTENT"; then
        if ! echo "$CONTENT" | grep -iq "$REQUIREDCONTENT"; then # case insensitive check
            stdError "Required content '$REQUIREDCONTENT' is absent"
        fi
    fi
    if echo "$WEBPAGE" | grep -iq "https"; then # case insensitive check
        EXPIREDATE=$(curl --max-time 5 --verbose --head --stderr - "$WEBPAGE" | grep "expire date" | cut -d":" -f 2- | date -f - "+%s")
        DAYS=$(( ($EXPIREDATE - $(date "+%s")) / (60*60*24) )) # days remaining to expiration
        if test $DAYS -gt 7; then
            stdOutput "No need to renew the SSL certificate. It will expire in $DAYS days."
        else
            if test $DAYS -gt 0; then
                stdError "The SSL certificate should be renewed as soon as possible ($DAYS remaining days)."
            else
                stdError "The SSL certificate IS ALREADY EXPIRED!"
            fi
        fi
    fi
else
    >&2 echo "Internet connectivity not available" #stderr
    exit 1
fi
