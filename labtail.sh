#!/usr/bin/env bash

set -euo pipefail

NEED_NEWLINE='false'
PREV_LINE='xyz'

getdate() {
  date '+%H:%M:%S'
}

BEGIN_EPOCH="$(date '+%s')"

PUSH_MODE='false'
if [[ "$#" == "1" ]]; then
  if [[ "$1" == "--push" ]]; then
    echo "PUSH_MODE enabled"
    PUSH_MODE='true'
  fi
fi

if ! command -v glab >/dev/null 2>&1
then
    echo "command 'glab' not found. Please install it from:"
    echo "https://docs.gitlab.com/editor_extensions/gitlab_cli/"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1
then
    echo "command 'jq' not found. Please install it from:"
    echo "https://jqlang.org/"
    echo 'Or just google/duckduck it for your distro'
    exit 1
fi

if ! command -v git >/dev/null 2>&1
then
    echo "command 'git' not found. Please install it."
    exit 1
fi

log_status() {
  if [[ "$PREV_LINE" == "$1" ]]; then
    NOW_EPOCH="$(date '+%s')"
    WAITED="$((NOW_EPOCH-BEGIN_EPOCH))"
    if [[ "$PUSH_MODE" == "true" ]]; then
      FILE_CHANGE_COUNT="$(git status --porcelain=v1 2>/dev/null | grep -v "^??" | wc -l | sed 's/[^0-9]//g' || true )"
      if [[ "$FILE_CHANGE_COUNT" != "0" ]]; then
        printf "\r$(getdate) $1 waited ${WAITED} seconds. "
        if [[ "$FILE_CHANGE_COUNT" == "1" ]]; then
          printf "Pushing %s git change ...\n" "${FILE_CHANGE_COUNT}"
        else
          printf "Pushing %s git changes ...\n" "${FILE_CHANGE_COUNT}"
        fi
        git commit -am "wip"
        git push
        NEED_NEWLINE='false'
      else
        printf "\r$(getdate) $1 waited ${WAITED} seconds (no git changes)"
        NEED_NEWLINE='true'
      fi
    else
      printf "\r$(getdate) $1 waited ${WAITED} seconds"
      NEED_NEWLINE='true'
    fi
  else
    PREV_LINE="$1"
    BEGIN_EPOCH="$(date '+%s')"
    if [[ "$NEED_NEWLINE" == "true" ]]; then
      printf "\n"
      echo -e -n "$(getdate) $1 waited 0 seconds"
      NEED_NEWLINE='true'
    else
      echo -e -n "$(getdate) $1 waited 0 seconds"
      NEED_NEWLINE='true'
    fi
  fi
}

log_info() {
  if [[ "$NEED_NEWLINE" == "true" ]]; then
    printf "\n%s\n" "$(getdate) $1"
  else
    printf "%s\n" "$(getdate) $1"
  fi
  PREV_LINE='xyz'
  NEED_NEWLINE='false'
}

log_error() {
  if [[ "$NEED_NEWLINE" == "true" ]]; then
    printf "\n\e[31m%s\e[0m\n" "$(getdate) ERROR $1"
  else
    printf "\e[31m%s\e[0m\n" "$(getdate) ERROR $1"
  fi
  PREV_LINE='xyz'
  NEED_NEWLINE='false'
}

log_ok() {
  if [[ "$NEED_NEWLINE" == "true" ]]; then
    printf "\n\e[32m%s\e[0m\n" "$(getdate) INFO $1"
  else
    printf "\e[32m%s\e[0m\n" "$(getdate) INFO $1"
  fi
  PREV_LINE='xyz'
  NEED_NEWLINE='false'
}

GLAB_EXIT_CODE=''
GLAB_OUTPUT=''

get_glab_output() {
  set +e
  GLAB_OUTPUT="$( bash -c 'glab ci get --output json 2>&1' )"
  GLAB_EXIT_CODE="$?"
  set -e
  if [[ "${GLAB_EXIT_CODE}" == "0" ]]; then
    :
  elif [[ "$GLAB_OUTPUT" == *"ERROR: no open merge request available for"* ]]; then
    GLAB_OUTPUT='{}'
  elif [[ "$GLAB_OUTPUT" == *"No pipelines running or available on branch"* ]]; then
    GLAB_OUTPUT='{}'
  elif [[ "$GLAB_OUTPUT" == *"connect: connection refused"* ]]; then
    GLAB_OUTPUT='{}'
  elif [[ "$GLAB_OUTPUT" == *"error connecting to"* ]]; then
    GLAB_OUTPUT='{}'
  else
    log_error "Unexpected exit code ${GLAB_EXIT_CODE} stdout/stderr was: ${GLAB_OUTPUT}"
    exit "${GLAB_EXIT_CODE}"
  fi
}

LAST_PIPELINE_ID='INIT'
LAST_TRACED_JOB_ID='INIT'

