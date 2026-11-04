#!/usr/bin/env bash
set -euo pipefail

# Default configuration: tabpay organization
ORG="tabpay"
EXCLUDE_ME=false
ONLY_ME=false
EXCLUDE_BOTS=false
NO_DRAFTS=false
OUTPUT_JSON=false
FILTER_CONTRIBUTOR=""
USE_COLOR=true

if [[ ! -t 1 ]] || [[ -n "${NO_COLOR:-}" ]]; then
  USE_COLOR=false
fi

show_help() {
  cat << 'HELP'
Usage: arro-prs [options]

Fetch and organize all open pull requests for GitHub organization (default: tabpay),
grouped by contributor and sorted in descending order by last commit timestamp.

Options:
  -o, --org <org>            GitHub organization name (default: tabpay)
  -c, --contributor <user>   Filter by contributor username
      --exclude-me, --not-me Exclude PRs authored by the current GitHub user
      --only-me              Show only PRs authored by the current GitHub user
      --no-bots              Exclude bot PRs (e.g. dependabot)
      --no-drafts            Exclude draft PRs
      --no-color             Disable color output
      --json                 Output raw structured JSON
  -h, --help                 Show this help message
HELP
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--org)
      if [[ $# -lt 2 ]]; then
        echo "error: --org requires an argument" >&2
        exit 1
      fi
      ORG="$2"
      shift 2
      ;;
    -c|--contributor)
      if [[ $# -lt 2 ]]; then
        echo "error: --contributor requires an argument" >&2
        exit 1
      fi
      FILTER_CONTRIBUTOR="$2"
      shift 2
      ;;
    --exclude-me|--not-me)
      EXCLUDE_ME=true
      shift
      ;;
    --only-me)
      ONLY_ME=true
      shift
      ;;
    --no-bots)
      EXCLUDE_BOTS=true
      shift
      ;;
    --no-drafts)
      NO_DRAFTS=true
      shift
      ;;
    --no-color)
      USE_COLOR=false
      shift
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "error: 'gh' (GitHub CLI) is required but not found in PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: 'jq' is required but not found in PATH." >&2
  exit 1
fi

# Detect current authenticated user login
CURRENT_USER="$(gh api user --jq '.login' 2>/dev/null || echo "")"

# GraphQL query to paginate open PRs in organization
# shellcheck disable=SC2016
GRAPHQL_QUERY='
query($endCursor: String, $searchQuery: String!) {
  search(query: $searchQuery, type: ISSUE, first: 50, after: $endCursor) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on PullRequest {
        number
        title
        url
        isDraft
        reviewDecision
        author {
          login
          ... on User {
            name
          }
        }
        repository {
          nameWithOwner
        }
        commits(last: 1) {
          nodes {
            commit {
              committedDate
              statusCheckRollup {
                state
              }
            }
          }
        }
      }
    }
  }
}
'

SEARCH_QUERY="org:${ORG} is:pr is:open"

if [[ "$OUTPUT_JSON" == false ]]; then
  echo "Fetching open pull requests for organization '${ORG}'..." >&2
fi

RAW_DATA="$(gh api graphql --paginate --slurp \
  -f query="$GRAPHQL_QUERY" \
  -F searchQuery="$SEARCH_QUERY")"

