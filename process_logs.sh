#!/bin/bash
set -euo pipefail 

# set DEBUG to empty if not set
DEBUG="${DEBUG:-}"

LANG=C.UTF-8

GREEN='\033[2;32m'
LGREEN='\033[0;92m'
RED='\033[0;31m'
BLUE='\033[0;36m'
BROWN='\033[0;33m'
NC='\033[0m'

fail()
{
    echo >&2 '
***************
*** FAILED ***
***************
'
    echo "An error occurred. Exiting..." >&2
    exit 1
}

trap 'fail' 0
set -e

mkdir -p reports/results

cd reports

last_file=$(printf '%s\n' report.json* | sort -rV | head -n1)

cd results

function extract_title_and_filter_data() {
  infile=$1
  outfile=$2
  echo -e "Extracting test title and status from ${BROWN}${infile}${NC} to ${LGREEN}${outfile}${NC} ..."

  cat $infile | jq '.[0].SpecReports[] | if .ContainerHierarchyTexts then .ContainerHierarchyTexts |= join("_") else .ContainerHierarchyTexts = (.LeafNodeLocation.FileName + "_" + (.LeafNodeLocation.LineNumber | tostring) ) end ' \
  | jq -s  | jq '[.[] | { test: (.ContainerHierarchyTexts + "__" + .LeafNodeText ), state: .State, Msg: .Failure.Message, Out: .CapturedGinkgoWriterOutput}] | sort_by(.test)' > $outfile
}

function restore_newlines() {
  infile=$1
  outfile=$2
  echo -e "Restoring new lines from ${BROWN}${infile}${NC} to ${LGREEN}${outfile}${NC} ..."
  cat $infile | sed 's/\\n/\n/g' > $outfile
}

function filter_failed_and_panicked() {
  infile=$1
  outfile=$2
  echo -e "Filtering failed and panicked tests from ${BROWN}${infile}${NC} to ${LGREEN}${outfile}${NC} ..."
  cat $infile | jq '[.[] | select(.state == "failed" or .state == "panicked")]' > $outfile
}

extract_title_and_filter_data ../$last_file sorted_$last_file
restore_newlines sorted_$last_file sorted_$last_file.nojson

extract_title_and_filter_data ../report.json sorted_report.json

filter_failed_and_panicked sorted_$last_file failed_sorted_$last_file
filter_failed_and_panicked sorted_report.json failed_sorted_report.json

cp sorted_$last_file sorted_prev_report.json
cp failed_sorted_$last_file failed_sorted_prev_report.json


function readable_logs_piped() {
  sed "s,\\\u001b\[[0-9;]*[a-zA-Z],,g" \
  | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" \
  | sed 's/\\r/\n/g' \
  | sed 's/\\n/\n/g' \
  | sed 's/\\t/\t/g'
}
function readable_logs() {
  infile=$1
  outfile=$2
  echo -e "Transforming logs for readability from ${BROWN}${infile}${NC} to ${LGREEN}${outfile}${NC} ..."
  cat $infile | readable_logs_piped > $outfile
}

readable_logs sorted_report.json sorted_report.json.nojson

readable_logs sorted_prev_report.json sorted_prev_report.json.nojson

readable_logs failed_sorted_report.json failed_sorted_report.json.nojson

readable_logs failed_sorted_prev_report.json failed_sorted_prev_report.json.nojson

