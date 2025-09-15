#!/usr/bin/env bash

set -euo pipefail
trap 'rm -rf -- "$MYTMPDIR"' EXIT
MYTMPDIR="$(mktemp -d)"

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
  elif [[ "$GLAB_OUTPUT" == *"connect: operation timed out"* ]]; then
      GLAB_OUTPUT='{}'
  elif [[ "$GLAB_OUTPUT" == *"error connecting to"* ]]; then
    GLAB_OUTPUT='{}'
  elif [[ "$GLAB_OUTPUT" == *"i/o timeout"* ]]; then
    GLAB_OUTPUT='{}'
  else
    log_error "Unexpected exit code '${GLAB_EXIT_CODE}' from 'glab ci get --output json'. Stdout/stderr was: ${GLAB_OUTPUT}"
    exit "${GLAB_EXIT_CODE}"
  fi
}

LAST_PIPELINE_ID='INIT'
LAST_PIPELINE_STATUS='INIT'

maybe_trace_job() {
  PIPELINE="$1"
  if [[ "[]" == "$(echo "${PIPELINE}" | jq -r '.jobs')" ]]; then
    log_error "'.jobs' is an empty array. Should not happen. Exiting"
    exit 1
  else
    ALL_JOB_IDS="$(echo "${PIPELINE}" | jq -r '.jobs[] | select(type=="object" and has("status") and (.status == "running" or .status == "failed" or .status == "success" or .status == "pending")) | .id' | sort)"
    while IFS= read -r JOB_ID || [[ -n $JOB_ID ]]; do
      if [[ "${JOB_ID}" != "null" ]]; then
        if [ ! -f "${MYTMPDIR}/job_${JOB_ID}" ]; then
            touch "${MYTMPDIR}/job_${JOB_ID}"
            JOB_URL="$(echo "${PIPELINE}" | jq -r ".jobs[] | select(.id == ${JOB_ID}) | .web_url")"
            JOB_NAME="$(echo "${PIPELINE}" | jq -r ".jobs[] | select(.id == ${JOB_ID}) | .name")"
            JOB_STATUS="$(echo "${PIPELINE}" | jq -r ".jobs[] | select(.id == ${JOB_ID}) | .status")"
            log_info "Tracing job '${JOB_NAME}' ${JOB_ID} with status '${JOB_STATUS}' ..."
            log_info "Job '${JOB_NAME}' ${JOB_ID} URL is ${JOB_URL}"
            glab ci trace "${JOB_ID}" || true
        fi
      fi
    done < <(printf '%s' "$ALL_JOB_IDS")
  fi
}

trace_job_manual() {
  PIPELINE="$1"
  if [[ "[]" == "$(echo "${PIPELINE}" | jq -r '.jobs')" ]]; then
    log_error "'.jobs' is an empty array. Should not happen. Exiting"
    exit 1
  else
    ALL_JOB_IDS="$(echo "${PIPELINE}" | jq -r '.jobs[] | select(type=="object" and has("status") and (.status == "manual")) | .id' | sort)"
    while IFS= read -r JOB_ID || [[ -n $JOB_ID ]]; do
      if [[ "${JOB_ID}" != "null" ]]; then
        if [ ! -f "${MYTMPDIR}/job_${JOB_ID}" ]; then
            touch "${MYTMPDIR}/job_${JOB_ID}"
            JOB_URL="$(echo "${PIPELINE}" | jq -r ".jobs[] | select(.id == ${JOB_ID}) | .web_url")"
            JOB_NAME="$(echo "${PIPELINE}" | jq -r ".jobs[] | select(.id == ${JOB_ID}) | .name")"
            log_info "Tracing manual job '${JOB_NAME}' ${JOB_ID} ..."
            log_info "Job '${JOB_NAME}' ${JOB_ID} URL is ${JOB_URL}"
            glab ci trace "${JOB_ID}" || true
        fi
      fi
    done < <(printf '%s' "$ALL_JOB_IDS")
  fi
}

