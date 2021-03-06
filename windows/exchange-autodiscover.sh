#! /bin/bash
# [ 0x19e Networks ]
# tests exchange autodiscover
# dumps result or error to console

function print_usage()
{
 echo "Usage: $(basename "$0") [options]"
 echo "Options:"
 echo "  -e  Autodiscover Endpoint URL"
 echo "  -a  SMTP address of account to perform autodiscover"
 echo "  -u  user ID used when logging into the specified Autodiscover Endpoint"
 exit 2
}

function parse_args()
{
 if ! args=$(getopt u:e:a: "$@"); then
  print_usage
 fi

 # shellcheck disable=2086
 set -- $args
 while [ $# -gt 0 ]; do
  case "$1" in
   -e)
    autod_url="$2"; shift
    shift
    ;;
   -a)
    autod_email="$2"; shift
    shift
    ;;
   -u)
    autod_id="$2"; shift
    shift
    ;;
   --)
    shift
    break
    ;;
  esac
 done

 if [ -z "$autod_url" ] || [ -z "$autod_email" ]; then
  print_usage
 fi
 if [ -z "$autod_id" ]; then
  # print_usage
  autod_id="$(echo "${autod_email}" | awk -F'@' '{ print $1 }')"
 fi
}

function generate_autod_request_xml() {
 _email_address="$1"
 autod_xml="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Autodiscover xmlns=\"http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006\">
  <Request>
    <EMailAddress>$_email_address</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a</AcceptableResponseSchema>
  </Request>
</Autodiscover>
"
}

# check if curl command exists
hash curl 2>/dev/null || { echo >&2 "You need to install curl. Aborting."; exit 1; }

parse_args "$@"
generate_autod_request_xml "$autod_email"
xml="$autod_xml"

echo "Sending request for user '${autod_id}' to ${autod_url} ..."
if ! curl --fail --silent --show-error -k -b '' --header 'Content-Type: text/xml' --ntlm --user "$autod_id" "$autod_url" --data "$xml"; then
  echo >&2 "ERROR: Failed to connect to Exchange server '${autod_url}'."
  exit 1
fi

exit 0
