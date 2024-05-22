#!/usr/local/bin/bash
# set -euxo pipefail 

export GREEN='\033[2;32m'
LGREEN='\033[0;92m'
RED='\033[0;31m'
BLUE='\033[0;36m'
BROWN='\033[0;33m'
YELLOW='\033[1;33m'
NC='\033[0m'

TREE="
                              .
                             .z.
                            .z.z.
                           .z.z.z.
                          .z.z.z.z.
                         .z.z.z.z.z.
                          .z.z.z.z.
                       .z.z.z.z.z.z.z.
                      .z.z.z.z.z.z.z.z.
                     .z.z.z.z.z.z.z.z.z.
                      .z.z.z.z.z.z.z.z.
                     .z.z.z.z.z.z.z.z.z.
                      .z.z.z.z.z.z.z.z.
                   .z.z.z.z.z.z.z.z.z.z.z.
                  .z.z.z.z.z.z.z.z.z.z.z.z.
                 .z.z.z.z.z.z.z.z.z.z.z.z.z.
                  .z.z.z.z.z.z.z.z.z.z.z.z.
                 .z.z.z.z.z.z.z.z.z.z.z.z.z.
                  .z.z.z.z.z.z.z.z.z.z.z.z.
               .z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.
              .z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.
             .z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.
              .z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.
             .z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.
              .z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.z.
                 ${BROWN}          |||||||
                           |||||||
                           |||||||${NC}
"


declare -A c=()
c["failed"]=$RED
c["panicked"]=$RED
c["passed"]=$LGREEN
c["pending"]=$BLUE
c["skipped"]=$YELLOW
c["timedout"]=$RED

#STATUS=$(cat report.json  | jq -r '.[0].SpecReports[] | .LeafNodeType +" "+ .State' | awk '/It/{print $2}')
STATUS=$(cat reports/report.json  | jq -r '.[0].SpecReports[] | if .ContainerHierarchyTexts then .ContainerHierarchyTexts |= join("_") else .ContainerHierarchyTexts = (.LeafNodeLocation.FileName + "_" + (.LeafNodeLocation.LineNumber | tostring) ) end ' | jq -s  | jq -r '[.[] | { test: (.ContainerHierarchyTexts + "__" + .LeafNodeText), state: .State, Msg: .Failure.Message, Out: .CapturedGinkgoWriterOutput, LeafNodeType: .LeafNodeType }] | sort_by(.test) | .[] | .LeafNodeType +" "+ .state' | awk '/It/{print $2}')
if [[ "$STATUS" == "" ]]; then
  echo  "No status was collected from test report."
  exit 0
fi

EERT=$(echo "$TREE" | tac)
  echo "$STATUS" | { while read p; do
    EERT=$(echo -e "$EERT" | sed '0,/z/s//\'"${c[$p]}\*\\${NC}"'/')
  done
TREE=$(echo "$EERT" | tac)

TREE=$(echo -e "$TREE" | sed 's/\./'"\\${GREEN}^\\${NC}"'/g')
TREE=$(echo -e "$TREE" | sed 's/z/*/g')

echo ""
echo -e "$TREE"
failed=$(echo "$STATUS" | grep "failed" | wc -l)
panicked=$(echo "$STATUS" | grep "panicked" | wc -l)
passed=$(echo "$STATUS" | grep "passed" | wc -l)
pending=$(echo "$STATUS" | grep "pending" | wc -l)
skipped=$(echo "$STATUS" | grep "skipped" | wc -l)
timedout=$(echo "$STATUS" | grep "timedout" | wc -l)
total=$(cat reports/report.json  | jq -r '.[0].PreRunStats.TotalSpecs')

let "tested = failed + panicked + passed + pending + timedout"
let "ptested = 100 * tested / total"
let "ppassed = 100 * passed / tested"
if [[ "$ppassed" == "" ]]; then
  ppassed = "0"
fi
let "ppassed_total = 100 * passed / total"

echo ""
RUN_TIME=$(cat reports/report.json  | jq -r '.[0].RunTime')

ELAPSED=$((RUN_TIME/1000000000))
ELAPSED=$(date -d@$ELAPSED -u +%H:%M:%S)
RUN_ON=$(date +"%Y-%m-%d %H:%M:%S")
echo " Time: $ELAPSED sec"
echo " Executed on: $RUN_ON"

echo -e " Execution Status: ${total} Total | ${c[passed]}${passed} Passed${NC} | ${c[failed]}${failed} Failed${NC} | ${c[panicked]}${panicked} Panicked${NC} | ${c[timedout]}${timedout} Timedout${NC} | ${c[pending]}${pending} Pending${NC} | ${c[skipped]}${skipped} Skipped${NC}"
echo -e " Summary: ${ptested}% Tested | ${ppassed}% Passed | ${ppassed_total}% Total Passed"
}

echo ""

REPORT=$(cat reports/results/failed_sorted_focused_report.json.nojson)
TOTAL=$(echo "$REPORT" | grep "Test:" | wc -l)
HIGHLY_LIKELY=$(echo "$REPORT" | grep "Highly likely tracked" | wc -l)
LIKELY=$(echo "$REPORT" | grep "Likely tracked" | wc -l)
PROBABLY=$(echo "$REPORT" | grep "Probably tracked" | wc -l)
HIGHLY_LIKELY_NOT=$(echo "$REPORT" | grep "Highly likely NOT tracked yet" | wc -l)

echo -e " Tracking Status: ${TOTAL} failures identified | ${RED}${HIGHLY_LIKELY_NOT} most likely NOT tracked${NC}"
echo -e " Tracked: ${LGREEN}${HIGHLY_LIKELY} highly likely${NC} | ${LGREEN}${LIKELY} likely${NC} | ${YELLOW}${PROBABLY} probably${NC} | ${RED}${HIGHLY_LIKELY_NOT} highly unlikely${NC}"

echo ""