while true; do
  get_glab_output
  PIPELINE="$( echo "$GLAB_OUTPUT" | { jq -r '.' 2>/dev/null || echo '{}'; })"
  PIPELINE_ID="$(echo "${PIPELINE}" | jq -r '.id')"
  LAST_PIPELINE_STATUS='INIT'
  if [[ "${PIPELINE_ID}" == "${LAST_PIPELINE_ID}" ]]; then
    log_status "Waiting for new pipeline ..."
    sleep 1
  elif [[ "${PIPELINE_ID}" == 'null' ]]; then
    log_status "Waiting for new pipeline ..."
    sleep 1
  else
    LAST_PIPELINE_ID="${PIPELINE_ID}"
    while true; do
      get_glab_output
      PIPELINE="$( echo "$GLAB_OUTPUT" | { jq -r '.' 2>/dev/null || echo '{}'; })"
      PIPELINE_ID="$(echo "${PIPELINE}" | jq -r '.id')"
      PIPELINE_STATUS="$(echo "${PIPELINE}" | jq -r '.status')"
      if [[ "${PIPELINE_STATUS}" == "${LAST_PIPELINE_STATUS}" ]]; then
        NEW_PIPELINE_STATUS='false'
      else
        NEW_PIPELINE_STATUS='true'
        LAST_PIPELINE_STATUS="$(echo "${PIPELINE}" | jq -r '.status')"
      fi
      PIPELINE_URL="$(echo "${PIPELINE}" | jq -r '.web_url')"
      if [[ "${PIPELINE_ID}" == "${LAST_PIPELINE_ID}" ]]; then
        if [[ "${PIPELINE_STATUS}" == "running" ]]; then
          log_status "Pipeline ${PIPELINE_ID} changed to state 'running'"
          maybe_trace_job "$PIPELINE"
        elif [[ "${PIPELINE_STATUS}" == "pending" ]]; then
          log_status "Pipeline ${PIPELINE_ID} changed to state 'pending'"
          sleep 1
        elif [[ "${PIPELINE_STATUS}" == "created" ]]; then
          log_status "Pipeline ${PIPELINE_ID} changed to state 'created'"
          sleep 1
        elif [[ "${PIPELINE_STATUS}" == "null" ]]; then
          sleep 1
        elif [[ "${PIPELINE_STATUS}" == "skipped" ]]; then
          log_info "Pipeline ${PIPELINE_ID} changed to state 'skipped'"
          sleep 1
          break
        elif [[ "${PIPELINE_STATUS}" == "failed" ]]; then
          log_error "Pipeline ${PIPELINE_ID} changed to state 'failed'"
          log_error "Pipeline URL: ${PIPELINE_URL}"
          if [[ "[]" == "$(echo "${PIPELINE}" | jq -r '.jobs')" ]]; then
            log_error "No jobs / details available"
            break
          else
            maybe_trace_job "$PIPELINE"
            log_error "Pipeline ${PIPELINE_ID} failed"
            log_error "Pipeline URL is ${PIPELINE_URL}"
            break
          fi
        elif [[ "${PIPELINE_STATUS}" == "success" ]]; then
          maybe_trace_job "$PIPELINE"
          log_info "Pipeline ${PIPELINE_ID} succeeded"
          log_info "Pipeline URL is ${PIPELINE_URL}"
          break
        elif [[ "${PIPELINE_STATUS}" == "manual" ]]; then
          if [[ "${NEW_PIPELINE_STATUS}" == 'true' ]]; then
            log_info "Pipeline ${PIPELINE_ID} URL is ${PIPELINE_URL}"
          fi
          log_status "Pipeline ${PIPELINE_ID} changed to state 'manual'"
#          trace_job_manual "$PIPELINE"
          sleep 1
        else
          log_error "Unhandled pipeline status '${PIPELINE_STATUS}'"
          log_info "Pipeline ${PIPELINE_ID} URL is ${PIPELINE_URL}"
          sleep 1
        fi
      else
        log_info "Pipeline changed to ${PIPELINE_ID}"
        break
      fi
    done
  fi
done