maybe_trace_job() {
  PIPELINE="$1"
  if [[ "[]" == "$(echo "${PIPELINE}" | jq -r '.jobs')" ]]; then
    log_error "should not happen"
    exit 1
  else
    JOB_ID="$(echo "${PIPELINE}" | jq -r '.jobs[-1].id')"
    JOB_URL="$( echo "${PIPELINE}" | jq -r '.jobs[-1].web_url')"
    if [[ "$LAST_TRACED_JOB_ID" == "$JOB_ID" ]]; then
      :
    elif [[ "${JOB_ID}" == "null" ]]; then
      log_error "jobs.id is null, cannot trace log"
      sleep 1
    else
      log_info "tracing job ${JOB_ID} ..."
      log_info "aka ${JOB_URL}"
      glab ci trace "${JOB_ID}" || true
      LAST_TRACED_JOB_ID="$JOB_ID"
    fi
  fi
}

while true; do
  get_glab_output
  PIPELINE="$( echo "$GLAB_OUTPUT" | { jq -r '.' 2>/dev/null || echo '{}'; })"
  PIPELINE_ID="$(echo "${PIPELINE}" | jq -r '.id')"
  if [[ "${PIPELINE_ID}" == "${LAST_PIPELINE_ID}" ]]; then
    log_status "waiting for new pipeline ..."
    sleep 1
  elif [[ "${PIPELINE_ID}" == 'null' ]]; then
    log_status "waiting for new pipeline ..."
    sleep 1
  else
    LAST_PIPELINE_ID="${PIPELINE_ID}"
    while true; do
      get_glab_output
      PIPELINE="$( echo "$GLAB_OUTPUT" | { jq -r '.' 2>/dev/null || echo '{}'; })"
      PIPELINE_ID="$(echo "${PIPELINE}" | jq -r '.id')"
      PIPELINE_STATUS="$(echo "${PIPELINE}" | jq -r '.status')"
      JOB_ID="$(echo "${PIPELINE}" | jq -r '.jobs[-1].id')"
      JOB_URL="$( echo "${PIPELINE}" | jq -r '.jobs[-1].web_url')"

      if [[ "${PIPELINE_ID}" == "${LAST_PIPELINE_ID}" ]]; then
        if [[ "[]" == "$(echo "${PIPELINE}" | jq -r '.jobs')" ]]; then
          log_status "waiting for new job for pipeline ${PIPELINE_ID} ..."
          sleep 1
        elif [[ "null" == "$(echo "${PIPELINE}" | jq -r '.jobs[-1].id')" ]]; then
          log_status "waiting for new job for pipeline ${PIPELINE_ID} ..."
          sleep 1
        elif [[ "${PIPELINE_STATUS}" == "running" ]]; then
          log_status "waiting for pipeline ${PIPELINE_ID} (\e[1;35m${PIPELINE_STATUS}\e[0m) to finish ..."
          maybe_trace_job "$PIPELINE"
        elif [[ "${PIPELINE_STATUS}" == "pending" ]]; then
          log_status "waiting for pipeline ${PIPELINE_ID} (\e[1;33m${PIPELINE_STATUS}\e[0m) to finish ..."
          sleep 1
        elif [[ "${PIPELINE_STATUS}" == "null" ]]; then
          sleep 1
        elif [[ "${PIPELINE_STATUS}" == "skipped" ]]; then
          log_status "waiting for new pipeline ..."
        elif [[ "${PIPELINE_STATUS}" == "failed" ]]; then
          maybe_trace_job "$PIPELINE"
          log_error "pipeline ${PIPELINE_ID} with job ${JOB_ID} failed"
          log_error "failed job URL is ${JOB_URL}"
#            printf '\033[3J' # clear scrollback
#            printf '\033[2J' # clear whole screen without moving the cursor
#            printf '\033[H' # move cursor to top left of the screen
#            log_error "pipeline ${PIPELINE_ID} failed, dumping logs:"
#            JOB_ID="$(echo "${PIPELINE}" | jq -r '.jobs[-1].id')"
#            if [[ "${JOB_ID}" == "null" ]]; then
#              log_error "jobs.id is null, cannot dump logs"
#            else
#              glab ci trace "${JOB_ID}" || true
#              JOB_URL="$( echo "$GLAB_OUTPUT" | jq -r '.jobs[-1].web_url')"
#              log_error "last job is ${JOB_URL}"
#            fi
            break
          fi
        elif [[ "${PIPELINE_STATUS}" == "success" ]]; then
#          printf '\033[3J' # clear scrollback
#          printf '\033[2J' # clear whole screen without moving the cursor
#          printf '\033[H' # move cursor to top left of the screen
          maybe_trace_job "$PIPELINE"
          log_info "pipeline ${PIPELINE_ID} with job ${JOB_ID} succeeded"
          log_info "succeeded job URL is ${JOB_URL}"
          break
        else
          log_error "unhandled pipeline status '${PIPELINE_STATUS}'"
          sleep 1
        fi
      else
        log_info "pipeline changed to ${PIPELINE_ID}"
        break
      fi
    done
  fi
done
