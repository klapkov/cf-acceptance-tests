#!/usr/bin/env python3

import json
import subprocess
import datetime
import re

GREEN = '\033[2;32m'
LGREEN = '\033[0;92m'
RED = '\033[0;31m'
BLUE = '\033[0;36m'
BROWN = '\033[0;33m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

TREE = """
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
                 {}          |||||||
                           |||||||
                           |||||||{}
""".format(BROWN, NC)

c = {
    "failed": RED,
    "panicked": RED,
    "passed": LGREEN,
    "pending": BLUE,
    "skipped": YELLOW,
    "timedout": RED
}

def get_status():
    cmd = (
        "cat reports/report.json | jq -r '.[0].SpecReports[] | "
        "if .ContainerHierarchyTexts then .ContainerHierarchyTexts |= join(\"_\") else "
        ".ContainerHierarchyTexts = (.LeafNodeLocation.FileName + \"_\" + "
        "(.LeafNodeLocation.LineNumber | tostring)) end' | jq -s | "
        "jq -r '[.[] | { test: (.ContainerHierarchyTexts + \"__\" + .LeafNodeText), "
        "state: .State, Msg: .Failure.Message, Out: .CapturedGinkgoWriterOutput, "
        "LeafNodeType: .LeafNodeType }] | sort_by(.test) | .[] | "
        ".LeafNodeType +\" \"+ .state' | awk '/It/{print $2}'"
    )
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip()

STATUS = get_status()

if not STATUS:
    print("No status was collected from test report.")
    exit(0)

EERT = '\n'.join(reversed(TREE.splitlines()))

for p in STATUS.splitlines():
    EERT = re.sub('z', f'{c.get(p, "")}*{NC}', EERT, 1)

TREE = '\n'.join(reversed(EERT.splitlines()))
TREE = TREE.replace('.', f'{GREEN}^{NC}')
TREE = TREE.replace('z', '*')

print("")
print(TREE)

def count_status(status):
    return STATUS.splitlines().count(status)

failed = count_status("failed")
panicked = count_status("panicked")
passed = count_status("passed")
pending = count_status("pending")
skipped = count_status("skipped")
timedout = count_status("timedout")

cmd_total = "cat reports/report.json | jq -r '.[0].PreRunStats.TotalSpecs'"
total = int(subprocess.run(cmd_total, shell=True, capture_output=True, text=True).stdout.strip())

tested = failed + panicked + passed + pending + timedout
ptested = 100 * tested / total if total else 0
ppassed = 100 * passed / tested if tested else 0
ppassed_total = 100 * passed / total if total else 0

print("")
cmd_runtime = "cat reports/report.json | jq -r '.[0].RunTime'"
RUN_TIME = int(subprocess.run(cmd_runtime, shell=True, capture_output=True, text=True).stdout.strip())

ELAPSED = str(datetime.timedelta(seconds=RUN_TIME // 1000000000))
RUN_ON = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
print(f" Time: {ELAPSED} sec")
print(f" Executed on: {RUN_ON}")

print(f" Execution Status: {total} Total | {LGREEN}{passed} Passed{NC} | {RED}{failed} Failed{NC} | {RED}{panicked} Panicked{NC} | {RED}{timedout} Timedout{NC} | {BLUE}{pending} Pending{NC} | {YELLOW}{skipped} Skipped{NC}")
print(f" Summary: {ptested:.2f}% Tested | {ppassed:.2f}% Passed | {ppassed_total:.2f}% Total Passed")

print("")

cmd_report = "cat reports/results/failed_sorted_focused_report.json.nojson"
REPORT = subprocess.run(cmd_report, shell=True, capture_output=True, text=True).stdout

TOTAL = REPORT.count("Test:")
HIGHLY_LIKELY = REPORT.count("Highly likely tracked")
LIKELY = REPORT.count("Likely tracked")
PROBABLY = REPORT.count("Probably tracked")
HIGHLY_LIKELY_NOT = REPORT.count("Highly likely NOT tracked yet")

print(f" Tracking Status: {TOTAL} failures identified | {RED}{HIGHLY_LIKELY_NOT} most likely NOT tracked{NC}")
print(f" Tracked: {LGREEN}{HIGHLY_LIKELY} highly likely{NC} | {LGREEN}{LIKELY} likely{NC} | {YELLOW}{PROBABLY} probably{NC} | {RED}{HIGHLY_LIKELY_NOT} highly unlikely{NC}")

print("")