function mask_logs() {
  infile=$1
  outfile=$2
  echo -e "Masking random elements for easier comparison from ${BROWN}${infile}${NC} to ${LGREEN}${outfile}${NC} ..."
  cat $infile | mask_logs_piped > $outfile
}
function mask_logs_piped() {
  sed 's/\\t//g' \
  | sed 's/\.[0-9][0-9][0-9]s/.s.and_millis/g' \
  | sed 's/0x[a-z0-9]*/<hex>/g' \
  | sed 's/[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9]/<timestamp>/g' \
  | sed -E 's/[0-9]{2}:[0-9]{2}:[0-9]{2}/<timestamp>/g' \
  | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/<date>/g' \
  | sed 's/CATS-.*-APP-[a-z0-9]*/<app>/g' \
  | sed 's/CATS-.*-ORG-[a-z0-9]*/<org>/g' \
  | sed 's/CATS-.*-QUOTA-[a-z0-9]*/<quota>/g' \
  | sed 's/CATS-.*-BPK-[a-z0-9]*/<bpk>/g' \
  | sed 's/CATS-.*-SPACE-[a-z0-9]*/<space>/g' \
  | sed -E 's/[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/<guid>/g' \
  | sed 's/matching-buildpack[0-9]*/<matching-buildpack>/g' \
  | sed 's/buildpack_env[0-9]*/<buildpack_env>/g' \
  | sed -E 's/[*]{40}[*]+/******************************************/g' \
  | sed -E 's|/tmp/[0-9]+/manifest|/tmp/<number>/manifest|g' \
  | sed -E 's| .*B / [.0-9]+ .iB \[.*\]\s+[.0-9]+%\s*[0-9]*s?|<download>|g' \
  | sed -E 's/b1\.[0-9]+\.[0-9]+/<b1.number.number>/g' \
  | uniq
}

mask_logs sorted_report.json.nojson sorted_report.json.nojson.masked
mask_logs sorted_prev_report.json.nojson sorted_prev_report.json.nojson.masked

function prepare_for_search() {
  sed 's/\r//g' \
  | sed 's/[ \t]*$//' \
  | sed "s/[^@ ]*@[^@]*\.[^@ ]*/<user>.../g" \
  | sed 's/\[.*\]> *//g' \
  | sed '/^$/d'
}

function prepare_for_search_one_string() {
  prepare_for_search \
  | gsed -z 's/\n/,/g' 
}

# Download all issues with label CATS from github repo trinity of org unified-runtime of the github.tools.sap instance,
# each issue to be in a separate file, all files to be in a subfolder called issues
# all pages have to be downloaded, not just the first one
function download_issues() {
  mkdir -p issues
  # cleanup issues folder before downloading
  rm -rf issues/*
  PAGE=1
  
  while true; do
    URL="https://github.tools.sap/api/v3/repos/unified-runtime/trinity/issues?state=all&labels=CATS&page=$PAGE"
    echo "Downloading issues $URL"
    echo -n "Downloading issues: "
    while read -r p; do
      NUMBER=$(echo "$p" | jq .number -r)
      echo -n "$NUMBER,"
      curl -H "Authorization: Bearer $GITHUB_TOKEN" "https://github.tools.sap/api/v3/repos/unified-runtime/trinity/issues/$NUMBER" -s | jq . > issues/$NUMBER.json
    done < <(curl -H "Authorization: Bearer $GITHUB_TOKEN" "$URL" -s | jq -c '.[]')
    if [ $(curl -H "Authorization: Bearer $GITHUB_TOKEN" "$URL" -s | jq '. | length') -eq 0 ]; then
      echo "done"
      break
    fi
    echo "done"
    PAGE=$((PAGE+1))
  done
} 

function grep_issues_matching_test_spec() {
  # accept parameter for the FAILURE_MSG message
  TEST_SPEC=$1
  OUTFILE=$2
  if [ -n "$DEBUG" ]; then
    echo -e "Checking issues for test spec $TEST_SPEC..." | awk '{print "[DEBUG] [GREP_SPEC] " $0}' >> $OUTFILE
  fi
  for issue in issues/*; do
    BODY=$(cat $issue | jq .body -r | readable_logs_piped)
    if echo "$BODY" | grep -qF "$TEST_SPEC"; then
      echo -e "$(cat $issue | jq .html_url -r)"
    fi
  done
}

function grep_issues_matching_failure_msg() {
  FAILED_MSG=$1
  FAILED_MSG=$( echo "$FAILED_MSG" | sort | uniq )
  OUTFILE=$2
  for issue in issues/*; do
    BODY=$(cat $issue | jq .body -r | readable_logs_piped | mask_logs_piped | prepare_for_search | sort | uniq)
    
    # check if each and every line of FAILED_MSG exists in STATUS irrespective of the order of lines
    COMMON_LINES=$(echo "$BODY" | grep -xF "$FAILED_MSG" | sort | uniq);
    # if DEBUG is set, print the BODY, FAILED_MSG and COMMON_LINES
    DIFF=$(diff <(echo "$FAILED_MSG") <(echo "$COMMON_LINES")) 
    if [ -n "$DEBUG" ]; then
      echo -e "BODY:\n---\n$BODY\n---\nFAILED_MSG:\n---\n$FAILED_MSG\n---\nCOMMON_LINES:\n---\n$COMMON_LINES\n---\nDIFF:\n---\n$DIFF\n---\n" \
      | awk '{print "[DEBUG] [GREP_ERR] ['$issue'] " $0}' >> $OUTFILE
    fi
    # removing frequently met lines for the check
    COMMON_LINES_CHECK=$(echo "$COMMON_LINES" | grep -vx "[ ]*[{}][ ]*" | grep -vxF "Unexpected error:"  | grep -vxF "occurred" || true)

    if [ -n "$COMMON_LINES_CHECK" ]; then
      HTML_URL=$(cat $issue | jq .html_url -r)
      if [ "$DIFF" == "" ]; then
        # full hits
        echo -e "$HTML_URL"
      else 
        # partial hits
        echo -e "_$HTML_URL" 
        echo -e "Partial match in: $HTML_URL\n---\nCOMMON_LINES:\n---\n$COMMON_LINES\n---\nDIFF:\n---\n$DIFF\n---\n" \
        | awk '{print "[PARTIAL_MATCH] ['$issue'] " $0}' >> $OUTFILE
      fi
    fi  
  done
}

function search_issues_matching_test_spec() {
    TEST_REF=$1
    OUTFILE=$2
    Q="$TEST_REF type:issue repo:unified-runtime/trinity"
    Q=$(echo "$Q" | jq -sRr @uri)
    QURL="https://github.tools.sap/api/v3/search/issues?q=$Q"
    if [ -n "$DEBUG" ]; then
      echo "Checking $QURL" | awk '{print "[DEBUG] [SEARCH_SPEC] " $0}' >> $OUTFILE 
    fi  
    curl -H "Authorization: Bearer $GITHUB_TOKEN" "$QURL" -s | jq '.items[].html_url' -r | sort
}

function search_issues_matching_failure_msg() {
    MSG_REF=$1 
    OUTFILE=$2
    Q="$MSG_REF type:issue repo:unified-runtime/trinity"
    Q=$(echo "$Q" | jq -sRr @uri)
    QURL="https://github.tools.sap/api/v3/search/issues?q=$Q"
    if [ -n "$DEBUG" ]; then
      echo "Checking $QURL" | awk '{print "[DEBUG] [SEARCH_ERR] " $0}' >> $OUTFILE
    fi
    curl -H "Authorization: Bearer $GITHUB_TOKEN" "$QURL" -s | jq '.items[].html_url' -rc | sort
}

function analyze_matches() {
    SPEC_REF=$1
    MSG_REF=$2
    COMMON_HITS=$3
    SPEC_HITS=$4
    MSG_HITS=$5
    PARTIAL_MSG_HITS=$6
    outfile=$7
    LIKELY_TRACKED=$8
    
    if [ -n "$COMMON_HITS" ]; then
      echo -e "$LIKELY_TRACKED tracked in: ${COMMON_HITS}" >> $outfile
    else
      if [[ -n "$SPEC_HITS" ]] || [[ -n "$PARTIAL_MSG_HITS" ]] || [[ -n "$MSG_HITS" ]]; then
        echo -e "Probably tracked." >> $outfile
      fi
      if [ -n "$SPEC_HITS" ]; then
        echo -e "\nTest spec is reported but probably with different error message in: \n${SPEC_HITS}" >> $outfile
        echo -e "Error message searched for: \n${MSG_REF}" >> $outfile
        if [ -n "$PARTIAL_MSG_HITS" ]; then
          echo -e "\nPartially matching error message was found in: \n${PARTIAL_MSG_HITS}" >> $outfile
          echo -e "\nCheck the issues above and either adjust the error message or create new issue." >> $outfile
        else
          echo -e "\nCheck the issues above and either add the error message if fitting or create new issue." >> $outfile
        fi  
      else
        if [[ -n "$PARTIAL_MSG_HITS" ]] || [[ -n "$MSG_HITS" ]]; then
          echo "" >> $outfile
          echo -n "Check the issues above and consider adding the test spec to the issue " >> $outfile
        fi
        if [ -n "$PARTIAL_MSG_HITS" ]; then
          echo -e "and adjusting the error message if appropriate." >> $outfile
          echo -e "\nPartially matching error message was found in: \n${PARTIAL_MSG_HITS}" >> $outfile
          echo -e "but the following test spec was not found: \n${SPEC_REF}" >> $outfile
        fi
        if [ -n "$MSG_HITS" ]; then
          echo -e "if error matches." >> $outfile
          echo -e "\nSame or similar error message was found in: \n${MSG_HITS}" >> $outfile
          echo -e "but the following test spec was not found: \n${SPEC_REF}" >> $outfile
        fi
      fi
    fi
}
export IFS=

# we cannot rely on jq to properly unquote multiline strings, so we have to do it ourselves
function unquote_line () {
  sed 's/["]$//' | sed 's/^["]//'
}

function extract_failure_message() {
    p="$1"

    OUT=$(echo "$p" | jq '.Out' | unquote_line | readable_logs_piped | mask_logs_piped | uniq)

    SEARCH="FAILED"
    if [ $(echo "$OUT" | grep -c "FAILED" ) -eq 0 ]; then
      if [ $(echo "$OUT" | grep -c "errors" ) -eq 0 ]; then
        FAILED=$(echo "$p" | jq '.Msg' | unquote_line | readable_logs_piped | mask_logs_piped)
        SEARCH=""
      else
        SEARCH="errors"
      fi
    fi

    if [ "$SEARCH" != "" ]; then
    FAILED=$(echo "$OUT" | awk -v search="$SEARCH" '{
        lines[NR] = $0
        if ($0 ~ search && !found) {
            for(i=NR; i>=1; i--) {
                if(lines[i] == "" || i == 1) {
                    start = (lines[i] == "") ? i+1 : i
                    break
                }
            }
            for(i=NR; i<=NR+10; i++) {
                if(lines[i] == "" || i == NR+10) {
                    end = (lines[i] == "") ? i : i
                    break
                }
            }
            found++
        }
    }
    END {
        for(j=start; j<=end; j++) {
            print lines[j]
        }
    }' | sed 's/FAILED//g' )
    fi
    echo "$FAILED"
}

# define function that checks if the issues are closed and generates a recommendation for reopening
# it expects a list of issue numbers as input
function check_if_issues_are_closed() {
  while read -r issue_number; do
    if [ -z "$issue_number" ]; then
      continue
    fi
    issue=$(cat issues/$issue_number.json)
    state=$(echo "$issue" | jq .state -r)
    if [ "$state" == "closed" ]; then
      echo -e "[WARNING]: Issue $issue_number is closed. Consider reopening it." >> $outfile
    fi
  done
}

# define function that extracts the issue number from the issue URL using awk
function extract_issue_number() {
  issue_url=$1
  echo "$issue_url" | awk -F'/' '{print $NF}'
}

function focus_result() {
  infile=$1
  outfile=$2
  echo -e "Extracting errors from ${BROWN}${infile}${NC} to ${LGREEN}${outfile}${NC} ..."
  rm -rf $outfile
  cat $infile | jq '.[]' -rc | while read -r p; do

    TEST=$(echo "$p" | jq '.test' -r)
    FAILED=$(extract_failure_message "$p")

    echo -e "-------------------------------------------------------------------------------------" >> $outfile
    echo -e "Test: $TEST" >> $outfile
    echo "-------------------------------------------------------------------------------------" >> $outfile
    echo -e "$FAILED" >> $outfile
    echo -e "-------------------------------------------------------------------------------------" >> $outfile

    SPEC_REF=$(echo "$TEST" | sed 's/\[.*\]_/"/g' | sed 's/__/" and "/g' | sed 's/_/", "/g')
    SPEC_REF="$SPEC_REF\""
     
    MSG_REF=$(echo "$FAILED" | readable_logs_piped | prepare_for_search)
    if [ -n "$DEBUG" ]; then
      echo -e "Analyzing matches for test:\n$SPEC_REF\nand error:\n$MSG_REF\n..." | awk '{print "[DEBUG] " $0}' >> $outfile
    fi  
    echo -n "."
    
    SPEC_HITS=$(grep_issues_matching_test_spec "$SPEC_REF" $outfile | sort)
    MSG_HITS=$(grep_issues_matching_failure_msg "$MSG_REF" $outfile | sort)
    COMMON_HITS=$(comm -12 <( echo "$SPEC_HITS" ) <( echo "$MSG_HITS" ))
    # extract lines from MSG_HITS that start with "_" and remove the underscore
    PARTIAL_MSG_HITS=$(echo "$MSG_HITS" | grep "^_" | sed 's/^_//' || true)
    # extract lines from MSG_HITS that do not start with
    MSG_HITS=$(echo "$MSG_HITS" | grep -v "^_" || true)

    if [ -n "$DEBUG" ]; then
      echo -e "GREP RESULTS\nSPEC_HITS:\n---\n$SPEC_HITS\n---\nMSG_HITS:\n---\n$MSG_HITS\n---\nCOMMON_HITS:\n---\n$COMMON_HITS\n---\n" | awk '{print "[DEBUG] " $0}' >> $outfile
    fi

    analyze_matches "$SPEC_REF" "$MSG_REF" "$COMMON_HITS" "$SPEC_HITS" "$MSG_HITS" "$PARTIAL_MSG_HITS" "$outfile" "Highly likely" "Likely NOT"
    
    extract_issue_number "$COMMON_HITS" | check_if_issues_are_closed 
    
    
    if [[ -z "$SPEC_HITS" ]] && [[ -z "$MSG_HITS" ]] && [[ -z "$PARTIAL_MSG_HITS" ]]; then
      SPEC_HITS=$(search_issues_matching_test_spec "$SPEC_REF" $outfile | sort)
      MSG_REF=$(echo "$FAILED" | uniq | prepare_for_search_one_string | cut -c 1-250 )
      MSG_HITS=$(search_issues_matching_failure_msg "$MSG_REF" $outfile | sort)
      COMMON_HITS=$(comm -12 <( echo "$SPEC_HITS" ) <( echo "$MSG_HITS" ))
      analyze_matches "$SPEC_REF" "$MSG_REF" "$COMMON_HITS" "$SPEC_HITS" "$MSG_HITS" "" "$outfile" "Likely"
      if [[ -z "$SPEC_HITS" ]] && [[ -z "$MSG_HITS" ]]; then
        echo -e "Highly likely NOT tracked yet.\nConsider creating new issue for test spec:\n${SPEC_REF}." >> $outfile
      fi 
    fi
    echo -e "-------------------------------------------------------------------------------------\n\n" >> $outfile
  
    done
    echo "done"
}

download_issues
#download_issues 103

#focus_result failed_sorted_report.json.debug failed_sorted_focused_report.json.nojson.debug
focus_result failed_sorted_report.json failed_sorted_focused_report.json.nojson
focus_result failed_sorted_prev_report.json failed_sorted_prev_focused_report.json.nojson

# TODO 1: implement a check for all issues that are "Highly likely tracked in" if they point to an issue which is closed 
# and generate recommendation for reopening such issues

# TODO 2: implement an analysis of the exising CATS labeled issues which are opened and no failure was found that points to it
# and generate recommendation for closing such issues

trap : 0