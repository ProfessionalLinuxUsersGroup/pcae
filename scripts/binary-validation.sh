#!/bin/bash

# Targeting mdBook version v0.4.52 as of Aug, 2025
# Only requests 5 latest release records, remove ?per_page=5 to fetch all
# Requires mdBook semantic version input from command line
# For example 'binary-validation.sh v0.1.15'

set -eo pipefail

[[ -z $1 ]] && printf "Requires a version, ex: v0.4.52\n" && exit 1

declare MDBOOK_VERSION="$1"
declare SKIP_DIGEST=0
declare INTERACTIVE=0

shift;

declare json
declare zip


cleanup() {
    [[ -e "$zip" ]] && rm -f "$zip"
}
trap 'printf "Cleaning up...\n"; cleanup;' EXIT SIGINT 

while [[ -n $1 && $1 =~ ^- ]]; do
    case "$1" in
        -s|--skip-digest)
            SKIP_DIGEST=1
            shift;
            ;;
        -i|--interactive)
            INTERACTIVE=1
            shift;
            ;;
        *)
            printf >&2 "Unknown argument!\n" 
            exit 1;
            ;;
    esac
done

# If the mdbook version is pre-digest version (<0.4.52), ask for user validation
# v0.3.56
insecure-download() {
    if [[ $INTERACTIVE -gt 0 ]]; then
        local -l choice
        printf "This version of mdBook (%s) pre-dates the SHA digest feature of the GitHub API.\n" "$MDBOOK_VERSION"
        read -r -p "Do you want to continue [y/N]? " choice
        case $choice in
            y*)
                printf "Proceeding with insecure download.\n"
                return 0
                ;;
            n*)
                printf "Cancelling download.\n"
                return 1
                ;;
            *)
                printf "Bad choice! \n"
                return 1
                ;;
        esac
    else
        printf "Non-interactive download, proceeding...\n"
        return 0
    fi
}

json_setup() {

    if [[ ! $MDBOOK_VERSION =~ v ]]; then
        MDBOOK_VERSION="v${MDBOOK_VERSION}"
    fi
	local jquery="
	map(select(.tag_name==\"${MDBOOK_VERSION}\"))
	| .[].assets
	| map(select(.name==\"mdbook-${MDBOOK_VERSION}-x86_64-unknown-linux-gnu.tar.gz\"))
	"
	printf "mdBook Binary script executing...\n"
	printf "Querying GH API for JSON %s mdBook record...\n" "${MDBOOK_VERSION}"

	json="$(curl -sL \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		https://api.github.com/repos/rust-lang/mdBook/releases?per_page=10 \
		| jq "${jquery}")" ||
		{
			printf "Something went wrong with the GH API request. Consider adding set -x flag.\n" 1>&2
			exit 1
		}

	# TODO Implement GH TOKEN in the future?
	# gh api repos/rust-lang/mdBook/releases?per_page=5 --jq "${jquery}" > "${json}"||
	# 	{
	# 		printf "Something may have gone wrong with the GH API request.\n" >&2
	# 		exit 1
	# 	}
}


check-digest(){
    [[ $SKIP_DIGEST -eq 0 ]] || return 0
	local api_digest
    local zip_digest
    api_digest="$(jq -r '.[].digest' <<<"${json}" | cut -d: -f2)"
    zip_digest=$(sha256sum "./${zip}" | awk '{print $1}')

    if [[ "$api_digest" == 'null' && $INTERACTIVE -gt 0 ]]; then
        insecure-download || {
            printf >&2 "Could not proceed with download.\n" && exit 1
        }
        return 0
    elif [[ "$api_digest" == null ]]; then
        return 0
    fi

    printf "%3s %s\n" "API_DIGEST:" "${api_digest}" "ZIP:" "${zip}"
    printf "\nFetching binary...\nCalculating ZIP digest...\n\n"

    printf "\nZIP_DIGEST: %s\n\n" "${zip_digest}"
    printf "Difference:\n\t%s\n\t%s\n\n" "$api_digest" "$zip_digest"

    if [[ "$api_digest" == 'null' ]]; then
        printf "Digest could not be gathered from the API, likely an older version (<0.4.52).\n"
    fi

    if [[ "${api_digest}" = "${zip_digest}" ]]; then
        printf "Digest check succeeded!\nCleaning up...\nmdBook binary unzipped and ready for execution!"
        return 0

    else
        printf "\nThe API digest appears to be different than the downloaded binary digest:"
        printf "\n%2s %s" "API sha:" "${api_digest}" "ZIP sha:" "${zip_digest}"
        printf "\n\nDumping JSON record and cleaning up...\n\n"
        echo "${json}" | jq '.'
        return 1
    fi

}


api_fetch() {
	local dl_url

	if [[ -n "${json}" ]]; then
		printf "Parsing API JSON return data and assigning variables...\n\n"

        dl_url="$(jq -r '.[].browser_download_url' <<<"${json}")"
        zip="$(jq -r '.[].name' <<< "${json}")"
        printf "%3s %s\n" "URL:" "${dl_url}" 

        curl -LO --progress-bar "$dl_url" || {
            printf >&2 "[ERROR]: Failed to download mkBook binary!\n" && return 1
        }
        tar xfz "${zip}"
	else
		printf "\nThe processed JSON record appears to be empty, queried version may not exist...\nExiting..."
		return 1
	fi

}

reg_pattern='^v?([0-9]{1,}\.[0-9]{1,}\.[0-9]{1,}$)'

if [[ "$MDBOOK_VERSION" =~ $reg_pattern ]]; then

	json_setup
	api_fetch
    check-digest || {
        printf >&2 "[ERROR]: Digest check failed!\n" && exit 1
    }

else
	printf "This script requires an mdBook version as an argument and to observe mdBook's semantic versioning, for example 'binary-validation.sh v0.4.20'"
	exit 1
fi