# Setup color definitions
if [[ "$USE_COLOR" == true ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_GREEN=""
  C_RED=""
  C_YELLOW=""
  C_BLUE=""
  C_MAGENTA=""
  C_CYAN=""
fi

PROCESSED_JSON="$(echo "$RAW_DATA" | jq \
  --arg me "$CURRENT_USER" \
  --argjson exclude_me "$EXCLUDE_ME" \
  --argjson only_me "$ONLY_ME" \
  --argjson exclude_bots "$EXCLUDE_BOTS" \
  --argjson no_drafts "$NO_DRAFTS" \
  --arg contributor "$FILTER_CONTRIBUTOR" \
  '
  def is_bot(login):
    (login == "dependabot" or (login | endswith("[bot]")) or (login | startswith("app/")));

  [.[].data.search.nodes[]]
  | map({
      repo: .repository.nameWithOwner,
      number: .number,
      title: .title,
      url: .url,
      isDraft: .isDraft,
      author_login: (.author.login // "ghost"),
      author_name: (.author.name // ""),
      last_commit: (.commits.nodes[0].commit.committedDate // "1970-01-01T00:00:00Z"),
      checks: (.commits.nodes[0].commit.statusCheckRollup.state // "NO_CHECKS"),
      review: (.reviewDecision // "NONE")
    })
  | if $no_drafts then map(select(.isDraft | not)) else . end
  | if $exclude_bots then map(select(is_bot(.author_login) | not)) else . end
  | if $exclude_me and ($me != "") then map(select(.author_login != $me)) else . end
  | if $only_me and ($me != "") then map(select(.author_login == $me)) else . end
  | if $contributor != "" then map(select(.author_login == $contributor)) else . end
  | group_by(.author_login)
  | map({
      contributor: .[0].author_login,
      name: .[0].author_name,
      prs: (sort_by(.last_commit) | reverse),
      latest_commit: (map(.last_commit) | max)
    })
  | sort_by(.latest_commit)
  | reverse
')"

if [[ "$OUTPUT_JSON" == true ]]; then
  echo "$PROCESSED_JSON"
  exit 0
fi

# Render formatted output
echo "$PROCESSED_JSON" | jq -r \
  --arg org "$ORG" \
  --arg c_reset "$C_RESET" \
  --arg c_bold "$C_BOLD" \
  --arg c_dim "$C_DIM" \
  --arg c_green "$C_GREEN" \
  --arg c_red "$C_RED" \
  --arg c_yellow "$C_YELLOW" \
  --arg c_blue "$C_BLUE" \
  --arg c_magenta "$C_MAGENTA" \
  --arg c_cyan "$C_CYAN" \
  '
  def reltime(d):
    (try (d | fromdateiso8601) catch null) as $ts
    | if $ts == null then "unknown"
      else
        (now - $ts) as $diff
        | if $diff < 0 then "just now"
          elif $diff < 60 then "\($diff | floor)s ago"
          elif $diff < 3600 then "\($diff / 60 | floor)m ago"
          elif $diff < 86400 then "\($diff / 3600 | floor)h ago"
          else "\($diff / 86400 | floor)d ago"
          end
      end;

  def fmt_checks(st):
    if st == "SUCCESS" then "\($c_green)✔ SUCCESS\($c_reset)"
    elif st == "FAILURE" then "\($c_red)✖ FAILURE\($c_reset)"
    elif st == "ERROR" then "\($c_red)✖ ERROR\($c_reset)"
    elif st == "PENDING" then "\($c_yellow)● PENDING\($c_reset)"
    elif st == "EXPECTED" then "\($c_cyan)○ EXPECTED\($c_reset)"
    else "\($c_dim)- NO CHECKS\($c_reset)"
    end;

  def fmt_review(rv):
    if rv == "APPROVED" then " \($c_green)[APPROVED]\($c_reset)"
    elif rv == "CHANGES_REQUESTED" then " \($c_red)[CHANGES REQUESTED]\($c_reset)"
    elif rv == "REVIEW_REQUIRED" then " \($c_yellow)[REVIEW REQUIRED]\($c_reset)"
    else ""
    end;

  . as $groups
  | ($groups | map(.prs | length) | add // 0) as $total_prs
  | ($groups | length) as $total_contribs
  | if $total_prs == 0 then
      "\n\($c_dim)No open pull requests found for \($org).\($c_reset)\n"
    else
      "\n\($c_bold)\($c_cyan)Organization: \($org) (\($total_prs | tostring) open PRs across \($total_contribs | tostring) contributor(s))\($c_reset)\n" +
      (
        $groups | map(
          "\($c_bold)\($c_cyan)👤 Contributor: @\(.contributor)\(if .name != "" then " (" + .name + ")" else "" end) [\((.prs | length) | tostring) open PR(s)]\($c_reset)\n" +
          (
            .prs | map(
              "  • [" + fmt_checks(.checks) + "] \($c_bold)\(.repo)#\(.number | tostring)\($c_reset)\(if .isDraft then " \($c_dim)[DRAFT]\($c_reset)" else "" end)" + fmt_review(.review) + " - \(.title)\n" +
              "    \($c_dim)Link:\($c_reset)       \(.url)\n" +
              "    \($c_dim)Opened by:\($c_reset)  \($c_bold)@\(.author_login)\($c_reset)\(if .author_name != "" then " (" + .author_name + ")" else "" end)\n" +
              "    \($c_dim)Last commit:\($c_reset) \(.last_commit) \($c_dim)(\(reltime(.last_commit)))\($c_reset)"
            ) | join("\n\n")
          )
        ) | join("\n\n")
      ) + "\n"
    end
'
